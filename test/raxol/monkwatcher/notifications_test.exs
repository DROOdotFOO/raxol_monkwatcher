defmodule Raxol.Monkwatcher.NotificationsTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Model, Notifications}

  describe "milestone_commands/3" do
    test "returns a :hits milestone broadcast with model and now at every 100th hit" do
      model = Model.new(0)

      assert Notifications.milestone_commands(100, model, 12_345) ==
               [{:broadcast_alert, {:milestone, :hits, 100, model, 12_345}}]
    end

    test "returns [] for non-milestone counts" do
      model = Model.new(0)
      assert Notifications.milestone_commands(99, model, 0) == []
      assert Notifications.milestone_commands(101, model, 0) == []
      assert Notifications.milestone_commands(0, model, 0) == []
    end
  end

  describe "idle_alert_commands/3" do
    test "wraps each fire level with model and now in a broadcast command" do
      model = Model.new(0)
      now = 240_000

      assert Notifications.idle_alert_commands([:warning], model, now) ==
               [{:broadcast_alert, {:idle_alert, :warning, model, now}}]
    end

    test "emits one command per fire level, preserving order" do
      model = Model.new(0)
      now = 280_000

      assert [
               {:broadcast_alert, {:idle_alert, :critical, _, ^now}},
               {:broadcast_alert, {:idle_alert, :warning, _, ^now}}
             ] = Notifications.idle_alert_commands([:critical, :warning], model, now)
    end

    test "returns [] when muted_until_ms is in the future" do
      model = %{Model.new(0) | muted_until_ms: 1_000_000}

      assert Notifications.idle_alert_commands([:warning, :critical], model, 500_000) == []
    end

    test "resumes emitting commands after the mute expires" do
      model = %{Model.new(0) | muted_until_ms: 500_000}

      assert [_] = Notifications.idle_alert_commands([:warning], model, 500_001)
    end

    test "returns [] for an empty fire list regardless of muting" do
      model = Model.new(0)
      assert Notifications.idle_alert_commands([], model, 1_000_000) == []
    end
  end

  describe "death_command/2" do
    test "wraps the model and now in a :death broadcast" do
      model = Model.new(0)
      assert Notifications.death_command(model, 999) == {:broadcast_alert, {:death, model, 999}}
    end
  end

  describe "level_up_command/2" do
    test "wraps the skill and new level in a :level milestone" do
      assert Notifications.level_up_command(:defence, 75) ==
               {:broadcast_alert, {:milestone, :level, {:defence, 75}}}
    end
  end
end
