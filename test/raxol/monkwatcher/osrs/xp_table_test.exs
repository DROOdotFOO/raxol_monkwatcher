defmodule Raxol.Monkwatcher.Osrs.XpTableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.Osrs.XpTable

  describe "xp_for_level/1" do
    test "level 1 requires 0 XP" do
      assert XpTable.xp_for_level(1) == 0
    end

    test "level 2 requires 83 XP" do
      assert XpTable.xp_for_level(2) == 83
    end

    test "level 75 requires 1,210,421 XP" do
      assert XpTable.xp_for_level(75) == 1_210_421
    end

    test "level 99 requires 13,034,431 XP" do
      assert XpTable.xp_for_level(99) == 13_034_431
    end
  end

  describe "level_for_xp/1" do
    test "0 XP is level 1" do
      assert XpTable.level_for_xp(0) == 1
    end

    test "82 XP is still level 1" do
      assert XpTable.level_for_xp(82) == 1
    end

    test "exactly 83 XP is level 2" do
      assert XpTable.level_for_xp(83) == 2
    end

    test "1,210,420 XP is level 74 (one short of 75)" do
      assert XpTable.level_for_xp(1_210_420) == 74
    end

    test "1,210,421 XP is exactly level 75" do
      assert XpTable.level_for_xp(1_210_421) == 75
    end

    test "200,000,000 XP caps at level 99" do
      assert XpTable.level_for_xp(200_000_000) == 99
    end
  end

  describe "xp_to_next/1" do
    test "at level 1 with 0 xp, next level is 2 needing 83 xp" do
      assert XpTable.xp_to_next(0) == {2, 83}
    end

    test "at level 74 with one short, next level is 75 needing 1 xp" do
      assert XpTable.xp_to_next(1_210_420) == {75, 1}
    end

    test "at max level returns {nil, 0}" do
      assert XpTable.xp_to_next(13_034_431) == {nil, 0}
      assert XpTable.xp_to_next(200_000_000) == {nil, 0}
    end
  end

  describe "properties" do
    property "level_for_xp(xp_for_level(n)) == n for all levels 1..99" do
      check all level <- integer(1..99) do
        xp = XpTable.xp_for_level(level)
        assert XpTable.level_for_xp(xp) == level
      end
    end

    property "level_for_xp is monotonic non-decreasing" do
      check all xp1 <- integer(0..200_000_000),
                xp2 <- integer(0..200_000_000) do
        if xp1 <= xp2 do
          assert XpTable.level_for_xp(xp1) <= XpTable.level_for_xp(xp2)
        end
      end
    end
  end
end
