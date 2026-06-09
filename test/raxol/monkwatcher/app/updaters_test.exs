defmodule Raxol.Monkwatcher.App.UpdatersTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Model
  alias Raxol.Monkwatcher.App.Updaters
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  describe "monk_killed/3" do
    test "emits no command on a non-milestone kill" do
      model = Model.new(0)
      {_model, commands} = Updaters.monk_killed(model, %{}, 1)

      assert commands == []
    end

    test "the 100th kill emits a milestone broadcast command" do
      model =
        Enum.reduce(1..99, Model.new(0), fn i, m ->
          {m, _} = Updaters.monk_killed(m, %{}, i)
          m
        end)

      {model, commands} = Updaters.monk_killed(model, %{}, 100)

      assert model.session.monks_killed == 100
      assert [{:broadcast_alert, {:milestone, :hits, 100, _model, 100}}] = commands
    end
  end

  describe "plugin_tick/2" do
    test "advances StateMachine to :fighting on a combat tick" do
      model = Model.new(0)
      tick = combat_tick(1_000)

      {model, _commands} = Updaters.plugin_tick(model, tick)

      assert model.sm.state == :fighting
      assert model.sm.last_combat_ms == 1_000
    end

    test "advances StateMachine to :idle on a non-combat tick" do
      model = Model.new(0)
      tick = idle_tick(2_000)

      {model, _commands} = Updaters.plugin_tick(model, tick)

      assert model.sm.state == :idle
    end

    test "copies player vitals from the tick into the model" do
      model = Model.new(0)
      tick = %{idle_tick(3_000) | hp: 67, max_hp: 85, prayer: 31, max_prayer: 82, run_energy: 40}

      {model, _commands} = Updaters.plugin_tick(model, tick)

      assert model.player.hp == 67
      assert model.player.max_hp == 85
      assert model.player.prayer == 31
      assert model.player.max_prayer == 82
      assert model.player.run_energy == 40
    end

    test "records location as {x, y, plane}" do
      model = Model.new(0)
      tick = %{idle_tick(4_000) | x: 3001, y: 3502, plane: 0}

      {model, _commands} = Updaters.plugin_tick(model, tick)

      assert model.player.location == {3001, 3502, 0}
    end

    test "advances pet target_mood from the new model state" do
      model = Model.new(0)
      # Combat tick -> sm.state :fighting -> default mood :content
      {model, _} = Updaters.plugin_tick(model, combat_tick(0))
      assert model.pet.target_mood == :content
    end

    test "no commands on a normal idle tick" do
      model = Model.new(0)
      {_model, commands} = Updaters.plugin_tick(model, idle_tick(1_000))
      assert commands == []
    end

    test "emits an idle_alert :warning command after 4:00 of continuous idle" do
      model = Model.new(0)

      {model, _} = Updaters.plugin_tick(model, idle_tick(0))
      {_model, commands} = Updaters.plugin_tick(model, idle_tick(240_000))

      assert [{:broadcast_alert, {:idle_alert, :warning, _model_snapshot, 240_000}}] = commands
    end

    test "suppresses idle_alert commands while muted_until_ms is in the future" do
      model = Model.new(0) |> Map.put(:muted_until_ms, 999_999_999)

      {model, _} = Updaters.plugin_tick(model, idle_tick(0))
      {_model, commands} = Updaters.plugin_tick(model, idle_tick(240_000))

      assert commands == []
    end
  end

  describe "player_death/2" do
    test "increments deaths in the session" do
      model = Model.new(0)
      {model, _} = Updaters.player_death(model, 1_000)

      assert model.session.deaths == 1
    end

    test "transitions sm.state to :dead with state_since_ms set to now" do
      model = Model.new(0)
      {model, _} = Updaters.player_death(model, 5_000)

      assert model.sm.state == :dead
      assert model.sm.state_since_ms == 5_000
    end

    test "sets pet target_mood to :fainted" do
      model = Model.new(0)
      {model, _} = Updaters.player_death(model, 1_000)

      assert model.pet.target_mood == :fainted
    end

    test "emits a death broadcast command" do
      model = Model.new(0)
      {_model, commands} = Updaters.player_death(model, 1_000)

      assert [{:broadcast_alert, {:death, _model_snapshot, 1_000}}] = commands
    end
  end

  describe "snooze/3" do
    test "sets muted_until_ms to now + ms" do
      model = Model.new(0)
      {model, commands} = Updaters.snooze(model, 60_000, 1_700_000_000_000)

      assert model.muted_until_ms == 1_700_000_060_000
      assert commands == []
    end
  end

  describe "scroll/2" do
    test "delegates to Fidget.scroll/2" do
      model = Model.new(0)
      {model, commands} = Updaters.scroll(model, 15)

      assert model.fidget.scroll_position == 15
      assert commands == []
    end

    test "view cycles past threshold via delegation" do
      model = Model.new(0)
      {model, _} = Updaters.scroll(model, 31)

      assert model.fidget.view_mode == :history
      assert model.fidget.scroll_position == 0
    end
  end

  defp combat_tick(t),
    do: %Tick{t: t, tick: 1, is_monk: true, anim: nil}

  defp idle_tick(t),
    do: %Tick{t: t, tick: 1, is_monk: false, anim: -1}
end
