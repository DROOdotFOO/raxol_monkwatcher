defmodule Raxol.Monkwatcher.Surfaces.Telegram do
  @moduledoc """
  Formats and pushes Telegram pinned-message updates.

  Format: `"<idle_mmss> * <hits> hits * <level> <skill_code> * <hp>/<max_hp>"`
  Example: `"4:12 * 247 hits * 74 def * 67/85"`

  Pure `format_pinned/2` is the contract; the GenServer is a thin shell.
  Tests inject `send_fn` to capture outbound text without hitting the
  Telegram Bot API.
  """
  use GenServer

  alias Raxol.Monkwatcher.{Channels, StateMachine}
  alias Raxol.Monkwatcher.View.Components

  @skill_codes %{
    attack: "att",
    strength: "str",
    defence: "def",
    hitpoints: "hp",
    ranged: "range",
    magic: "mage",
    prayer: "pray"
  }

  # --- pure formatting ---

  @spec format_pinned(map, integer) :: String.t()
  def format_pinned(model, now) do
    idle = Components.format_mmss(idle_ms(model.sm, now))
    hits = Components.format_count(model.session.monks_killed)
    skill = skill_segment(model.player.skill, model.player.skill_level)
    vitals = vitals_segment(model.player.hp, model.player.max_hp)

    "#{idle} * #{hits} hits * #{skill} * #{vitals}"
  end

  defp idle_ms(%StateMachine{state: :idle} = sm, now), do: StateMachine.time_in_state_ms(sm, now)
  defp idle_ms(_sm, _now), do: 0

  defp skill_segment(nil, _), do: "-"
  defp skill_segment(_, nil), do: "-"

  defp skill_segment(skill, level) when is_atom(skill) and is_integer(level) do
    code = Map.get(@skill_codes, skill, Atom.to_string(skill))
    "#{level} #{code}"
  end

  defp vitals_segment(nil, _), do: "-/-"
  defp vitals_segment(_, nil), do: "-/-"
  defp vitals_segment(hp, max_hp), do: "#{hp}/#{max_hp}"

  # --- GenServer ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    send_fn = Keyword.get(opts, :send_fn, &drop/1)
    chat_id = Keyword.get(opts, :chat_id)
    :ok = Phoenix.PubSub.subscribe(pubsub, Channels.alerts())
    {:ok, %{send_fn: send_fn, chat_id: chat_id}}
  end

  @impl true
  def handle_info({:idle_alert, _level, model, now}, state) do
    state.send_fn.(format_pinned(model, now))
    {:noreply, state}
  end

  def handle_info({:milestone, :hits, _n, model, now}, state) do
    state.send_fn.(format_pinned(model, now))
    {:noreply, state}
  end

  def handle_info({:death, model, now}, state) do
    state.send_fn.(format_pinned(model, now))
    {:noreply, state}
  end

  # Level-up payload has no model attached — emit a short status line.
  def handle_info({:milestone, :level, {skill, level}}, state) do
    code = Map.get(@skill_codes, skill, Atom.to_string(skill))
    state.send_fn.("level up: #{level} #{code}")
    {:noreply, state}
  end

  defp drop(_text), do: :ok
end
