defmodule Raxol.Monkwatcher.MixProject do
  use Mix.Project

  def project do
    [
      app: :raxol_monkwatcher,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Raxol app that watches an OSRS session via the RuneLite bridge plugin."
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["DROO AMOR"],
      files: ~w(lib priv mix.exs README.md LICENSE)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Raxol.Monkwatcher.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:stream_data, "~> 1.0", only: :test}
    ]
  end
end
