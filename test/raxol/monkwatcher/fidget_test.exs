defmodule Raxol.Monkwatcher.FidgetTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.Fidget

  # Textbook reference: uses index arithmetic to cycle, distinct
  # implementation strategy from the production module's pattern matching.
  defmodule Model do
    @views [:pet, :history, :stats, :sparkline]
    @threshold 30
    defstruct scroll: 0, view: :pet

    def new, do: %__MODULE__{}

    def scroll(%__MODULE__{} = m, delta) do
      new_pos = m.scroll + delta

      cond do
        new_pos > @threshold -> %__MODULE__{scroll: 0, view: cycle(m.view, 1)}
        new_pos < -@threshold -> %__MODULE__{scroll: 0, view: cycle(m.view, -1)}
        true -> %__MODULE__{m | scroll: new_pos}
      end
    end

    defp cycle(view, dir) do
      idx = Enum.find_index(@views, &(&1 == view))
      Enum.at(@views, Integer.mod(idx + dir, length(@views)))
    end
  end

  describe "new/0" do
    test "starts at scroll_position 0 in :pet view" do
      assert %Fidget{scroll_position: 0, view_mode: :pet} = Fidget.new()
    end
  end

  describe "scroll/2" do
    test "accumulates delta within the cycle threshold" do
      fidget = Fidget.new() |> Fidget.scroll(15) |> Fidget.scroll(10)

      assert fidget.scroll_position == 25
      assert fidget.view_mode == :pet
    end

    test "scrolling past +threshold cycles view forward and resets scroll" do
      fidget = Fidget.new() |> Fidget.scroll(31)

      assert fidget.scroll_position == 0
      assert fidget.view_mode == :history
    end

    test "scrolling past -threshold cycles view backward and resets scroll" do
      fidget = Fidget.new() |> Fidget.scroll(-31)

      assert fidget.scroll_position == 0
      assert fidget.view_mode == :sparkline
    end

    test "view cycles wrap: four forward cycles return to :pet" do
      fidget =
        Fidget.new()
        |> Fidget.scroll(31)
        |> Fidget.scroll(31)
        |> Fidget.scroll(31)
        |> Fidget.scroll(31)

      assert fidget.view_mode == :pet
    end

    property "Fidget matches the textbook model across arbitrary delta sequences" do
      check all deltas <- list_of(integer(-100..100), max_length: 200) do
        {model, real} =
          Enum.reduce(deltas, {Model.new(), Fidget.new()}, fn d, {m, r} ->
            {Model.scroll(m, d), Fidget.scroll(r, d)}
          end)

        assert model.scroll == real.scroll_position
        assert model.view == real.view_mode
      end
    end
  end
end
