defmodule Raxol.Monkwatcher.Plugin.Bridge do
  @moduledoc """
  Consumes the RuneLite plugin's UDS stream. Connects to the socket,
  line-decodes JSON, dispatches each decoded message via an injected
  `dispatch_fn` (default: `&App.dispatch/1`).

  Reconnects with exponential backoff (500ms -> 10s cap) so RuneLite and
  Raxol can start in any order and either side can restart independently.

  The injected `dispatch_fn` is the single seam — tests use it to assert
  on dispatched messages without starting `App`.
  """
  use GenServer
  require Logger

  alias Raxol.Monkwatcher.App
  alias Raxol.Monkwatcher.Plugin.Codec

  @reconnect_base_ms 500
  @reconnect_max_ms 10_000

  defstruct [:socket_path, :socket, :backoff_ms, :dispatch_fn]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      socket_path: Keyword.fetch!(opts, :socket_path),
      dispatch_fn: Keyword.get(opts, :dispatch_fn, &App.dispatch/1),
      backoff_ms: @reconnect_base_ms
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case :gen_tcp.connect({:local, state.socket_path}, 0,
           mode: :binary,
           active: :once,
           packet: :line
         ) do
      {:ok, socket} ->
        Logger.info("Plugin.Bridge connected to #{state.socket_path}")
        {:noreply, %{state | socket: socket, backoff_ms: @reconnect_base_ms}}

      {:error, reason} ->
        Logger.debug(
          "Plugin.Bridge connect failed: #{inspect(reason)}, retry in #{state.backoff_ms}ms"
        )

        Process.send_after(self(), :connect, state.backoff_ms)
        {:noreply, %{state | backoff_ms: min(state.backoff_ms * 2, @reconnect_max_ms)}}
    end
  end

  def handle_info({:tcp, socket, line}, %{socket: socket} = state) do
    case Codec.decode(line) do
      {:ok, msg} ->
        state.dispatch_fn.(msg)

      {:error, reason} ->
        Logger.warning("Plugin.Bridge bad line: #{inspect(reason)}")
    end

    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Plugin.Bridge socket closed, reconnecting")
    send(self(), :connect)
    {:noreply, %{state | socket: nil}}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("Plugin.Bridge tcp_error: #{inspect(reason)}")
    send(self(), :connect)
    {:noreply, %{state | socket: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}
end
