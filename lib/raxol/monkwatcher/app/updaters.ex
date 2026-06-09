defmodule Raxol.Monkwatcher.App.Updaters do
  alias Raxol.Monkwatcher.{Fidget, Model, Notifications, Pet, Session, StateMachine}
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  def monk_killed(model, data, now) do
    new_session = Session.record_kill(model.session, now, data)
    new_model = %{model | session: new_session}
    commands = Notifications.milestone_commands(new_session.monks_killed, new_model, now)
    {new_model, commands}
  end

  def plugin_tick(model, %Tick{} = tick) do
    sm = StateMachine.apply_tick(model.sm, tick)
    {sm, fires} = StateMachine.check_thresholds(sm, tick.t)

    model =
      %{model | sm: sm}
      |> Model.put_player(tick)
      |> advance_pet(tick.t)

    {model, Notifications.idle_alert_commands(fires, model, tick.t)}
  end

  def player_death(model, now) do
    session = Session.record_death(model.session)
    sm = %{model.sm | state: :dead, state_since_ms: now}
    pet = %{model.pet | target_mood: :fainted, mood: :fainted, transition_remaining: 0}

    new_model = %{model | session: session, sm: sm, pet: pet}
    {new_model, [Notifications.death_command(new_model, now)]}
  end

  def snooze(model, ms, now) when is_integer(ms) and is_integer(now) do
    {%{model | muted_until_ms: now + ms}, []}
  end

  def scroll(model, delta) when is_integer(delta) do
    new_fidget = Fidget.scroll(model.fidget, delta)
    {%{model | fidget: new_fidget}, []}
  end

  defp advance_pet(model, now) do
    target = Pet.derive_target_mood(model, now)
    new_pet = Pet.tick_mood(model.pet, target, now)
    %{model | pet: new_pet}
  end
end
