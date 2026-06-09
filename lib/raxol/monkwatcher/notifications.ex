defmodule Raxol.Monkwatcher.Notifications do
  @moduledoc """
  Pure constructors for outbound alert commands. Encapsulates two things
  Updaters used to do inline: choosing which payloads to emit, and checking
  the muting window for idle-alert flows. Surfaces translate payload shapes
  into user-facing copy — this module never produces strings.
  """

  alias Raxol.Monkwatcher.Commands

  @hit_milestone_step 100

  @spec milestone_commands(non_neg_integer, map, integer) :: [term]
  def milestone_commands(n, model, now)
      when is_integer(n) and n > 0 and rem(n, @hit_milestone_step) == 0,
      do: [Commands.broadcast_alert({:milestone, :hits, n, model, now})]

  def milestone_commands(_, _, _), do: []

  @spec idle_alert_commands([atom], map, integer) :: [term]
  def idle_alert_commands([], _model, _now), do: []

  def idle_alert_commands(_fires, %{muted_until_ms: muted}, now) when muted > now, do: []

  def idle_alert_commands(fires, model, now) do
    Enum.map(fires, fn level ->
      Commands.broadcast_alert({:idle_alert, level, model, now})
    end)
  end

  @spec death_command(map, integer) :: term
  def death_command(model, now), do: Commands.broadcast_alert({:death, model, now})

  @spec level_up_command(atom, pos_integer) :: term
  def level_up_command(skill, level) when is_atom(skill) and is_integer(level),
    do: Commands.broadcast_alert({:milestone, :level, {skill, level}})
end
