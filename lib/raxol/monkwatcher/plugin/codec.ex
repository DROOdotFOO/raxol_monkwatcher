defmodule Raxol.Monkwatcher.Plugin.Codec do
  @moduledoc """
  Decodes lines from the RuneLite plugin's UDS stream into typed structs.
  All downstream modules pattern-match on `%Tick{}` or `%Event{}`; the
  stringly-keyed JSON map never escapes this module.
  """

  defmodule Tick do
    @enforce_keys [:t, :tick]
    defstruct [
      :t,
      :tick,
      :is_monk,
      :anim,
      :hp,
      :max_hp,
      :prayer,
      :max_prayer,
      :run_energy,
      :x,
      :y,
      :plane,
      :skill,
      :skill_xp,
      :skill_level
    ]
  end

  # Whitelist for safe wire-string -> atom conversion (avoids atom exhaustion).
  @known_skills %{
    "attack" => :attack,
    "strength" => :strength,
    "defence" => :defence,
    "hitpoints" => :hitpoints,
    "ranged" => :ranged,
    "magic" => :magic,
    "prayer" => :prayer
  }

  defmodule Event do
    @enforce_keys [:type, :data, :t]
    defstruct [:type, :data, :t]
  end

  def decode(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, %{"event" => type, "data" => data} = m} ->
        {:ok, %Event{type: type, data: data, t: m["t"]}}

      {:ok, %{"t" => _, "tick" => _} = m} ->
        {:ok, to_tick(m)}

      {:ok, _other} ->
        {:error, {:unknown_shape, line}}

      {:error, reason} ->
        {:error, {:bad_json, reason}}
    end
  end

  defp to_tick(m) do
    %Tick{
      t: m["t"],
      tick: m["tick"],
      is_monk: m["isMonk"],
      anim: m["anim"],
      hp: m["hp"],
      max_hp: m["maxHp"],
      prayer: m["prayer"],
      max_prayer: m["maxPrayer"],
      run_energy: m["runEnergy"],
      x: m["x"],
      y: m["y"],
      plane: m["plane"],
      skill: parse_skill(m["skill"]),
      skill_xp: m["skillXp"],
      skill_level: m["skillLevel"]
    }
  end

  defp parse_skill(nil), do: nil
  defp parse_skill(s) when is_binary(s), do: Map.get(@known_skills, s)
end
