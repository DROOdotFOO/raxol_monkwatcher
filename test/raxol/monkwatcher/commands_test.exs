defmodule Raxol.Monkwatcher.CommandsTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Commands

  test "broadcast_alert/1 wraps the payload in a tagged tuple" do
    assert Commands.broadcast_alert({:idle_alert, :warning, %{}}) ==
             {:broadcast_alert, {:idle_alert, :warning, %{}}}
  end

  test "broadcast_alert/1 preserves the inner payload shape exactly" do
    payload = {:milestone, :hits, 100}
    assert Commands.broadcast_alert(payload) == {:broadcast_alert, payload}
  end
end
