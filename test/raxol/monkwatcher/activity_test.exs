defmodule Raxol.Monkwatcher.ActivityTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Activity, Model}

  describe "title/1" do
    test "Edgeville Monastery coordinates resolve to 'Monks'" do
      model = put_location(Model.new(0), {3050, 3490, 1})
      assert Activity.title(model) == "Monks"
    end

    test "Hosidius sand crab coordinates resolve to 'Crabs'" do
      model = put_location(Model.new(0), {1775, 3470, 0})
      assert Activity.title(model) == "Crabs"
    end

    test "unknown location with known skill falls back to capitalized skill name" do
      model =
        Model.new(0)
        |> put_location({100, 100, 0})
        |> put_skill(:strength)

      assert Activity.title(model) == "Strength"
    end

    test "no location and no skill falls back to 'Combat'" do
      assert Activity.title(Model.new(0)) == "Combat"
    end

    test "location takes precedence over skill" do
      model =
        Model.new(0)
        |> put_location({3050, 3490, 1})
        |> put_skill(:strength)

      assert Activity.title(model) == "Monks"
    end
  end

  defp put_location(model, loc),
    do: %{model | player: %{model.player | location: loc}}

  defp put_skill(model, skill),
    do: %{model | player: %{model.player | skill: skill}}
end
