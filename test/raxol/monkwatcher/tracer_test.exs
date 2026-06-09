defmodule Raxol.Monkwatcher.TracerTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.Model
  alias Raxol.Monkwatcher.App.Updaters

  test "monk_killed increments session.monks_killed and emits no command" do
    model = Model.new(1_000_000)
    {model_after, commands} = Updaters.monk_killed(model, %{}, 1_000_001)

    assert model_after.session.monks_killed == 1
    assert commands == []
  end
end
