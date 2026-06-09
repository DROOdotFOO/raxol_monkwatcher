defmodule Raxol.Monkwatcher.Application do
  @moduledoc """
  OTP boot. Always starts `Phoenix.PubSub` under the canonical name
  `Raxol.Monkwatcher.PubSub`. Optional surfaces (Watch, Telegram) are
  conditionally added to the supervisor based on application config.

  Adding a third surface in the future means one new child here plus a
  config flag — no other module changes.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Raxol.Monkwatcher.PubSub},
        {Raxol.Monkwatcher.App, []}
      ] ++ optional_bridge() ++ optional_surfaces()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Raxol.Monkwatcher.Supervisor
    )
  end

  defp optional_bridge do
    case Application.get_env(:raxol_monkwatcher, :plugin_socket_path) do
      nil ->
        []

      path when is_binary(path) ->
        [{Raxol.Monkwatcher.Plugin.Bridge, socket_path: path}]
    end
  end

  defp optional_surfaces do
    []
    |> maybe_add(
      Application.get_env(:raxol_monkwatcher, :watch_enabled, false),
      {Raxol.Monkwatcher.Surfaces.Watch, pubsub: Raxol.Monkwatcher.PubSub}
    )
    |> maybe_add(
      Application.get_env(:raxol_monkwatcher, :telegram_enabled, false),
      {Raxol.Monkwatcher.Surfaces.Telegram, pubsub: Raxol.Monkwatcher.PubSub}
    )
  end

  defp maybe_add(list, true, child), do: list ++ [child]
  defp maybe_add(list, false, _), do: list
end
