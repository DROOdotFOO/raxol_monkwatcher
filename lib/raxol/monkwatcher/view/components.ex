defmodule Raxol.Monkwatcher.View.Components do
  @moduledoc """
  Pure string helpers for terminal rendering. Every function returns a
  plain string — no Raxol view trees, no ANSI escapes. The eventual surface
  layer wraps these as needed; tests can match on output directly.
  """

  @fill "#"
  @empty "."

  @spec bar(number, pos_integer) :: String.t()
  def bar(ratio, width) when is_number(ratio) and is_integer(width) and width > 0 do
    clamped = ratio |> max(0.0) |> min(1.0)
    filled = round(clamped * width)
    String.duplicate(@fill, filled) <> String.duplicate(@empty, width - filled)
  end

  @spec format_mmss(integer | nil) :: String.t()
  def format_mmss(nil), do: "--:--"
  def format_mmss(ms) when is_integer(ms) and ms < 0, do: "--:--"

  def format_mmss(ms) when is_integer(ms) do
    total_s = div(ms, 1000)
    mm = div(total_s, 60)
    ss = rem(total_s, 60)
    "#{mm}:#{pad2(ss)}"
  end

  @spec format_hms(integer) :: String.t()
  def format_hms(ms) when is_integer(ms) and ms >= 0 do
    total_s = div(ms, 1000)
    h = div(total_s, 3600)
    m = div(rem(total_s, 3600), 60)
    s = rem(total_s, 60)
    "#{h}:#{pad2(m)}:#{pad2(s)}"
  end

  @spec format_count(integer | nil) :: String.t()
  def format_count(nil), do: "-"

  def format_count(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @views [:pet, :history, :stats, :sparkline]

  @spec tabs(atom, integer) :: String.t()
  def tabs(active, scroll) when active in @views and is_integer(scroll) do
    labels =
      Enum.map(@views, fn v ->
        s = Atom.to_string(v)
        if v == active, do: "[#{String.upcase(s)}]", else: s
      end)

    "< " <> Enum.join(labels, "  ") <> " >  scroll: #{scroll}"
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: "#{n}"
end
