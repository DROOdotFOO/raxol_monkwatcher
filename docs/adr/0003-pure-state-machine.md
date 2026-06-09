# 3. Implement StateMachine as a pure module, not `gen_statem`

Date: 2026-06-09

## Status

Proposed

## Context

The idle-detection state machine has six states and well-defined transitions driven by plugin tick payloads. Erlang/OTP ships `gen_statem`, which would be the natural choice for a stateful FSM.

The hard requirement is **replayability**: the spec's build order has us recording real OSRS sessions to a file and replaying them against the state machine to tune `@recovery_window_ms`, the `@attack_animations` set, and the threshold timings. Replay must be deterministic, repeatable, and fast (thousands of iterations during tuning).

`gen_statem` introduces a process, message-passing latency, timer side effects, and a startup/shutdown lifecycle. Each of those is a barrier to fast, deterministic replay.

A pure module — `StateMachine.apply_tick(sm, payload) -> sm'` and `StateMachine.check_thresholds(sm, now) -> {sm', fires}` — has none of those barriers and can be exercised at hundreds of thousands of ticks per second by property tests.

## Decision

We will implement `Raxol.Monkwatcher.StateMachine` as a pure module:

- A struct `%StateMachine{state, state_since_ms, last_combat_ms, last_tick, last_payload, notified}`.
- `apply_tick/2` and `apply_event/4` return a new struct.
- `check_thresholds/2` is explicitly called by `App` with `now`, returning fires (`[:warning, :critical]`) and the updated struct.
- No `Process.send_after`, no timers, no GenServer. The App's tick cadence (driven by RuneLite) advances the clock for the FSM.

`StreamData` property tests verify: warnings never fire before 4:00, fire exactly once per continuous idle period, and reset on any combat tick.

## Consequences

**Positive**

- Replay is trivial: `Enum.reduce(recorded_ticks, StateMachine.new(), &apply_tick/2)`.
- Property tests run at maximum speed; no process startup.
- The FSM is testable from `iex` with no setup.
- Threshold tuning is a config change + property re-run, not a process restart.

**Negative**

- The clock is driven externally. If `App` stops feeding ticks (e.g., PluginBridge dies and the reconnect window is long), the FSM "freezes" — `:idle` won't advance to `:warning` because no tick is checking the threshold. Mitigation: `App` schedules a self-tick (`Process.send_after(self(), :recheck_thresholds, 1000)`) as a heartbeat, even with no plugin data.
- Loss of `gen_statem`'s built-in features (state enter/leave callbacks, postpone, generic timeouts). The FSM is simple enough that we don't need them; if we do later, the pure module can be wrapped by a `gen_statem` without changing the property tests.
