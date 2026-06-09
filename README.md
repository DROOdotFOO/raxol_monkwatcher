# raxol_monkwatcher

A Raxol app that watches an OSRS session via a RuneLite bridge plugin. One TEA module, three surfaces (terminal, Telegram, Apple Watch). Designed as a Tamagotchi-meets-fidget-spinner — ambient companionship for a six-hour monk grind, not an alarm clock.

## Status

**Pre-implementation.** The repository currently contains the design spec and architectural planning docs. No `mix.exs`, no `lib/`, no tests yet. The build order is defined in the spec ("What to build first, in order").

## Reading order

| If you are...                          | Read                                                                  |
|----------------------------------------|-----------------------------------------------------------------------|
| New to the project                     | [`raxol_monkwatcher.md`](raxol_monkwatcher.md) — the design spec      |
| Reviewing the proposed architecture    | [`docs/architecture.md`](docs/architecture.md)                        |
| Implementing modules                   | [`docs/app-structure.md`](docs/app-structure.md)                      |
| Writing tests                          | [`docs/testing-strategy.md`](docs/testing-strategy.md)                |
| Asking "why was X decided this way?"   | [`docs/adr/`](docs/adr/) — Architecture Decision Records              |
| Operating as an AI agent in this repo  | [`CLAUDE.md`](CLAUDE.md)                                              |

## Design pivot in one line

The pet IS the monk you're hitting. Kill rate feeds it; idle minutes make it restless; the 4-minute logout warning is one expression of pet state, not the product itself. See the spec's "Design pivot" section for the full framing.

## Architecture in one diagram

```
                    RuneLite plugin
                          | UDS, newline JSON
                          v
                    Plugin.Bridge --decode--> Plugin.Codec
                          | dispatch_fn
                          v
   pure core:        App (TEA)
   StateMachine  <-- Updaters --> Model
   Pet                   |
   Session               | broadcast on "alerts"
   Fidget                v
                    Phoenix.PubSub
                       |       |
                       v       v
              Surfaces.Watch   Surfaces.Telegram
                  (APNS)         (Bot API)
```

Pure modules (`StateMachine`, `Pet`, `Session`, `Fidget`, `Updaters`, `Codec`, `View.*`) are property-testable without ever starting a process. The first nine items of the build order require zero OTP.

## ADR index

| #    | Decision                                                                  |
|------|---------------------------------------------------------------------------|
| 0001 | [Adopt TEA single-model for the app core](docs/adr/0001-adopt-tea-single-model.md) |
| 0002 | [Unix Domain Socket with newline-delimited JSON for the RuneLite bridge](docs/adr/0002-uds-newline-json-bridge.md) |
| 0003 | [StateMachine as a pure module, not `gen_statem`](docs/adr/0003-pure-state-machine.md) |
| 0004 | [Phoenix.PubSub as the App-to-Surfaces seam](docs/adr/0004-pubsub-app-to-surfaces.md) |
| 0005 | [No persistence of session state across crashes or restarts](docs/adr/0005-no-persistence.md) |
| 0006 | [Conditional supervisor children for optional surfaces](docs/adr/0006-conditional-supervisor-surfaces.md) |

## Things this app deliberately will not do

From the spec's "Things deliberately not included" — these are anti-features, not gaps:

- No auto-click, ever
- No XP/hour calculator beyond kills/hr
- No "best monk location" guidance
- No persistence across sessions
- No leaderboards, shared pets, or clan integration
- No music or sound
- No payments integration

If a contribution drifts toward any of these, surface the conflict with the spec first.

## License

MIT. See [LICENSE](LICENSE).
