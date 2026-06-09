defmodule Raxol.Monkwatcher.Plugin.CodecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.Plugin.Codec
  alias Raxol.Monkwatcher.Plugin.Codec.{Tick, Event}
  alias Raxol.Monkwatcher.Test.CodecHelpers

  describe "decode/1 with a tick payload" do
    test "returns a populated %Tick{} struct" do
      line =
        ~s({"t":1700000000000,"tick":42,"isMonk":true,"anim":386,) <>
          ~s("hp":67,"maxHp":85,"prayer":31,"maxPrayer":82,) <>
          ~s("runEnergy":40,"x":3001,"y":3502,"plane":0,) <>
          ~s("skill":"defence","skillXp":1210421,"skillLevel":75})

      assert {:ok,
              %Tick{
                t: 1_700_000_000_000,
                tick: 42,
                is_monk: true,
                anim: 386,
                hp: 67,
                max_hp: 85,
                prayer: 31,
                max_prayer: 82,
                run_energy: 40,
                x: 3001,
                y: 3502,
                plane: 0,
                skill: :defence,
                skill_xp: 1_210_421,
                skill_level: 75
              }} = Codec.decode(line)
    end
  end

  describe "decode/1 with an event payload" do
    test "returns a populated %Event{} struct for a kill event" do
      line = ~s({"event":"monk_killed","t":1700000000000,) <>
             ~s("data":{"npc":"Monk"}})

      assert {:ok,
              %Event{
                type: "monk_killed",
                t: 1_700_000_000_000,
                data: %{"npc" => "Monk"}
              }} = Codec.decode(line)
    end

    test "decodes a level_up event with skill and level" do
      line = ~s({"event":"level_up","t":1700000005000,) <>
             ~s("data":{"skill":"defence","level":75}})

      assert {:ok,
              %Event{
                type: "level_up",
                t: 1_700_000_005_000,
                data: %{"skill" => "defence", "level" => 75}
              }} = Codec.decode(line)
    end

    test "decodes a player_death event with empty data" do
      line = ~s({"event":"player_death","t":1700000010000,"data":{}})

      assert {:ok,
              %Event{
                type: "player_death",
                t: 1_700_000_010_000,
                data: %{}
              }} = Codec.decode(line)
    end
  end

  describe "decode/1 on malformed input" do
    test "returns {:error, {:bad_json, _}}" do
      assert {:error, {:bad_json, _}} = Codec.decode("not json")
    end
  end

  describe "roundtrip" do
    @skills [:attack, :strength, :defence, :hitpoints, :ranged, :magic, :prayer]

    defp tick_generator do
      gen all t <- integer(0..2_000_000_000_000),
              tick <- integer(0..1_000_000),
              is_monk <- boolean(),
              anim <- integer(0..3000),
              hp <- integer(0..99),
              max_hp <- integer(1..99),
              prayer <- integer(0..99),
              max_prayer <- integer(1..99),
              run_energy <- integer(0..100),
              x <- integer(0..4096),
              y <- integer(0..4096),
              plane <- integer(0..3),
              skill <- member_of(@skills),
              skill_xp <- integer(0..200_000_000),
              skill_level <- integer(1..99) do
        %Tick{
          t: t, tick: tick, is_monk: is_monk, anim: anim,
          hp: hp, max_hp: max_hp, prayer: prayer, max_prayer: max_prayer,
          run_energy: run_energy, x: x, y: y, plane: plane,
          skill: skill, skill_xp: skill_xp, skill_level: skill_level
        }
      end
    end

    property "decode(encode(tick)) == tick for any well-formed tick" do
      check all tick <- tick_generator() do
        assert {:ok, ^tick} = tick |> CodecHelpers.encode() |> Codec.decode()
      end
    end
  end
end
