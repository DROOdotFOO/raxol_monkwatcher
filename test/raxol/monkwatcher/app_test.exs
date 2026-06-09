defmodule Raxol.Monkwatcher.AppTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{App, Channels, Model}
  alias Raxol.Monkwatcher.Plugin.Codec.{Event, Tick}

  setup do
    pubsub = String.to_atom("app_test_pubsub_#{System.unique_integer([:positive])}")
    name = String.to_atom("app_test_#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: pubsub})
    # Inject a deterministic clock so tests don't depend on wall time.
    {:ok, _} = App.start_link(name: name, pubsub: pubsub, now_fn: fn -> 1_000_000 end)

    %{pubsub: pubsub, name: name}
  end

  describe "start_link/1" do
    test "initializes a fresh model anchored at the injected clock", %{name: name} do
      model = App.get_model(name)

      assert %Model{} = model
      assert model.session.started_at == 1_000_000
    end
  end

  describe "dispatch/1 with a Tick" do
    test "advances the StateMachine and updates the player slice", %{name: name} do
      tick = %Tick{
        t: 2_000_000,
        tick: 1,
        is_monk: true,
        anim: 386,
        hp: 67,
        max_hp: 85,
        skill: :defence,
        skill_xp: 1_210_421,
        skill_level: 75
      }

      App.dispatch(tick, name)
      Process.sleep(10)
      model = App.get_model(name)

      assert model.sm.state == :fighting
      assert model.player.hp == 67
      assert model.player.skill == :defence
    end
  end

  describe "dispatch/1 with an Event" do
    test "monk_killed event bumps session.monks_killed", %{name: name} do
      event = %Event{type: "monk_killed", t: 2_000_000, data: %{"npc" => "Monk"}}

      App.dispatch(event, name)
      Process.sleep(10)
      model = App.get_model(name)

      assert model.session.monks_killed == 1
    end

    test "player_death event sets sm.state = :dead", %{name: name} do
      event = %Event{type: "player_death", t: 2_000_000, data: %{}}

      App.dispatch(event, name)
      Process.sleep(10)
      model = App.get_model(name)

      assert model.sm.state == :dead
      assert model.session.deaths == 1
    end

    test "level_up event broadcasts a level milestone on PubSub", %{name: name, pubsub: pubsub} do
      Phoenix.PubSub.subscribe(pubsub, Channels.alerts())

      event = %Event{
        type: "level_up",
        t: 2_000_000,
        data: %{"skill" => "defence", "level" => 75}
      }

      App.dispatch(event, name)

      assert_receive {:milestone, :level, {:defence, 75}}, 500
    end
  end

  describe "dispatch/1 with control messages" do
    test "scroll updates fidget", %{name: name} do
      App.dispatch({:scroll, 15}, name)
      Process.sleep(10)
      assert App.get_model(name).fidget.scroll_position == 15
    end

    test "snooze sets muted_until_ms", %{name: name} do
      App.dispatch({:snooze, 60_000}, name)
      Process.sleep(10)
      # muted_until_ms = now_fn() + 60_000 = 1_000_000 + 60_000
      assert App.get_model(name).muted_until_ms == 1_060_000
    end
  end

  describe "idle alert path" do
    test "tick crossing the 4:00 threshold broadcasts on PubSub", %{name: name, pubsub: pubsub} do
      Phoenix.PubSub.subscribe(pubsub, Channels.alerts())

      App.dispatch(idle_tick(0), name)
      App.dispatch(idle_tick(240_000), name)

      assert_receive {:idle_alert, :warning, _model, 240_000}, 500
    end
  end

  describe "view/0" do
    test "returns a rendered string at the injected clock", %{name: name} do
      out = App.view(name)
      assert is_binary(out)
      assert out =~ "Combat"
    end
  end

  describe "dispatch/1 with unknown messages" do
    test "silently ignores", %{name: name} do
      App.dispatch(:garbage, name)
      Process.sleep(10)
      # Process still alive and model unchanged
      assert App.get_model(name).session.monks_killed == 0
    end
  end

  defp idle_tick(t),
    do: %Tick{t: t, tick: 1, is_monk: false, anim: -1}
end
