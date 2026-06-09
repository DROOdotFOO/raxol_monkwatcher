# 5. Do not persist session state across crashes or restarts

Date: 2026-06-09

## Status

Proposed

## Context

The model holds the full session: monks killed, kill history, deaths, levels gained, pet name, pet mood. None of it is written to disk.

The product framing (`raxol_monkwatcher.md`, "Things deliberately not included") explicitly rules out memory of past sessions: "Each session is a fresh pet with a fresh name. Persistent stats are anti-Tamagotchi — half the charm is the temporary bond."

This decision has architectural consequences beyond the design pivot:

- An `App` crash drops the in-flight session entirely.
- A laptop reboot mid-grind drops the session.
- There is no migration path, no schema versioning, no DB dependency.

The question is whether we're confident enough in the framing to bake non-persistence into the architecture, or whether we should add a thin persistence layer (DETS, a JSON dump on shutdown) as a safety net.

## Decision

We will not persist any session state. The Erlang VM is the only store. Specifically:

- No DETS, no Mnesia, no SQLite, no JSON dump on shutdown.
- `App.init/1` constructs a fresh model. `random_monk_name/0` picks a new name.
- The supervision strategy is `:one_for_one`. If `App` crashes, the supervisor restarts it with a fresh model — and that is correct, not a bug.
- The supervisor's restart intensity should be tuned so that a persistently-crashing App fails the whole supervisor rather than infinite-restarting. (Default `max_restarts: 3, max_seconds: 5` is fine.)

## Consequences

**Positive**

- Zero schema migrations, ever.
- No "what happens if the DB is corrupt" branch.
- The pet bond is genuinely temporary, matching the design intent.
- Crash-only design: the app can be killed at any moment without data loss because there is no data to lose.

**Negative**

- A six-hour grind that crashes at hour five loses the kill count and pet history. Mitigated by: the underlying OSRS account still has the XP gained (RuneLite is authoritative for game state), and pet history is the loss — a feature feature.
- No way to answer "how many monks did I kill last Tuesday." If that turns out to be a user need, this ADR is superseded, not amended.
- The `kill_history` cap at 50 is the only thing protecting the model from unbounded growth in a single session. That cap must stay.
