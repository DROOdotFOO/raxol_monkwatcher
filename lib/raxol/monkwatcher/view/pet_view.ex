defmodule Raxol.Monkwatcher.View.PetView do
  @moduledoc """
  Renders the default fidget view as a multi-line string. User-facing labels
  reflect the actual in-game task — no pet metaphor leaks through to text.
  Internal abstractions (mood, fullness, energy) still drive ASCII frame
  selection, but no mood label is printed.
  """

  alias Raxol.Monkwatcher.{Pet, Session, View.Components}
  alias Raxol.Monkwatcher.Osrs.XpTable

  @width 58
  @bar_width 16

  def render(model, now) do
    [
      top_border(),
      header_line(model, now),
      blank(),
      art_block(model, now),
      blank(),
      state_line(model, now),
      blank(),
      hp_line(model.player),
      prayer_line(model.player),
      blank(),
      stats_line(model.session, now),
      blank(),
      sparkline_line(),
      blank(),
      tab_line(model.fidget),
      bottom_border()
    ]
    |> Enum.join("\n")
  end

  # --- header ---

  defp header_line(model, now) do
    activity = activity_label(model.player.skill)
    elapsed = Components.format_hms(session_elapsed(model.session, now))
    inside = " #{activity} * #{elapsed} "
    pad_line(inside)
  end

  defp activity_label(nil), do: "Combat"
  defp activity_label(skill), do: "Training " <> skill_title(skill)

  defp skill_title(skill) when is_atom(skill) do
    skill |> Atom.to_string() |> String.capitalize()
  end

  defp session_elapsed(%Session{started_at: nil}, _now), do: 0
  defp session_elapsed(%Session{started_at: start}, now), do: max(0, now - start)

  # --- art + right rail ---

  defp art_block(model, now) do
    frame = Pet.frame(model.pet.mood, model.fidget.scroll_position)
    art_lines = [frame, "", "", "", ""]

    rail_lines = [
      state_label(model.sm.state),
      "--------",
      skill_label(model.player),
      xp_remaining_label(model.player)
    ]

    art_lines
    |> Enum.zip_with(pad_rail(rail_lines), fn art, rail ->
      pad_line("  " <> pad_right(art, 14) <> "  " <> rail)
    end)
    |> Enum.join("\n")
    |> tap(fn _ -> now end)
  end

  defp pad_rail(rails), do: rails ++ List.duplicate("", max(0, 5 - length(rails)))

  defp state_label(state), do: state |> Atom.to_string() |> String.upcase()

  defp skill_label(%{skill: nil}), do: "---"

  defp skill_label(%{skill: skill, skill_level: level}) do
    "#{skill |> Atom.to_string() |> String.upcase()}  #{level || "-"}"
  end

  defp xp_remaining_label(%{skill_xp: nil}), do: ""

  defp xp_remaining_label(%{skill_xp: xp}) do
    case XpTable.xp_to_next(xp) do
      {nil, _} -> "maxed"
      {next, remaining} -> "#{Components.format_count(remaining)} to #{next}"
    end
  end

  # --- state line ---

  defp state_line(model, now) do
    state = state_label(model.sm.state)
    last_hit = format_last_hit(model.session, now)
    pad_line("  state: #{state}#{spaces(20 - String.length(state))}last hit: #{last_hit}  ")
  end

  defp format_last_hit(%Session{kill_history: []}, _now), do: "--"

  defp format_last_hit(%Session{kill_history: [{ts, _} | _]}, now),
    do: "#{div(max(0, now - ts), 1000)}s ago"

  # --- bars ---

  defp hp_line(player), do: pad_line(vital_line("HP ", player.hp, player.max_hp))
  defp prayer_line(player), do: pad_line(vital_line("PRA", player.prayer, player.max_prayer))

  defp vital_line(label, nil, _), do: "  #{label}  #{empty_bar()}  -/-"
  defp vital_line(label, _, nil), do: "  #{label}  #{empty_bar()}  -/-"

  defp vital_line(label, value, max) do
    ratio = if max > 0, do: value / max, else: 0.0
    "  #{label}  #{Components.bar(ratio, @bar_width)}  #{value}/#{max}"
  end

  defp empty_bar, do: Components.bar(0.0, @bar_width)

  # --- stats ---

  defp stats_line(session, now) do
    hits = Components.format_count(session.monks_killed)
    per_hour = Components.format_count(hits_per_hour(session, now))
    pad_line("  hits * #{hits}   /hr * #{per_hour}   xp/hr * -")
  end

  defp hits_per_hour(%Session{started_at: nil}, _now), do: 0
  defp hits_per_hour(%Session{started_at: start}, now) when now <= start, do: 0

  defp hits_per_hour(%Session{started_at: start, monks_killed: kills}, now) do
    hours = (now - start) / 3_600_000
    if hours > 0, do: round(kills / hours), else: 0
  end

  # --- sparkline placeholder ---

  defp sparkline_line, do: pad_line("  " <> String.duplicate(".", 40))

  # --- tab bar ---

  defp tab_line(fidget) do
    pad_line("  " <> Components.tabs(fidget.view_mode, fidget.scroll_position))
  end

  # --- borders + padding ---

  defp top_border, do: "+" <> String.duplicate("-", @width) <> "+"
  defp bottom_border, do: top_border()

  defp blank, do: pad_line("")

  defp pad_line(inside) do
    inner = pad_right(inside, @width)
    "|" <> inner <> "|"
  end

  defp pad_right(s, n) do
    len = String.length(s)

    if len >= n do
      String.slice(s, 0, n)
    else
      s <> spaces(n - len)
    end
  end

  defp spaces(n) when n <= 0, do: ""
  defp spaces(n), do: String.duplicate(" ", n)
end
