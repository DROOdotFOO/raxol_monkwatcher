defmodule Raxol.Monkwatcher.View.PetViewTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Model
  alias Raxol.Monkwatcher.View.PetView
  alias Raxol.Monkwatcher.App.Updaters
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  describe "render/2" do
    test "produces a non-empty multi-line string" do
      rendered = PetView.render(Model.new(0), 0)
      assert is_binary(rendered)
      assert length(String.split(rendered, "\n")) > 5
    end

    test "header shows the formatted session time" do
      model = Model.new(0)
      assert PetView.render(model, 60_000) =~ "0:01:00"
    end

    test "header shows 'Training {Skill}' when a skill is reported in the latest tick" do
      tick = %Tick{
        t: 1_000,
        tick: 1,
        is_monk: true,
        anim: nil,
        skill: :defence,
        skill_xp: 1_210_421,
        skill_level: 75
      }

      {model, _} = Updaters.plugin_tick(Model.new(0), tick)
      assert PetView.render(model, 1_000) =~ "Training Defence"
    end

    test "header falls back to 'Combat' when no skill tick has arrived" do
      assert PetView.render(Model.new(0), 0) =~ "Combat"
    end

    test "right rail shows the current state in uppercase" do
      {model, _} = Updaters.plugin_tick(Model.new(0), combat_tick(0))
      assert PetView.render(model, 1_000) =~ "FIGHTING"
    end

    test "right rail shows skill name + current level when available" do
      tick = %Tick{
        t: 0, tick: 1, is_monk: false, anim: -1,
        skill: :defence, skill_xp: 1_210_421, skill_level: 75
      }

      {model, _} = Updaters.plugin_tick(Model.new(0), tick)
      rendered = PetView.render(model, 0)
      assert rendered =~ "DEFENCE"
      assert rendered =~ "75"
    end

    test "right rail shows 'X to {next}' when below max level" do
      # at 1,210,420 xp the player is 1 xp short of level 75
      tick = %Tick{
        t: 0, tick: 1, is_monk: false, anim: -1,
        skill: :defence, skill_xp: 1_210_420, skill_level: 74
      }

      {model, _} = Updaters.plugin_tick(Model.new(0), tick)
      rendered = PetView.render(model, 0)
      assert rendered =~ "1 to 75"
    end

    test "renders HP and prayer bars with current/max counts" do
      tick = %Tick{
        t: 0, tick: 1, is_monk: false, anim: -1,
        hp: 67, max_hp: 85, prayer: 31, max_prayer: 82
      }

      {model, _} = Updaters.plugin_tick(Model.new(0), tick)
      rendered = PetView.render(model, 0)
      assert rendered =~ "67/85"
      assert rendered =~ "31/82"
    end

    test "stats line shows hit count with comma separator" do
      model = Model.new(0)

      model =
        Enum.reduce(1..1_234, model, fn i, m ->
          {m, _} = Updaters.monk_killed(m, %{}, i)
          m
        end)

      assert PetView.render(model, 0) =~ "1,234"
    end

    test "tab bar is present and highlights the active view" do
      assert PetView.render(Model.new(0), 0) =~ "[PET]"
    end

    test "missing HP renders as a dash, not crash" do
      model = Model.new(0)
      rendered = PetView.render(model, 0)
      assert rendered =~ "-/-"
    end
  end

  defp combat_tick(t),
    do: %Tick{t: t, tick: 1, is_monk: true, anim: nil}
end
