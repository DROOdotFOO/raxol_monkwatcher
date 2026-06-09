defmodule Raxol.Monkwatcher.ViewTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Model, View}

  describe "render/2" do
    test "routes :pet view to PetView" do
      rendered = View.render(Model.new(0), 0)
      assert rendered =~ "[PET]"
    end

    test "routes :history view to HistoryView placeholder" do
      model = put_view_mode(Model.new(0), :history)
      rendered = View.render(model, 0)
      assert rendered =~ "history"
    end

    test "routes :stats view to StatsView placeholder" do
      model = put_view_mode(Model.new(0), :stats)
      rendered = View.render(model, 0)
      assert rendered =~ "stats"
    end

    test "routes :sparkline view to SparklineView placeholder" do
      model = put_view_mode(Model.new(0), :sparkline)
      rendered = View.render(model, 0)
      assert rendered =~ "sparkline"
    end
  end

  defp put_view_mode(model, mode),
    do: %{model | fidget: %{model.fidget | view_mode: mode}}
end
