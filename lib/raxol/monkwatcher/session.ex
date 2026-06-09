defmodule Raxol.Monkwatcher.Session do
  @kill_history_cap 50

  defstruct [:started_at, monks_killed: 0, kill_history: [], deaths: 0]

  def new(now \\ nil) when is_integer(now) or is_nil(now),
    do: %__MODULE__{started_at: now}

  def record_kill(%__MODULE__{} = session, now, data) do
    %{
      session
      | monks_killed: session.monks_killed + 1,
        kill_history: [{now, data} | session.kill_history] |> Enum.take(@kill_history_cap)
    }
  end

  def record_death(%__MODULE__{} = session) do
    %{session | deaths: session.deaths + 1}
  end
end
