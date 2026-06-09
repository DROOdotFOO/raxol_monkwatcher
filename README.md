# raxol_monkwatcher

**OSRS AFK combat training, on your wrist.** Reads your Old School RuneScape session through a RuneLite bridge plugin and pushes the idle timer, current skill, XP progress, and hit count to an Apple Watch. Terminal view and a Telegram pinned message come along for the ride. Written in Elixir on top of Raxol.

## Background

OSRS is the 2007-era version of RuneScape, maintained by Jagex as a separate game. A defence pure is an account built around 1 attack, 1 strength, and a target defence level (75 is the common one) to land in a specific PvP combat-level bracket.

The Edgeville Monastery is the canonical defence-pure training spot. Level 5 monks. They don't auto-aggro once you're past combat 10, they rarely land hits, they self-heal, and they're worth roughly 2.5k defence XP an hour. Going from 1 to 75 is about 480 hours of monk time. It's abysmal. It's also the most AFK training method in the game — stand in a corner, click occasionally, stare at the wall.

OSRS has two timers that matter here. While you're in active combat, auto-retaliate keeps your character swinging for up to 20 minutes. When that runs out you stop attacking back, and 5 minutes of true idle later the game logs you out. So one click at a monk buys you roughly 25 minutes of AFK before you need to act. This app buzzes your wrist when you're 60 seconds from logout, names the skill you're training and the level you're at, and gives you a snooze button. You can be anywhere in the house.

## Works for any combat pure

The wire format treats the trained skill as data. A 1/99/1 pure at sand crabs sees `STRENGTH` in the header. A range tank at chinchompas sees `RANGED`. Anything where you grind a combat skill on an AFK target.

## Status

Working end-to-end. 162 tests, 13 properties, 0 failures. Boots via OTP supervisor; Plugin.Bridge and the surfaces gate on app config.

Still needed: a real RuneLite plugin emitting the wire format, an APNS adapter for the watch, a Telegex hookup for Telegram, hand-drawn ASCII frames in `Pet.Frames`.

## Reading order

| If you are                          | Read                                                                  |
|-------------------------------------|-----------------------------------------------------------------------|
| Reviewing the architecture          | [`docs/architecture.md`](docs/architecture.md)                        |
| Implementing or extending a module  | [`docs/app-structure.md`](docs/app-structure.md)                      |
| Asking "why was X decided this way" | [`docs/adr/`](docs/adr/) — ADRs                                       |
| An AI agent picking up the codebase | [`CLAUDE.md`](CLAUDE.md)                                              |

## Architecture

```
                    RuneLite plugin
                          |  UDS, newline JSON
                          v
                    Plugin.Bridge --decode--> Plugin.Codec
                          |  dispatch_fn
                          v
   pure core:        App (TEA)
   StateMachine  <-- Updaters --> Model
   Pet                   |
   Session               |  broadcast on "alerts"
   Fidget                v
                    Phoenix.PubSub
                       |       |
                       v       v
              Surfaces.Watch   Surfaces.Telegram
                  (APNS)         (Bot API)
```

`StateMachine`, `Pet`, `Session`, `Fidget`, `Updaters`, `Codec`, and `View.*` are pure modules. The end-to-end smoke test at `test/raxol/monkwatcher/e2e_test.exs` drives a fake UDS server through the whole pipeline.

## ADR index

| #    | Decision                                                                  |
|------|---------------------------------------------------------------------------|
| 0001 | [TEA single-model for the app core](docs/adr/0001-adopt-tea-single-model.md) |
| 0002 | [Unix Domain Socket with newline-delimited JSON for the bridge](docs/adr/0002-uds-newline-json-bridge.md) |
| 0003 | [StateMachine as a pure module](docs/adr/0003-pure-state-machine.md) |
| 0004 | [Phoenix.PubSub as the App-to-Surfaces seam](docs/adr/0004-pubsub-app-to-surfaces.md) |
| 0005 | [No persistence across crashes or restarts](docs/adr/0005-no-persistence.md) |
| 0006 | [Conditional supervisor children for optional surfaces](docs/adr/0006-conditional-supervisor-surfaces.md) |

## Won't do

- No auto-click. Ever.
- No XP/hr countdowns.
- No training-spot recommendations.
- No persistence between sessions.
- No leaderboards or social features.
- No music or sound.

## License

MIT. See [LICENSE](LICENSE).
