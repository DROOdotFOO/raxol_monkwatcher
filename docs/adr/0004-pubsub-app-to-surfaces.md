# 4. Use Phoenix.PubSub as the App-to-Surfaces seam

Date: 2026-06-09

## Status

Accepted (2026-06-10). Payload shapes evolved during implementation — the authoritative list is in the Decision section below.

## Context

`App` holds the authoritative model. Two surfaces (Telegram, Watch) project that model to their outputs. Both are GenServers that push to external systems and are *optional* — they're behind feature flags (`telegram_enabled`, `watch_enabled`). The seam between App and surfaces needs to support: zero, one, or two listeners; surfaces starting after App; surfaces crashing independently; no compile-time coupling.

Options:

- **Direct calls from App to each surface module** (`Surfaces.Watch.notify(...)`). Compile-time coupling; App must know which surfaces exist. Adding Discord means editing App.
- **A list of listener PIDs in App's state**. App holds references; surfaces register on startup. Decouples compile-time but couples lifecycle (App must handle dead PIDs).
- **`Registry` + manual broadcast**. Lightweight but every broadcast site reimplements the loop.
- **`Phoenix.PubSub`**. Topic-based fan-out, dead subscriber cleanup automatic, zero subscribers is a valid state.

The codebase has no other persistent need for a message bus — this is the only fan-out point. We accept `Phoenix.PubSub` as a dependency for this one seam.

## Decision

We use `Phoenix.PubSub` (started as `Raxol.Monkwatcher.PubSub` in the supervisor) with a single topic returned by `Channels.alerts/0` (`"alerts"`). `App` broadcasts well-typed payloads. The shipped shapes (built by `Notifications` via `Commands.broadcast_alert/1`):

- `{:idle_alert, :warning | :critical, model, now}`
- `{:milestone, :hits, integer, model, now}` (hits, not kills — the wire term is "hits" everywhere a user sees it)
- `{:milestone, :level, {skill_atom, level_integer}}` (level-ups carry no model; surfaces format from the tuple)
- `{:death, model, now}`

Each payload includes `now` (the tick timestamp that triggered the event) so surfaces don't have to read the wall clock to format an idle string. Surfaces subscribe in their `init/1` and pattern-match in `handle_info/2`. The model is passed by value (a small map); surfaces extract what they need.

To prevent typo-induced silent drops, the topic name is a function: `Raxol.Monkwatcher.Channels.alerts/0` returns `"alerts"`. All sites call the function.

## Consequences

**Positive**

- Zero surfaces is a valid configuration. Headless app (just a terminal grind) runs the same code.
- Surfaces crash independently; PubSub cleans up subscriptions.
- Adding a new surface is a new GenServer + a new conditional in `Application.optional_surfaces/0`. No change to App.
- Payloads include the full model snapshot — surfaces don't need to query App back, avoiding round-trip latency on the alert path.

**Negative**

- Broadcasting the model on every alert is a copy. The model is small (<2KB); this is fine, but the temptation to embed large blobs (kill history, frames) must be resisted.
- `Phoenix.PubSub` is a dependency for one seam. If it becomes the only reason to depend on the Phoenix ecosystem, the cost-benefit shifts. A future replacement with `Registry.dispatch/3` is plausible — coupling score 10 (medium) per architecture.md §2.
- Ordering: PubSub is fire-and-forget. If `App.update/2` emits a warning and then a critical in the same call, the order seen by surfaces is the broadcast order, not necessarily the receive order across subscribers. Acceptable for this use case (each surface processes its own queue).
