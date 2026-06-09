defmodule Raxol.Monkwatcher.Model do
  alias Raxol.Monkwatcher.{Fidget, Session, StateMachine}
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  @type t :: %__MODULE__{}

  defstruct [:sm, :session, :fidget, :player, :pet, :muted_until_ms]

  def new(now) when is_integer(now) do
    %__MODULE__{
      sm: StateMachine.new(),
      session: Session.new(now),
      fidget: Fidget.new(),
      player: %{
        hp: nil,
        max_hp: nil,
        prayer: nil,
        max_prayer: nil,
        run_energy: nil,
        location: nil,
        skill: nil,
        skill_xp: nil,
        skill_level: nil
      },
      pet: %{mood: :content, target_mood: :content, transition_remaining: 0},
      muted_until_ms: 0
    }
  end

  @spec put_player(t, Tick.t()) :: t
  def put_player(%__MODULE__{} = model, %Tick{} = tick) do
    %{
      model
      | player: %{
          hp: tick.hp,
          max_hp: tick.max_hp,
          prayer: tick.prayer,
          max_prayer: tick.max_prayer,
          run_energy: tick.run_energy,
          location: {tick.x, tick.y, tick.plane},
          skill: tick.skill,
          skill_xp: tick.skill_xp,
          skill_level: tick.skill_level
        }
    }
  end
end
