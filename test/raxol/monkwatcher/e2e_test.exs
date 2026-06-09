defmodule Raxol.Monkwatcher.E2ETest do
  @moduledoc """
  End-to-end smoke test. Exercises the full production pipeline with one
  test: UDS line -> Plugin.Bridge -> Codec -> App.dispatch -> Updaters ->
  Phoenix.PubSub broadcast -> Surfaces.Watch -> send_fn.

  If this test passes, every piece of the runtime is wired correctly.
  """
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{App, Plugin.Bridge, Surfaces.Watch}
  alias Raxol.Monkwatcher.Test.FakePlugin

  test "100 monk_killed events from the plugin produce a hit-milestone push" do
    pubsub = unique_atom("e2e_pubsub")
    app_name = unique_atom("e2e_app")
    watch_name = unique_atom("e2e_watch")
    bridge_name = unique_atom("e2e_bridge")

    start_supervised!({Phoenix.PubSub, name: pubsub})

    {:ok, _} =
      start_supervised(%{
        id: app_name,
        start: {App, :start_link, [[name: app_name, pubsub: pubsub]]}
      })

    test_pid = self()
    send_fn = fn n -> send(test_pid, {:pushed, n}) end

    {:ok, _} =
      start_supervised(%{
        id: watch_name,
        start: {Watch, :start_link, [[name: watch_name, pubsub: pubsub, send_fn: send_fn]]}
      })

    path = FakePlugin.tmp_socket_path()
    on_exit(fn -> File.rm(path) end)

    events =
      for i <- 1..100 do
        ~s({"event":"monk_killed","t":#{i * 1000},"data":{"npc":"Monk"}})
      end

    FakePlugin.start(path, events)

    {:ok, _} =
      start_supervised(%{
        id: bridge_name,
        start:
          {Bridge, :start_link,
           [
             [
               name: bridge_name,
               socket_path: path,
               dispatch_fn: fn msg -> App.dispatch(msg, app_name) end
             ]
           ]}
      })

    # The 100th kill triggers Notifications.milestone_commands which
    # broadcasts {:milestone, :hits, 100, model, now}. Watch translates
    # that into a notification with body "100".
    assert_receive {:pushed, %{body: "100"}}, 3_000

    # Final model reflects all 100 kills.
    model = App.get_model(app_name)
    assert model.session.monks_killed == 100
  end

  defp unique_atom(prefix),
    do: String.to_atom("#{prefix}_#{System.unique_integer([:positive])}")
end
