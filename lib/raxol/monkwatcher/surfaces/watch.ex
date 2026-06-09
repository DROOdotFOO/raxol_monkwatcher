defmodule Raxol.Monkwatcher.Surfaces.Watch do
  @moduledoc """
  Translates broadcast alerts into watch-shaped push notifications.

  Notification copy rules locked here:
    * Title varies with current activity (`"Monks"`, `"Crabs"`, ...) for
      idle/hits/death; level-up uses the skill name (`"Defence"`).
    * No emoji in any field — watchOS rendering is inconsistent.
    * `:critical` (4:40) drops the action button — at that point the user
      should glance and act, not read button labels.

  Pure `to_notification/1` is the contract surface; the GenServer is a
  thin shell that subscribes to PubSub and forwards translated notifications
  to an injected `send_fn` (default: drop the message — production wires it
  to a real APNS adapter).
  """
  use GenServer

  alias Raxol.Monkwatcher.{Activity, Channels}

  # --- pure translation ---

  def to_notification({:idle_alert, :warning, model, _now}) do
    %{
      title: Activity.title(model),
      body: "4:00",
      priority: :normal,
      actions: [%{id: "snooze", label: "+60s"}]
    }
  end

  def to_notification({:idle_alert, :critical, model, _now}) do
    %{
      title: Activity.title(model),
      body: "Click!",
      priority: :high
    }
  end

  def to_notification({:milestone, :hits, n, model, _now}) do
    %{
      title: Activity.title(model),
      body: Integer.to_string(n),
      priority: :normal
    }
  end

  def to_notification({:milestone, :level, {skill, n}}) when is_atom(skill) do
    %{
      title: skill |> Atom.to_string() |> String.capitalize(),
      body: Integer.to_string(n),
      priority: :normal
    }
  end

  def to_notification({:death, model, _now}) do
    %{
      title: Activity.title(model),
      body: "Died.",
      priority: :high
    }
  end

  # --- GenServer ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    send_fn = Keyword.get(opts, :send_fn, &drop/1)
    :ok = Phoenix.PubSub.subscribe(pubsub, Channels.alerts())
    {:ok, %{send_fn: send_fn}}
  end

  @impl true
  def handle_info(payload, state) do
    state.send_fn.(to_notification(payload))
    {:noreply, state}
  end

  defp drop(_notification), do: :ok
end
