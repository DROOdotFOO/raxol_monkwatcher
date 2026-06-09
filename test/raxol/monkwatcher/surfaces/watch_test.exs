defmodule Raxol.Monkwatcher.Surfaces.WatchTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Channels, Model}
  alias Raxol.Monkwatcher.Surfaces.Watch

  describe "to_notification/1" do
    test "idle :warning becomes a normal push with snooze action" do
      model = at_monastery(Model.new(0))

      assert %{
               title: "Monks",
               body: "4:00",
               priority: :normal,
               actions: [%{id: "snooze", label: "+60s"}]
             } = Watch.to_notification({:idle_alert, :warning, model, 0})
    end

    test "idle :critical drops actions (HIG penalty for second tap)" do
      model = at_monastery(Model.new(0))
      n = Watch.to_notification({:idle_alert, :critical, model, 0})

      assert n.title == "Monks"
      assert n.body == "Click!"
      assert n.priority == :high
      refute Map.has_key?(n, :actions)
    end

    test "hits milestone uses activity title and the count as body" do
      model = at_monastery(Model.new(0))

      assert %{title: "Monks", body: "100", priority: :normal} =
               Watch.to_notification({:milestone, :hits, 100, model, 0})
    end

    test "level-up uses the skill name as title" do
      assert %{title: "Defence", body: "75", priority: :normal} =
               Watch.to_notification({:milestone, :level, {:defence, 75}})
    end

    test "death uses activity title with high priority" do
      model = at_monastery(Model.new(0))
      n = Watch.to_notification({:death, model, 0})

      assert n.title == "Monks"
      assert n.body == "Died."
      assert n.priority == :high
    end

    test "no emoji in any payload (watchOS rendering consistency)" do
      model = at_monastery(Model.new(0))

      payloads = [
        {:idle_alert, :warning, model, 0},
        {:idle_alert, :critical, model, 0},
        {:milestone, :hits, 100, model, 0},
        {:milestone, :level, {:defence, 75}},
        {:death, model, 0}
      ]

      for p <- payloads do
        n = Watch.to_notification(p)
        for field <- [:title, :body], do: assert(no_emoji?(n[field]))
      end
    end
  end

  describe "GenServer integration" do
    setup do
      pubsub = String.to_atom("watch_test_pubsub_#{System.unique_integer([:positive])}")
      start_supervised!({Phoenix.PubSub, name: pubsub})
      %{pubsub: pubsub}
    end

    test "forwards a translated notification on broadcast", %{pubsub: pubsub} do
      test_pid = self()
      send_fn = fn n -> send(test_pid, {:pushed, n}) end

      start_supervised!({Watch, pubsub: pubsub, send_fn: send_fn})

      model = at_monastery(Model.new(0))
      Phoenix.PubSub.broadcast(pubsub, Channels.alerts(), {:idle_alert, :warning, model, 0})

      assert_receive {:pushed, %{title: "Monks", body: "4:00"}}, 500
    end

    test "translates hit-milestone broadcast end-to-end", %{pubsub: pubsub} do
      test_pid = self()
      send_fn = fn n -> send(test_pid, {:pushed, n}) end

      start_supervised!({Watch, pubsub: pubsub, send_fn: send_fn})

      model = at_monastery(Model.new(0))

      Phoenix.PubSub.broadcast(
        pubsub,
        Channels.alerts(),
        {:milestone, :hits, 100, model, 0}
      )

      assert_receive {:pushed, %{title: "Monks", body: "100"}}, 500
    end
  end

  defp at_monastery(model),
    do: %{model | player: %{model.player | location: {3050, 3490, 1}}}

  defp no_emoji?(nil), do: true

  defp no_emoji?(s) when is_binary(s) do
    String.printable?(s) and Regex.run(~r/[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]/u, s) == nil
  end
end
