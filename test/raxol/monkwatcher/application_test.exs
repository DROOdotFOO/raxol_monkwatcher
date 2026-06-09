defmodule Raxol.Monkwatcher.ApplicationTest do
  use ExUnit.Case, async: false

  test "PubSub server is registered under the canonical name" do
    assert is_pid(Process.whereis(Raxol.Monkwatcher.PubSub))
  end

  test "App is started and registered under the canonical name" do
    assert is_pid(Process.whereis(Raxol.Monkwatcher.App))
  end

  test "Plugin.Bridge is NOT started by default (no socket_path configured)" do
    refute Process.whereis(Raxol.Monkwatcher.Plugin.Bridge)
  end

  test "optional surfaces are NOT started by default" do
    refute Process.whereis(Raxol.Monkwatcher.Surfaces.Watch)
    refute Process.whereis(Raxol.Monkwatcher.Surfaces.Telegram)
  end

  test "broadcasting on the global PubSub reaches subscribers" do
    Phoenix.PubSub.subscribe(Raxol.Monkwatcher.PubSub, Raxol.Monkwatcher.Channels.alerts())
    Phoenix.PubSub.broadcast(Raxol.Monkwatcher.PubSub, Raxol.Monkwatcher.Channels.alerts(), :ping)

    assert_receive :ping, 500
  end
end
