defmodule Raxol.Monkwatcher.Pet do
  @moduledoc """
  Pure derivations from the model: fullness, energy, mood, and ASCII frame
  selection. Internal abstraction — no user-facing strings here. The view
  layer decides whether to render the resulting frame at all and never
  prints the mood atom.
  """

  alias Raxol.Monkwatcher.{StateMachine, Pet.Frames}

  @fullness_baseline 0.5
  @fullness_per_kill 0.02
  @fullness_decay_per_idle_minute 0.05

  @energy_baseline 0.5
  @energy_per_scroll_detent 0.001

  @panicked_idle_ms 270_000
  @sleepy_idle_ms 60_000
  @level_up_window_ms 5_000
  @hungry_below 0.2
  @content_above 0.8

  @transition_ticks 8

  @spec fullness(map, integer) :: float
  def fullness(model, now) do
    gain = model.session.monks_killed * @fullness_per_kill
    idle_minutes = max(0, StateMachine.time_in_state_ms(model.sm, now) / 60_000)
    decay = idle_minutes * @fullness_decay_per_idle_minute

    (@fullness_baseline + gain - decay)
    |> clamp(0.0, 1.0)
    |> Float.round(2)
  end

  @spec energy(map) :: float
  def energy(model) do
    base =
      case model.player.run_energy do
        nil -> @energy_baseline
        n when is_integer(n) -> n / 100
      end

    fidget_bonus = model.fidget.scroll_position * @energy_per_scroll_detent

    (base + fidget_bonus)
    |> clamp(0.0, 1.0)
    |> Float.round(2)
  end

  @doc """
  Derives the target mood from the current model state. Ordering is
  significant: :fainted wins over everything, then :panicked over :sleepy,
  then :triumphant, then :hungry, then default :content. The metamorphic
  property `:dead -> :fainted` pins ordering against accidental reshuffle.
  """
  @spec derive_target_mood(map, integer) :: atom
  def derive_target_mood(model, now) do
    idle = StateMachine.time_in_state_ms(model.sm, now)

    cond do
      model.sm.state == :dead -> :fainted
      model.sm.state == :idle and idle > @panicked_idle_ms -> :panicked
      model.sm.state == :idle and idle > @sleepy_idle_ms -> :sleepy
      just_leveled?(model, now) -> :triumphant
      fullness(model, now) < @hungry_below -> :hungry
      fullness(model, now) > @content_above -> :content
      true -> :content
    end
  end

  @doc """
  Advances the pet toward `target` over `@transition_ticks` ticks. Until the
  transition completes, `pet.mood` (what the view renders) stays at the
  previous value; only `target_mood` and `transition_remaining` change. When
  the counter reaches zero, `mood` snaps to `target`. Briefly-flickering
  targets don't reach the view.
  """
  @spec tick_mood(map, atom, integer) :: map
  def tick_mood(pet, target, _now) do
    cond do
      target == pet.mood ->
        %{pet | target_mood: target, transition_remaining: 0}

      target != pet.target_mood ->
        %{pet | target_mood: target, transition_remaining: @transition_ticks}

      pet.transition_remaining > 1 ->
        %{pet | transition_remaining: pet.transition_remaining - 1}

      true ->
        %{pet | mood: target, transition_remaining: 0}
    end
  end

  @doc """
  Returns the ASCII frame for the given mood, rotated by `scroll_pos`.
  Negative and positive scrolls map to the same frame (magnitude only).
  """
  @spec frame(atom, integer) :: String.t()
  def frame(mood, scroll_pos) do
    frames = Frames.for_mood(mood)
    Enum.at(frames, rem(abs(scroll_pos), length(frames)))
  end

  defp just_leveled?(model, now) do
    case Map.get(model.session, :levels_gained, []) do
      [{_skill, _level, ts} | _] -> now - ts < @level_up_window_ms
      _ -> false
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
end
