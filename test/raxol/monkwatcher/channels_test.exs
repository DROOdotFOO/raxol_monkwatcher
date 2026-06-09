defmodule Raxol.Monkwatcher.ChannelsTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Channels

  test "alerts/0 returns the canonical topic name" do
    assert Channels.alerts() == "alerts"
  end
end
