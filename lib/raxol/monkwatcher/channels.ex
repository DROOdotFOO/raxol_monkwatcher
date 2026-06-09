defmodule Raxol.Monkwatcher.Channels do
  @moduledoc """
  Canonical PubSub topic names. Every broadcast and subscription site
  goes through these functions so a typo can't silently route messages
  to the void.
  """

  def alerts, do: "alerts"
end
