defmodule Raxol.Monkwatcher.Pet.Frames do
  @moduledoc """
  ASCII art frame sets keyed by internal mood. Each mood owns an N-frame
  cycle; the view rotates through frames via the scroll-wheel position so
  the figure animates as the user fidgets.

  These are placeholder frames. The actual art is intentionally deferred —
  the contract (a list of strings per mood, rotation by index) is what
  upstream depends on.
  """

  def for_mood(:content), do: [".o.", "o.o", ".o."]
  def for_mood(:sleepy), do: ["-_-", "-.-", "z.z", "z-z"]
  def for_mood(:hungry), do: ["o.o", "o_o"]
  def for_mood(:panicked), do: ["O_O", "0_0", "O.O", "0.0"]
  def for_mood(:triumphant), do: ["\\o/", "|o|", "/o\\"]
  def for_mood(:fainted), do: ["x_x", "x.x"]
end
