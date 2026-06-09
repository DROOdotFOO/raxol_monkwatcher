defmodule Raxol.Monkwatcher.StateMachine do
  @moduledoc """
  Pure functional state machine over plugin tick payloads.

  States: :unknown, :logged_out, :fighting, :recovering, :idle, :dead.
  """

  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  @attack_animations MapSet.new([
                       # unarmed
                       422, 423, 1156, 1157, 1162,
                       # melee weapons
                       386, 390, 393, 400, 401, 406, 407, 412
                     ])

  @recovery_window_ms 30_000
  @warning_idle_ms 240_000
  @critical_idle_ms 280_000

  defstruct state: :unknown,
            state_since_ms: nil,
            last_combat_ms: nil,
            last_tick: nil,
            notified: MapSet.new()

  def new, do: %__MODULE__{}

  def apply_tick(%__MODULE__{} = sm, %Tick{} = tick) do
    cond do
      fighting?(tick) ->
        sm
        |> transition(:fighting, tick.t)
        |> Map.put(:last_combat_ms, tick.t)
        |> Map.put(:notified, MapSet.new())
        |> Map.put(:last_tick, tick.tick)

      recovering?(sm, tick.t) ->
        sm
        |> transition(:recovering, tick.t)
        |> Map.put(:last_tick, tick.tick)

      true ->
        sm
        |> transition(:idle, tick.t)
        |> Map.put(:last_tick, tick.tick)
    end
  end

  defp fighting?(%Tick{is_monk: true}), do: true
  defp fighting?(%Tick{anim: anim}), do: MapSet.member?(@attack_animations, anim)

  defp recovering?(%__MODULE__{last_combat_ms: nil}, _now), do: false

  defp recovering?(%__MODULE__{last_combat_ms: last}, now),
    do: now - last < @recovery_window_ms

  defp transition(%__MODULE__{state: same} = sm, same, _now), do: sm
  defp transition(sm, new_state, now), do: %{sm | state: new_state, state_since_ms: now}

  @doc "Returns {sm, [:warning | :critical, ...]} for thresholds newly crossed."
  def check_thresholds(%__MODULE__{state: :idle, state_since_ms: since} = sm, now)
      when is_integer(since) do
    idle_for = now - since

    fires =
      []
      |> maybe_fire(:warning, idle_for >= @warning_idle_ms, sm.notified)
      |> maybe_fire(:critical, idle_for >= @critical_idle_ms, sm.notified)

    new_notified = Enum.reduce(fires, sm.notified, &MapSet.put(&2, &1))
    {%{sm | notified: new_notified}, fires}
  end

  def check_thresholds(sm, _now), do: {sm, []}

  @doc "How long the player has been in the current state."
  def time_in_state_ms(%__MODULE__{state_since_ms: nil}, _now), do: 0
  def time_in_state_ms(%__MODULE__{state_since_ms: since}, now), do: now - since

  defp maybe_fire(acc, level, true, notified) do
    if MapSet.member?(notified, level), do: acc, else: [level | acc]
  end

  defp maybe_fire(acc, _level, false, _notified), do: acc
end
