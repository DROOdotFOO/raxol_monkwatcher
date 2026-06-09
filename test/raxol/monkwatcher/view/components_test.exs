defmodule Raxol.Monkwatcher.View.ComponentsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.View.Components

  describe "bar/2" do
    test "empty when ratio is 0.0" do
      assert Components.bar(0.0, 10) == ".........."
    end

    test "full when ratio is 1.0" do
      assert Components.bar(1.0, 10) == "##########"
    end

    test "rounds to the nearest cell" do
      # 0.55 * 10 = 5.5 -> rounds to 6
      assert Components.bar(0.55, 10) == "######...."
    end

    test "clamps below 0.0 to empty" do
      assert Components.bar(-1.0, 5) == "....."
    end

    test "clamps above 1.0 to full" do
      assert Components.bar(2.0, 5) == "#####"
    end

    property "output length always equals `width`" do
      check all ratio <- one_of([float(min: -1.0, max: 2.0), constant(0.0), constant(1.0)]),
                width <- integer(1..40) do
        assert String.length(Components.bar(ratio, width)) == width
      end
    end
  end

  describe "format_mmss/1" do
    test "zero is 0:00" do
      assert Components.format_mmss(0) == "0:00"
    end

    test "245_000ms is 4:05" do
      assert Components.format_mmss(245_000) == "4:05"
    end

    test "240_000ms is 4:00" do
      assert Components.format_mmss(240_000) == "4:00"
    end

    test "60-minute boundary still shows in minutes" do
      assert Components.format_mmss(3_600_000) == "60:00"
    end

    test "nil and negative inputs render as --:--" do
      assert Components.format_mmss(nil) == "--:--"
      assert Components.format_mmss(-1) == "--:--"
    end
  end

  describe "format_hms/1" do
    test "zero is 0:00:00" do
      assert Components.format_hms(0) == "0:00:00"
    end

    test "2h 46m 45s renders correctly" do
      assert Components.format_hms(10_005_000) == "2:46:45"
    end

    test "exactly one hour" do
      assert Components.format_hms(3_600_000) == "1:00:00"
    end

    test "under one hour pads hours to 0" do
      assert Components.format_hms(60_000) == "0:01:00"
    end
  end

  describe "tabs/2" do
    test "highlights the active view by uppercasing it" do
      assert Components.tabs(:pet, 0) ==
               "< [PET]  history  stats  sparkline >  scroll: 0"
    end

    test "history active" do
      assert Components.tabs(:history, 12) ==
               "< pet  [HISTORY]  stats  sparkline >  scroll: 12"
    end

    test "sparkline active with negative scroll" do
      assert Components.tabs(:sparkline, -7) ==
               "< pet  history  stats  [SPARKLINE] >  scroll: -7"
    end

    test "raises on unknown view" do
      assert_raise FunctionClauseError, fn -> Components.tabs(:unknown, 0) end
    end
  end

  describe "format_count/1" do
    test "small numbers stay as-is" do
      assert Components.format_count(0) == "0"
      assert Components.format_count(999) == "999"
    end

    test "thousands get a comma" do
      assert Components.format_count(1_000) == "1,000"
      assert Components.format_count(14_832) == "14,832"
    end

    test "millions get two commas" do
      assert Components.format_count(1_210_421) == "1,210,421"
    end

    test "nil renders as a single dash" do
      assert Components.format_count(nil) == "-"
    end
  end
end
