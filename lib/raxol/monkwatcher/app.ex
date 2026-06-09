defmodule Raxol.Monkwatcher.App do
  @moduledoc """
  TEA runtime as a thin GenServer shell. Holds the model, dispatches
  inbound messages to the appropriate `Updaters` function based on shape,
  and executes the returned commands by broadcasting on `Phoenix.PubSub`.

  Three injection points keep tests deterministic without mocks:
    * `:pubsub` — name of the PubSub server to broadcast on
    * `:now_fn` — clock function for `init/1` model bootstrapping and
      time-dependent updaters like `snooze`
    * `:name` — process registration name (default: `__MODULE__`)
  """
  use GenServer

  alias Raxol.Monkwatcher.{Channels, Model, Notifications, View}
  alias Raxol.Monkwatcher.App.Updaters
  alias Raxol.Monkwatcher.Plugin.Codec.{Event, Tick}

  @known_skills %{
    "attack" => :attack,
    "strength" => :strength,
    "defence" => :defence,
    "hitpoints" => :hitpoints,
    "ranged" => :ranged,
    "magic" => :magic,
    "prayer" => :prayer
  }

  # --- public API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def dispatch(msg, name \\ __MODULE__) do
    GenServer.cast(name, {:dispatch, msg})
  end

  def view(name \\ __MODULE__) do
    GenServer.call(name, :view)
  end

  def get_model(name \\ __MODULE__) do
    GenServer.call(name, :get_model)
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    now_fn = Keyword.get(opts, :now_fn, &default_now/0)
    pubsub = Keyword.get(opts, :pubsub, Raxol.Monkwatcher.PubSub)

    state = %{
      model: Model.new(now_fn.()),
      pubsub: pubsub,
      now_fn: now_fn
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:dispatch, msg}, state) do
    {new_model, commands} = apply_update(msg, state)
    Enum.each(commands, &execute(&1, state.pubsub))
    {:noreply, %{state | model: new_model}}
  end

  @impl true
  def handle_call(:view, _from, state) do
    {:reply, View.render(state.model, state.now_fn.()), state}
  end

  def handle_call(:get_model, _from, state) do
    {:reply, state.model, state}
  end

  # --- routing ---

  defp apply_update(%Tick{} = tick, state),
    do: Updaters.plugin_tick(state.model, tick)

  defp apply_update(%Event{type: "monk_killed", data: data, t: t}, state),
    do: Updaters.monk_killed(state.model, data, t)

  defp apply_update(%Event{type: "player_death", t: t}, state),
    do: Updaters.player_death(state.model, t)

  defp apply_update(
         %Event{type: "level_up", data: %{"skill" => skill_str, "level" => level}},
         state
       )
       when is_integer(level) do
    case parse_skill(skill_str) do
      nil -> {state.model, []}
      skill -> {state.model, [Notifications.level_up_command(skill, level)]}
    end
  end

  defp apply_update({:scroll, delta}, state) when is_integer(delta),
    do: Updaters.scroll(state.model, delta)

  defp apply_update({:snooze, ms}, state) when is_integer(ms),
    do: Updaters.snooze(state.model, ms, state.now_fn.())

  defp apply_update(_unknown, state),
    do: {state.model, []}

  # --- command execution ---

  defp execute({:broadcast_alert, payload}, pubsub) do
    Phoenix.PubSub.broadcast(pubsub, Channels.alerts(), payload)
  end

  defp execute(_other, _pubsub), do: :ok

  # --- helpers ---

  defp parse_skill(s) when is_binary(s), do: Map.get(@known_skills, s)
  defp parse_skill(_), do: nil

  defp default_now, do: System.system_time(:millisecond)
end
