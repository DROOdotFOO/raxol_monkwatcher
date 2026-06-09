defmodule Raxol.Monkwatcher.Osrs.XpTable do
  @moduledoc """
  Canonical OSRS XP curve. The same curve applies to every skill —
  feed it XP, get a level; feed it a level, get XP required.

  Formula (Jagex, all skills):

      xp(n) = floor((1/4) * sum_{L=1}^{n-1} floor(L + 300 * 2^(L/7)))
  """

  @max_level 99

  # Compile-time table: %{level => xp_required}.
  {table, _final_sum} =
    Enum.reduce(2..@max_level, {%{1 => 0}, 0}, fn level, {acc, sum} ->
      l = level - 1
      addend = trunc(l + 300 * :math.pow(2, l / 7))
      new_sum = sum + addend
      {Map.put(acc, level, div(new_sum, 4)), new_sum}
    end)

  @xp_table table

  # Sorted [{xp_required, level}, ...] descending for fast lookup.
  @thresholds_desc @xp_table
                   |> Enum.map(fn {level, xp} -> {xp, level} end)
                   |> Enum.sort_by(fn {xp, _} -> -xp end)

  def max_level, do: @max_level

  @spec xp_for_level(1..99) :: non_neg_integer
  def xp_for_level(level) when level in 1..@max_level,
    do: Map.fetch!(@xp_table, level)

  @spec level_for_xp(non_neg_integer) :: 1..99
  def level_for_xp(xp) when is_integer(xp) and xp >= 0 do
    {_xp_req, level} = Enum.find(@thresholds_desc, fn {req, _} -> xp >= req end)
    level
  end

  @spec xp_to_next(non_neg_integer) :: {1..99 | nil, non_neg_integer}
  def xp_to_next(xp) when is_integer(xp) and xp >= 0 do
    current = level_for_xp(xp)

    if current >= @max_level do
      {nil, 0}
    else
      next = current + 1
      {next, Map.fetch!(@xp_table, next) - xp}
    end
  end
end
