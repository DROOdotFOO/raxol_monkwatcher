defmodule Raxol.Monkwatcher.Test.CodecHelpers do
  @moduledoc """
  Test-only helpers that invert `Plugin.Codec.decode/1`. Used by the
  Codec roundtrip property; never linked into a release.
  """

  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  @spec to_wire_map(Tick.t()) :: map
  def to_wire_map(%Tick{} = t) do
    %{
      "t" => t.t,
      "tick" => t.tick,
      "isMonk" => t.is_monk,
      "anim" => t.anim,
      "hp" => t.hp,
      "maxHp" => t.max_hp,
      "prayer" => t.prayer,
      "maxPrayer" => t.max_prayer,
      "runEnergy" => t.run_energy,
      "x" => t.x,
      "y" => t.y,
      "plane" => t.plane,
      "skill" => skill_to_wire(t.skill),
      "skillXp" => t.skill_xp,
      "skillLevel" => t.skill_level
    }
  end

  defp skill_to_wire(nil), do: nil
  defp skill_to_wire(skill) when is_atom(skill), do: Atom.to_string(skill)

  @spec encode(Tick.t()) :: String.t()
  def encode(%Tick{} = t), do: t |> to_wire_map() |> Jason.encode!()
end
