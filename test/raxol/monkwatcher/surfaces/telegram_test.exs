defmodule Raxol.Monkwatcher.Surfaces.TelegramTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Channels, Model}
  alias Raxol.Monkwatcher.Surfaces.Telegram

  describe "format_pinned/2" do
    test "shows idle time, hits, skill+level, and HP/maxHP" do
      model = build_model(idle_for: 4 * 60_000 + 12_000, hits: 247, skill: :defence,
                          skill_level: 74, hp: 67, max_hp: 85)

      assert Telegram.format_pinned(model, 4 * 60_000 + 12_000) ==
               "4:12 * 247 hits * 74 def * 67/85"
    end

    test "uses the abbreviated skill code (def, str, hp, range, mage, pray, att)" do
      model = build_model(idle_for: 0, hits: 0, skill: :strength, skill_level: 99,
                          hp: 99, max_hp: 99)

      assert Telegram.format_pinned(model, 0) ==
               "0:00 * 0 hits * 99 str * 99/99"
    end

    test "renders dashes for missing data" do
      model = Model.new(0)
      assert Telegram.format_pinned(model, 0) == "0:00 * 0 hits * - * -/-"
    end
  end

  describe "GenServer integration" do
    setup do
      pubsub = String.to_atom("tg_test_pubsub_#{System.unique_integer([:positive])}")
      start_supervised!({Phoenix.PubSub, name: pubsub})
      %{pubsub: pubsub}
    end

    test "forwards a formatted update on idle :warning broadcast", %{pubsub: pubsub} do
      test_pid = self()
      send_fn = fn text -> send(test_pid, {:edit, text}) end

      start_supervised!({Telegram, pubsub: pubsub, send_fn: send_fn, chat_id: 0})

      model = build_model(idle_for: 240_000, hits: 100, skill: :defence,
                         skill_level: 75, hp: 67, max_hp: 85)

      Phoenix.PubSub.broadcast(
        pubsub,
        Channels.alerts(),
        {:idle_alert, :warning, model, 240_000}
      )

      assert_receive {:edit, text}, 500
      assert text =~ "4:00"
      assert text =~ "100 hits"
      assert text =~ "75 def"
    end
  end

  defp build_model(opts) do
    model = Model.new(0)

    session = %{
      model.session
      | started_at: 0,
        monks_killed: Keyword.get(opts, :hits, 0)
    }

    sm =
      case Keyword.get(opts, :idle_for, 0) do
        0 -> model.sm
        ms -> %{model.sm | state: :idle, state_since_ms: 0}
      end
      |> Map.put(:state_since_ms, 0)

    %{
      model
      | session: session,
        sm: %{sm | state: :idle},
        player: %{
          model.player
          | skill: opts[:skill],
            skill_level: opts[:skill_level],
            hp: opts[:hp],
            max_hp: opts[:max_hp]
        }
    }
  end
end
