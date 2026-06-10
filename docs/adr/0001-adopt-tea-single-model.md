# 1. Adopt TEA single-model architecture for the app core

Date: 2026-06-09

## Status

Accepted (2026-06-10). The single-model intent landed; the runtime is a plain `GenServer` calling pure `App.Updaters.*` functions, not the Raxol TEA runtime described below — `raxol` is not a dependency. References to `App.view/1` and Raxol commands should be read as "the equivalent pure-function rendering and `{:broadcast_alert, payload}` commands in this codebase."

## Context

The app projects one source of truth (an OSRS session and a derived pet) to two concurrent surfaces: Telegram and Apple Watch. Each surface must agree on what the user is looking at right now. The session is event-driven (RuneLite ticks, kills, deaths) and the model is small enough to keep entirely in memory.

The available alternatives:

- **One GenServer per concern** (session, pet, view state) coordinated by messages. Familiar in OTP, but every cross-concern question — "does this kill bump pet fullness above 0.8?" — requires a multi-process round-trip and introduces ordering bugs.
- **TEA single model + pure `update/2`** (what Raxol provides). The whole model is rebuilt per event; cross-concern questions are local function calls; the terminal view is a pure function of the model.
- **`gen_statem` with a giant data map.** Wire-format-driven state transitions are easy but the model becomes the `gen_statem` data, which leaks state-machine ceremony into pet derivation and view rendering.

The model is small (a few hundred bytes), event rate is low (~600ms tick + sparse events), and we want surfaces to be eventually-consistent projections, not authoritative state holders.

## Decision

We will model the entire app as a single TEA module (`Raxol.Monkwatcher.App`) with a single immutable map as the model. `update/2` is pure per-branch. Effects (PubSub broadcasts, notifications) are returned as commands the Raxol runtime executes asynchronously.

Surfaces (`Surfaces.Telegram`, `Surfaces.Watch`) are not part of the model. They subscribe to `Phoenix.PubSub` and project the model state into their own output. They never write to the model — they only send messages back via `App.dispatch/1` for user input (tap-back, callback buttons).

## Consequences

**Positive**

- Cross-concern questions are pure function calls: `Pet.derive_mood(model, now)` sees session + state machine + fidget input in one place.
- The model is property-testable as data; `update/2` is property-testable as a pure function.
- Surfaces are pluggable. Adding a Discord surface means one new GenServer that subscribes to `"alerts"`; no change to App.
- A crash of App means a fresh model. This is consistent with the no-persistence stance (ADR-0005).

**Negative**

- `App` becomes a hotspot. The `update/2` function will have many branches; without discipline it grows into a god module (see architecture.md R1).
- Every event rebuilds the whole model (structurally shared but still). For this scale (one user, ~1Hz events) it is irrelevant; for a hypothetical multi-session future it would not scale.
- The single registered name (`Raxol.Monkwatcher.App`) means one app per node. Acceptable for a personal tool.
