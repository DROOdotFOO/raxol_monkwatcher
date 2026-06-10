# 6. Fan out surfaces via conditional supervisor children, not a registry

Date: 2026-06-09

## Status

Accepted (2026-06-10). Implemented in `Raxol.Monkwatcher.Application.start/2` with `optional_bridge/0` and `optional_surfaces/0`. The chezmoi-toggle paragraph below describes desired integration with the user's dotfiles; the wiring does not exist in this repo.

## Context

Two of the three surfaces are optional. The user controls them via application config (`telegram_enabled`, `watch_enabled`). We need a mechanism to start zero, one, or two of them at boot.

Options:

- **Always start them; have them no-op when disabled**. Wastes a GenServer and a PubSub subscription per disabled surface. Couples disabled surfaces to their eventual external dependencies (Telegram Bot client, APNS adapter) even when unused — the modules still need to compile and link.
- **A surface registry**. Surfaces register themselves on startup, the supervisor reads the registry to decide what to start. Inversion of control without a clear payoff for two surfaces.
- **Conditional supervisor children**. `Application.start/2` builds the child list with `if Application.get_env(...)` gates. Disabled surfaces are never compiled into the supervision tree at boot.
- **Multiple OTP applications**. Split each surface into its own app with its own `application.ex`. Heavy for personal-tool scale.

## Decision

We will assemble the supervisor child list conditionally in `Raxol.Monkwatcher.Application.start/2`. A small helper:

```elixir
defp optional_surfaces do
  []
  |> add_if(Application.get_env(:raxol_monkwatcher, :telegram_enabled, false),
           Raxol.Monkwatcher.Surfaces.Telegram)
  |> add_if(Application.get_env(:raxol_monkwatcher, :watch_enabled, false),
           Raxol.Monkwatcher.Surfaces.Watch)
end
```

reads the flag once at boot. Re-enabling a surface requires an app restart, which is acceptable for a personal tool.

## Consequences

**Positive**

- Zero overhead for disabled surfaces.
- The set of running surfaces is visible in one place (`children` in `Application.start/2`).
- Adding a third surface is one new module + one `add_if` call.

**Negative**

- Toggling at runtime requires a restart. If the user enables Telegram mid-session, the existing session is dropped (consistent with ADR-0005 but worth flagging).
- The flags live in `Application` env, set by `config/runtime.exs`. The chezmoi-driven toggles in `chezmoi.toml` flow through chezmoi template rendering of `config/runtime.exs` — wire this up so the same `{{ .telegram }}` boolean drives both the Raxol app and the chezmoi-managed shell config.
- Once external clients are added (Telegram Bot, APNS), they will be compile-time dependencies of the umbrella even when their surface is gated off. If they fail to compile, the whole app fails to compile. Mitigation: keep their imports inside the surface modules, not at the App or `Plugin.Bridge` level.
