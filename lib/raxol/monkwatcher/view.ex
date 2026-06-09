defmodule Raxol.Monkwatcher.View do
  @moduledoc """
  Render dispatcher. Selects the subview based on `model.fidget.view_mode`.
  Each subview is a pure function `(model, now) -> String.t()`.
  """

  alias Raxol.Monkwatcher.View.{HistoryView, PetView, SparklineView, StatsView}

  def render(model, now) do
    case model.fidget.view_mode do
      :pet -> PetView.render(model, now)
      :history -> HistoryView.render(model, now)
      :stats -> StatsView.render(model, now)
      :sparkline -> SparklineView.render(model, now)
    end
  end
end
