defmodule Raxol.Monkwatcher.Plugin.BridgeTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Plugin.Bridge
  alias Raxol.Monkwatcher.Plugin.Codec.{Event, Tick}
  alias Raxol.Monkwatcher.Test.FakePlugin

  setup do
    path = FakePlugin.tmp_socket_path()
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  describe "Bridge integration with a real UDS" do
    test "dispatches a Tick decoded from a single wire line", %{path: path} do
      line = ~s({"t":123,"tick":1,"isMonk":true,"anim":386,"hp":50,"maxHp":85,) <>
             ~s("prayer":31,"maxPrayer":82,"runEnergy":40,"x":3050,"y":3490,) <>
             ~s("plane":1,"skill":"defence","skillXp":1210421,"skillLevel":75})

      FakePlugin.start(path, [line])

      test_pid = self()
      send_fn = fn msg -> send(test_pid, {:dispatched, msg}) end

      {:ok, _} =
        Bridge.start_link(
          name: unique_name(),
          socket_path: path,
          dispatch_fn: send_fn
        )

      assert_receive {:dispatched, %Tick{t: 123, skill: :defence, skill_level: 75}}, 1_000
    end

    test "dispatches an Event decoded from a single wire line", %{path: path} do
      line = ~s({"event":"monk_killed","t":456,"data":{"npc":"Monk"}})
      FakePlugin.start(path, [line])

      test_pid = self()

      {:ok, _} =
        Bridge.start_link(
          name: unique_name(),
          socket_path: path,
          dispatch_fn: fn msg -> send(test_pid, {:dispatched, msg}) end
        )

      assert_receive {:dispatched, %Event{type: "monk_killed", t: 456}}, 1_000
    end

    test "skips malformed JSON without crashing or dispatching", %{path: path} do
      good = ~s({"event":"monk_killed","t":1,"data":{}})
      FakePlugin.start(path, ["not json", good])

      test_pid = self()

      {:ok, pid} =
        Bridge.start_link(
          name: unique_name(),
          socket_path: path,
          dispatch_fn: fn msg -> send(test_pid, {:dispatched, msg}) end
        )

      # only the good line dispatches
      assert_receive {:dispatched, %Event{type: "monk_killed"}}, 1_000
      refute_receive {:dispatched, _}, 100
      assert Process.alive?(pid)
    end

    test "dispatches multiple lines in order", %{path: path} do
      l1 = ~s({"event":"a","t":1,"data":{}})
      l2 = ~s({"event":"b","t":2,"data":{}})
      l3 = ~s({"event":"c","t":3,"data":{}})

      FakePlugin.start(path, [l1, l2, l3])

      test_pid = self()

      {:ok, _} =
        Bridge.start_link(
          name: unique_name(),
          socket_path: path,
          dispatch_fn: fn msg -> send(test_pid, {:dispatched, msg}) end
        )

      assert_receive {:dispatched, %Event{type: "a"}}, 1_000
      assert_receive {:dispatched, %Event{type: "b"}}, 1_000
      assert_receive {:dispatched, %Event{type: "c"}}, 1_000
    end
  end

  describe "Bridge reconnect behaviour" do
    test "remains alive after the plugin socket closes", %{path: path} do
      line = ~s({"event":"x","t":1,"data":{}})
      FakePlugin.start(path, [line])

      test_pid = self()

      {:ok, pid} =
        Bridge.start_link(
          name: unique_name(),
          socket_path: path,
          dispatch_fn: fn msg -> send(test_pid, {:dispatched, msg}) end
        )

      assert_receive {:dispatched, _}, 1_000
      # The FakePlugin closes immediately after the writes. The Bridge
      # should survive and start its reconnect cycle.
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end

  defp unique_name,
    do: String.to_atom("bridge_test_#{System.unique_integer([:positive])}")
end
