defmodule Raxol.Monkwatcher.SessionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raxol.Monkwatcher.Session

  describe "record_kill/3" do
    test "prepends the new kill to kill_history" do
      session = Session.new()
      session = Session.record_kill(session, 1_000, %{npc: "Monk"})

      assert [{1_000, %{npc: "Monk"}}] = session.kill_history
    end

    test "caps kill_history at 50 entries while monks_killed keeps counting" do
      session =
        Enum.reduce(1..75, Session.new(), fn i, acc ->
          Session.record_kill(acc, i * 1_000, %{npc: "Monk #{i}"})
        end)

      assert length(session.kill_history) == 50
      assert session.monks_killed == 75
      # most recent kill at the head
      assert [{75_000, %{npc: "Monk 75"}} | _] = session.kill_history
    end

    property "monks_killed equals total kills; kill_history capped at 50" do
      check all timestamps <- list_of(integer(), max_length: 200) do
        session =
          Enum.reduce(timestamps, Session.new(), fn t, s ->
            Session.record_kill(s, t, %{})
          end)

        assert session.monks_killed == length(timestamps)
        assert length(session.kill_history) == min(length(timestamps), 50)
      end
    end
  end
end
