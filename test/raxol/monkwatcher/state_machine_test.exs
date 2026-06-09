defmodule Raxol.Monkwatcher.StateMachineTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.StateMachine
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  describe "new/0" do
    test "starts in :unknown with no state timestamp" do
      sm = StateMachine.new()

      assert sm.state == :unknown
      assert sm.state_since_ms == nil
      assert sm.last_combat_ms == nil
    end
  end

  describe "apply_tick/2 — state determination" do
    test "is_monk: true transitions to :fighting" do
      tick = %Tick{t: 1_000, tick: 1, is_monk: true, anim: nil}
      sm = StateMachine.new() |> StateMachine.apply_tick(tick)

      assert sm.state == :fighting
      assert sm.state_since_ms == 1_000
      assert sm.last_combat_ms == 1_000
    end

    test "known attack animation transitions to :fighting" do
      tick = %Tick{t: 2_000, tick: 1, is_monk: false, anim: 386}
      sm = StateMachine.new() |> StateMachine.apply_tick(tick)

      assert sm.state == :fighting
    end

    test "non-combat tick from a fresh machine goes to :idle" do
      tick = %Tick{t: 3_000, tick: 1, is_monk: false, anim: -1}
      sm = StateMachine.new() |> StateMachine.apply_tick(tick)

      assert sm.state == :idle
      assert sm.state_since_ms == 3_000
    end

    test "non-combat tick within recovery window stays :recovering" do
      sm = StateMachine.new() |> StateMachine.apply_tick(combat_tick(10_000))
      sm = StateMachine.apply_tick(sm, idle_tick(15_000))

      assert sm.state == :recovering
    end

    test "non-combat tick after recovery window expires becomes :idle" do
      sm = StateMachine.new() |> StateMachine.apply_tick(combat_tick(10_000))
      sm = StateMachine.apply_tick(sm, idle_tick(50_000))

      assert sm.state == :idle
    end
  end

  describe "check_thresholds/2" do
    test "fires nothing before 4:00 of continuous idle" do
      sm = StateMachine.new() |> StateMachine.apply_tick(idle_tick(0))
      {_sm, fires} = StateMachine.check_thresholds(sm, 239_999)

      assert fires == []
    end

    test "fires :warning at exactly 4:00 of continuous idle" do
      sm = StateMachine.new() |> StateMachine.apply_tick(idle_tick(0))
      {sm, fires} = StateMachine.check_thresholds(sm, 240_000)

      assert fires == [:warning]
      assert MapSet.member?(sm.notified, :warning)
    end

    test "does not re-fire :warning while still idle" do
      sm = StateMachine.new() |> StateMachine.apply_tick(idle_tick(0))
      {sm, _} = StateMachine.check_thresholds(sm, 240_000)
      {_sm, fires} = StateMachine.check_thresholds(sm, 250_000)

      assert fires == []
    end

    test "fires :critical at 4:40 in addition to :warning" do
      sm = StateMachine.new() |> StateMachine.apply_tick(idle_tick(0))
      {_sm, fires} = StateMachine.check_thresholds(sm, 280_000)

      assert :warning in fires
      assert :critical in fires
    end

    test "returns no fires when not in :idle" do
      sm = StateMachine.new() |> StateMachine.apply_tick(combat_tick(0))
      {_sm, fires} = StateMachine.check_thresholds(sm, 1_000_000)

      assert fires == []
    end
  end

  describe "time_in_state_ms/2" do
    test "returns 0 for a fresh machine (state_since_ms == nil)" do
      assert StateMachine.time_in_state_ms(StateMachine.new(), 1_000) == 0
    end

    test "returns elapsed ms since state_since_ms was set" do
      sm = StateMachine.new() |> StateMachine.apply_tick(idle_tick(1_000))
      assert StateMachine.time_in_state_ms(sm, 4_500) == 3_500
    end
  end

  describe "threshold properties (spec)" do
    property ":warning never fires before 4:00 of continuous idle" do
      check all duration_ms <- integer(0..239_000) do
        fires = collect_fires(idle_ticks(0, duration_ms))
        assert :warning not in fires
      end
    end

    property ":warning fires exactly once per continuous idle period" do
      check all duration_ms <- integer(240_000..279_000) do
        fires = collect_fires(idle_ticks(0, duration_ms))
        assert Enum.count(fires, &(&1 == :warning)) == 1
      end
    end

    property "any combat tick resets the notification set" do
      check all idle1_ms <- integer(240_000..250_000),
                idle2_ms <- integer(240_000..250_000) do
        combat_t = idle1_ms + 1_000
        idle2_start = combat_t + 31_000

        stream =
          idle_ticks(0, idle1_ms) ++
            [combat_tick(combat_t)] ++
            idle_ticks(idle2_start, idle2_ms)

        fires = collect_fires(stream)
        assert Enum.count(fires, &(&1 == :warning)) == 2
      end
    end
  end

  defp combat_tick(t), do: %Tick{t: t, tick: 1, is_monk: true, anim: nil}
  defp idle_tick(t), do: %Tick{t: t, tick: 1, is_monk: false, anim: -1}

  defp idle_ticks(start_t, duration_ms) do
    n = div(duration_ms, 1000)
    for i <- 0..n, do: idle_tick(start_t + i * 1000)
  end

  defp collect_fires(stream) do
    {_sm, fires} =
      Enum.reduce(stream, {StateMachine.new(), []}, fn tick, {sm, acc} ->
        sm = StateMachine.apply_tick(sm, tick)
        {sm, new_fires} = StateMachine.check_thresholds(sm, tick.t)
        {sm, acc ++ new_fires}
      end)

    fires
  end
end
