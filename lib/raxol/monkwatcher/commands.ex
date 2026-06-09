defmodule Raxol.Monkwatcher.Commands do
  @moduledoc """
  Builders for the command shapes the TEA runtime executes. Keeping the
  envelope construction here means tests can match on `{:broadcast_alert,
  payload}` shapes — no need to execute closures or start PubSub.

  Future runtime integration may swap the inner shape for a Raxol async
  command (`{:async, fn -> ... end}`); the function signature won't change.
  """

  @spec broadcast_alert(term) :: {:broadcast_alert, term}
  def broadcast_alert(payload), do: {:broadcast_alert, payload}
end
