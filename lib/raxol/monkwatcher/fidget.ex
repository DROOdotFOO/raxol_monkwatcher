defmodule Raxol.Monkwatcher.Fidget do
  @cycle_threshold 30

  defstruct scroll_position: 0, view_mode: :pet

  def new, do: %__MODULE__{}

  def scroll(%__MODULE__{} = fidget, delta) when is_integer(delta) do
    new_pos = fidget.scroll_position + delta

    cond do
      new_pos > @cycle_threshold ->
        %{fidget | scroll_position: 0, view_mode: next_view(fidget.view_mode)}

      new_pos < -@cycle_threshold ->
        %{fidget | scroll_position: 0, view_mode: prev_view(fidget.view_mode)}

      true ->
        %{fidget | scroll_position: new_pos}
    end
  end

  defp next_view(:pet), do: :history
  defp next_view(:history), do: :stats
  defp next_view(:stats), do: :sparkline
  defp next_view(:sparkline), do: :pet

  defp prev_view(:pet), do: :sparkline
  defp prev_view(:sparkline), do: :stats
  defp prev_view(:stats), do: :history
  defp prev_view(:history), do: :pet
end

