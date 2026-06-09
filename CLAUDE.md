# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

Pre-implementation. The repository currently contains only `raxol_monkwatcher.md`, the design spec. There is no `mix.exs`, no `lib/`, and no test scaffolding yet. The spec is the source of truth — treat it as the contract for what gets built.

When implementing, follow the build order in `raxol_monkwatcher.md` ("What to build first, in order"): RuneLite plugin -> PluginBridge + logging stub -> StateMachine + property tests -> Pet module + ASCII frames -> full App -> Watch surface -> scroll wheel -> Telegram surface.

## What this is

A Raxol app that watches an OSRS (Old School RuneScape) session via a RuneLite bridge plugin. One TEA module (`Raxol.Monkwatcher.App`) drives three surfaces: terminal (fidget toy), Telegram (pinned-message status), Apple Watch (terse pushes via `raxol_watch`).

The framing is **Tamagotchi-meets-fidget-spinner**, not an alarm clock. The pet IS the monk being hit. Kill rate feeds it; idle minutes make it restless; the 4-minute logout warning is just one expression of pet state. Do not regress this framing back to "logout-prevention utility" — the surface IS the product.

## Architecture invariants

These are load-bearing decisions from the spec. Don't quietly relax them:

- **One TEA model, pure update/view.** `Raxol.Monkwatcher.App` owns the model. `StateMachine` and `Pet` are pure modules (no processes, no `System.system_time` inside — `now` is threaded in as an argument so they're property-testable).
- **PluginBridge uses `:gen_tcp.connect({:local, path}, 0, [packet: :line, active: :once])`.** Unix domain socket, line-framed JSON. `active: :once` is the backpressure mode — never switch to `active: true`.
- **PluginBridge reconnects with exponential backoff** (500ms -> 10s cap). RuneLite and Raxol can start in any order; either side can restart without the other noticing.
- **Surfaces subscribe to `Phoenix.PubSub` topic `"alerts"`.** App emits `{:idle_alert, level, model}`, `{:milestone, :kills, n}`, `{:pet_event, :fainted, model}`. Surfaces are pluggable and conditionally started in `Application.start/2`.
- **State machine thresholds**: `@warning_idle_ms = 240_000` (4:00), `@critical_idle_ms = 280_000` (4:40), `@recovery_window_ms = 30_000`. Any combat tick resets `notified` so a new idle period re-fires.
- **Tap-back routing.** Watch actions route via `raxol_watch`'s `action_map` to `Raxol.Monkwatcher.App.dispatch/1`. Telegram callback queries route the same way via `raxol_telegram`'s Bot module.

## Notification copy rules

The spec enforces three rules that are easy to violate without noticing:

1. **One-word title, one-number body** on the watch (`"Monk"` + `"4:00"`).
2. **No emoji in watch pushes.** Inconsistent rendering across watchOS versions. Emoji are fine in Telegram.
3. **One button max on the wrist**, and the **critical (4:40) push has zero actions** — glance and act, no button labels to read.

## Telegram surface

One pinned message per session, edited in place (not new messages per update). The `message_id` is held in the GenServer state. Format: `"🧘 4:12 · 247 · 67/85"` (idle · kills · HP/maxHP). Edit dedup is handled by `raxol_telegram`'s Session layer — don't reimplement it in the surface.

## Pet module

Pure derivation from the model. Mood ordering matters (first match wins): `:fainted` -> `:panicked` -> `:sleepy` -> `:triumphant` -> `:hungry` -> `:content`. Each mood has 8 ASCII frames in `Raxol.Monkwatcher.Pet.Frames`; `frame/2` rotates by `rem(abs(scroll_pos), 8)`. The scroll wheel is the primary fidget input — it spins the avatar, cycles views past a ±30-detent threshold, and feeds `pet.energy` at 0.001 per detent.

## Testing

- **StateMachine and Pet are pure** — test them as pure functions with property-based tests (StreamData). The spec ships three example properties to start from:
  - `:warning` never fires before 4 minutes of continuous idle.
  - `:warning` fires exactly once per continuous idle period.
  - Any combat tick resets the notification set (so two idle periods produce two warnings).
- **Replay recorded RuneLite sessions** against the StateMachine. The stub App in step 2 of the build order exists specifically to record real wire-format data for replay-based tuning of `@recovery_window_ms` and the `@attack_animations` set.
- **No mocks.** Use real PubSub, real `:gen_tcp` against a test UDS, and replay fixtures for plugin ticks.

## Things deliberately excluded (do not propose adding)

The spec is explicit about these — they are anti-features, not gaps:

- No auto-click, ever. The line is the line.
- No XP/hour beyond kills/hr. RuneLite already tracks XP.
- No "best monk location" guidance. This is a companion, not a coach.
- No persistence across sessions. Fresh pet, fresh name, every session — the temporary bond is the point.
- No social features (leaderboards, shared pets, clan integration).
- No music or sound — OSRS owns the audio.
- No `raxol_payments` integration. This project is the one place where it would be deeply wrong.

If a request drifts toward any of these, surface the conflict with the spec before implementing.

## Conventions

This is an Elixir/Raxol project, so the Elixir patterns in `~/CLAUDE.md` apply (pattern matching, pipes, `with` chains, ExUnit, `Req` for HTTP). The `raxol` skill auto-triggers on Raxol imports — defer to it for framework-specific patterns (TEA structure, headless mode, MCP tools).

The design doc uses some emoji in Telegram copy examples (`🧘`, `💤`, `🎯`) — those are intentional and stay. Everywhere else, ASCII per the user's global preference.
