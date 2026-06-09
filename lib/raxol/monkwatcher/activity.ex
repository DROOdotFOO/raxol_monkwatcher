defmodule Raxol.Monkwatcher.Activity do
  @moduledoc """
  Derives a short user-facing activity label from the model. Tries known
  training regions first (coordinate-box match), falls back to the
  capitalized skill atom, finally falls back to "Combat".

  Used by every surface that needs a title — Watch push notifications and
  Telegram pinned message updates both go through `title/1`. New training
  spots are added to `@regions` without touching call sites.
  """

  @regions [
    %{name: "Monks", x: 3046..3060, y: 3480..3500, plane: 1},
    %{name: "Crabs", x: 1768..1788, y: 3464..3484, plane: 0}
  ]

  @spec title(map) :: String.t()
  def title(model) do
    location_label(model.player.location) ||
      skill_label(model.player.skill) ||
      "Combat"
  end

  defp location_label({x, y, plane}) when is_integer(x) and is_integer(y) do
    Enum.find_value(@regions, fn r ->
      if x in r.x and y in r.y and plane == r.plane, do: r.name
    end)
  end

  defp location_label(_), do: nil

  defp skill_label(nil), do: nil
  defp skill_label(skill) when is_atom(skill), do: skill |> Atom.to_string() |> String.capitalize()
end
