# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Elixir app that watches an OSRS (Old School RuneScape) defence-pure / AFK-combat session through a RuneLite bridge plugin and fans the model out to surfaces: an Apple Watch push (`Surfaces.Watch`) and a Telegram pinned-message updater (`Surfaces.Telegram`). The framing in `README.md` is the product framing — wrist-first AFK companion for monk/sand-crab/chinchompa training. Don't regress it into a generic Raxol TUI demo, and don't propose the won't-do list at the bottom of the README.

The repo name is historical: the actual `raxol` framework is not (yet) a dependency. The current stack is `:jason`, `:phoenix_pubsub`, and `:stream_data` (test). `lib/raxol/monkwatcher/...` is just the namespace.

## Commands

```bash
mix deps.get                                       # install jason, phoenix_pubsub, stream_data
mix test                                           # full suite (~160 tests, ~13 properties)
mix test test/raxol/monkwatcher/state_machine_test.exs   # one file
mix test test/raxol/monkwatcher/pet_test.exs:42    # one test by line number
mix test --only property                           # if/when tagged; otherwise omit
mix format                                         # gofmt-style; .formatter.exs covers lib + test
mix compile --warnings-as-errors                   # CI gate
```

There is no `mix precommit` alias yet. Run `mix format && mix test` before pushing.

## Architecture

The full picture lives in `docs/architecture.md` and `docs/app-structure.md`. The six load-bearing decisions are in `docs/adr/` (0001 TEA single-model, 0002 UDS newline JSON, 0003 pure StateMachine, 0004 PubSub seam, 0005 no persistence, 0006 conditional surfaces). Read those before proposing structural changes.

Short version of the boundaries:

```
RuneLite plugin
     | UDS, newline-delimited JSON
     v
Plugin.Bridge (GenServer)
     | Plugin.Codec.decode/1 -> %Tick{} | %Event{}
     v
App (GenServer)                <-- single source of truth: Model
     | App.Updaters.* (pure)        threads `now` from tick payloads
     | StateMachine / Pet / Session / Fidget (all pure)
     | Notifications -> Commands (pure command tuples)
     v
Phoenix.PubSub topic Channels.alerts()   ("alerts")
     |                              |
     v                              v
Surfaces.Watch (GenServer)     Surfaces.Telegram (GenServer)
```

### Invariants (don't relax without an ADR)

- **One model, owned by `Raxol.Monkwatcher.App`.** Inbound is `App.dispatch/1`; the GenServer routes by struct/tuple shape to a pure `App.Updaters` function that returns `{model, commands}`. The GenServer executes commands (currently only `{:broadcast_alert, payload}`) and stores the new model. No business logic in `App` itself.
- **Pure core, framework-free.** `StateMachine`, `Pet`, `Session`, `Fidget`, `Model`, `Notifications`, `Commands`, `Activity`, `Plugin.Codec`, and the `View.*` modules are pure. They take `now` as an argument — never call `System.system_time` inside. App, Plugin.Bridge, and the two Surfaces are the only processes.
- **`Plugin.Bridge` uses `:gen_tcp.connect({:local, path}, 0, mode: :binary, active: :once, packet: :line)`** with exponential reconnect (500 ms → 10 s cap). Backpressure is `active: :once` — don't switch to `active: true`. `dispatch_fn` is injected so tests can capture decoded messages without booting `App`.
- **`Plugin.Codec` is the only place that touches stringly-keyed JSON.** Downstream modules pattern-match on `%Plugin.Codec.Tick{}` / `%Plugin.Codec.Event{}` structs. Renaming a wire field (`isMonk` → `is_combat`, etc.) is a one-line Codec change.
- **Skill atoms come from a whitelist** (`@known_skills` in `Plugin.Codec` and again in `App`) to avoid atom exhaustion. New skills mean adding to both whitelists.
- **`Application.start/2` conditionally adds Plugin.Bridge and surfaces** based on `:raxol_monkwatcher` config (`:plugin_socket_path`, `:watch_enabled`, `:telegram_enabled`). Boot order is fixed: PubSub → App → Bridge → Surfaces. Surfaces subscribe to `Channels.alerts()` in `init/1`, so App must already be up.
- **State machine thresholds (in `StateMachine`):** `@warning_idle_ms = 240_000` (4:00), `@critical_idle_ms = 280_000` (4:40), `@recovery_window_ms = 30_000`. A fighting tick resets `notified` so each fresh idle window re-fires once.
- **Pet mood ordering (first match wins, in `Pet.derive_target_mood/2`):** `:fainted` → `:panicked` → `:sleepy` → `:triumphant` → `:hungry` → `:content`. Mood is smoothed via `Pet.tick_mood/3` over `@transition_ticks` (8) ticks. Tests pin the ordering; don't reshuffle the `cond`.

### Surface copy rules

- **`Surfaces.Watch.to_notification/1` is the pure contract.** Title comes from `Activity.title/1` (region match → skill name → `"Combat"`) — not hardcoded `"Monks"`. No emoji in any field (watchOS rendering is inconsistent). The `:critical` payload has **no `actions`** key: glance and click, no button to read. The `:warning` payload has one action (`snooze`, `+60s`).
- **`Surfaces.Telegram.format_pinned/2` is the pure contract.** Single line: `"<idle_mmss> * <hits> hits * <level> <skill_code> * <hp>/<max_hp>"`. Skill codes (`att/str/def/hp/range/mage/pray`) live in `@skill_codes` in the surface. The README/spec examples may show emoji and middle-dot separators; the implementation uses `*` and no emoji. If you change the format, update both the moduledoc example and `surfaces/telegram_test.exs`.

### Anti-features

Listed in `README.md` "Won't do" and the ADRs. The shortlist: no auto-click, no XP/hr beyond hits/hr, no training-spot recommendations, no cross-session persistence (fresh model on every supervisor restart — ADR-0005), no leaderboards or social, no sound. Surface conflicts with these before implementing.

## Testing

- **No mocks.** Pure modules are tested as pure functions with `StreamData` properties + concrete examples. `Plugin.Bridge` integration tests drive a real UDS socket via `test/support/fake_plugin.ex` (`FakePlugin.start/2` + `FakePlugin.tmp_socket_path/0`). Surfaces are tested by injecting `send_fn` and asserting on the captured value, not by stubbing HTTP.
- **`now` is an argument, not `System.system_time`.** Tests pass concrete millis. `StreamData` generators in property tests should do the same.
- **One test file per production module.** Test names describe behavior, not implementation (`"warning never fires before 4 minutes of continuous idle"`, not `"check_thresholds_idle_240s"`).
- **`async: true`** on pure-module tests. Surface tests that share the PubSub namespace need `async: false`.
- The end-to-end smoke test (`test/raxol/monkwatcher/e2e_test.exs`) wires a fake UDS server through Codec → Bridge → App → PubSub → a test-subscribed process. It's the canary for boot-order regressions.

## Conventions

This is an Elixir project so the patterns in `~/CLAUDE.md` apply: pattern matching, pipes, `with` chains, `Req` for HTTP if/when added, descriptive ExUnit names. ASCII over emoji per global preference — except inside Telegram copy where emoji are tolerated by the spec, currently unused by the implementation.

The `raxol` skill auto-triggers on Raxol imports — there are none yet, so it should not fire here. If the project later adopts Raxol Core for the terminal surface, defer to that skill for TEA-runtime specifics.
