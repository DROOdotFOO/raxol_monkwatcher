# raxol_monkwatcher

**OSRS AFK combat training, on your wrist.** Reads your Old School RuneScape session through a RuneLite bridge plugin and pushes the idle timer, current skill, XP progress, and hit count to an Apple Watch — so you can train monks (or crabs, or chinchompas) without keeping the OSRS window in focus. A terminal view and a Telegram pinned message are along for the ride if you want them. Written in Elixir on top of Raxol.

The watch is the headline. The whole point is that you can be in another room, on the couch, walking the dog, and still know when you're sixty seconds from being logged out. Tap the snooze button on the buzz, get sixty more seconds, go back to your sandwich.

## Background

OSRS is the 2007-era version of RuneScape, frozen at that point and maintained by Jagex as its own game since 2013. Players decide how their character trains, and "pures" are accounts built around keeping specific combat stats at 1 to land in a particular combat-level bracket. A defence pure trains defence to a target level (usually 75) while keeping attack and strength at 1. The result is a character that can't hit anything in melee but absorbs hits well — useful for tanking on range or magic builds.

The standard place to train defence from 1 is the Edgeville Monastery. The monks there are level 5, hit you for 1 every few seconds, and aggro the moment you walk in. You stand in a corner, set your weapon to defensive style, and gain defence XP each time a monk lands a hit on you. It's slow. Around 15-20k XP per hour, which means 60-100 hours of monk time to reach level 75. It is also the most AFK training method in the game.

The catch: OSRS logs you out after about five minutes of no clicks, and monk aggression runs out after ten. So the loop is — walk in, get aggro'd, AFK for ten minutes, click a monk to refresh aggression before that timer runs out, click anything every five minutes so the game doesn't kick you. Miss either window and you log out, the monks stop hitting you, and your XP/hour drops to zero until you notice.

This app exists for that loop. It tells you when you're sixty seconds from being kicked, how many monks have hit you, what level you're at, and how much XP you have to go. You can read all of it from a glance at the terminal, your phone, or your wrist while the OSRS window sits behind whatever else you're doing.

## Works for any combat pure

The wire format and the pure functional core treat the currently-trained skill as data. A 1/99/1 strength pure grinding sand crabs sees the same readouts with `STRENGTH` in the header. A range tank at chinchompas sees `RANGED`. Anything where you're working a combat skill on a long AFK target and want an idle reminder, this fits.

## Status

Working end-to-end. 162 tests, 13 properties, 0 failures, suite runs in about half a second. Boots via OTP supervisor. The Plugin.Bridge and both surfaces are conditional on app config so you can run any subset.

What still needs to land before this is useful to anyone but me:

- A real RuneLite plugin that emits the wire format on a Unix socket. None of this works without the producer.
- An APNS adapter for the Watch surface (currently the outbound send is stubbed; the translation is locked).
- A Telegex (or equivalent) hookup for the Telegram surface (same — translation is done, the wire is stubbed).
- Hand-drawn ASCII frames in `Pet.Frames`. Placeholders are in.

## Reading order

| If you are                          | Read                                                                  |
|-------------------------------------|-----------------------------------------------------------------------|
| Reviewing the architecture          | [`docs/architecture.md`](docs/architecture.md)                        |
| Implementing or extending a module  | [`docs/app-structure.md`](docs/app-structure.md)                      |
| Asking "why was X decided this way" | [`docs/adr/`](docs/adr/) — ADRs                                       |
| An AI agent picking up the codebase | [`CLAUDE.md`](CLAUDE.md)                                              |

## Architecture in one diagram

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

`StateMachine`, `Pet`, `Session`, `Fidget`, `Updaters`, `Codec`, `View.*` are all pure modules. None of them need a process to test, and most are covered by property tests rather than examples. The first nine items of the build order require zero OTP. If you want to see the whole pipeline run, the end-to-end smoke test in `test/raxol/monkwatcher/e2e_test.exs` drives a fake UDS server through Bridge, App, PubSub, and the Watch surface in 50 lines.

## A note on the Pet module

The internal abstraction owes a debt to Tamagotchi. There's a `Pet` module that derives a mood (`:content`, `:sleepy`, `:hungry`, `:panicked`, `:triumphant`, `:fainted`) from session state, and an animated ASCII figure that changes accordingly. The user only sees task-relevant text: header reads `Training Defence`, right rail reads `DEFENCE 74` and `1 to 75`, state line reads `FIGHTING` or `IDLE` or `DEAD` from the FSM. The pet sits underneath all of that, picking which frame to draw.

## ADR index

| #    | Decision                                                                  |
|------|---------------------------------------------------------------------------|
| 0001 | [Adopt TEA single-model for the app core](docs/adr/0001-adopt-tea-single-model.md) |
| 0002 | [Unix Domain Socket with newline-delimited JSON for the RuneLite bridge](docs/adr/0002-uds-newline-json-bridge.md) |
| 0003 | [StateMachine as a pure module, not `gen_statem`](docs/adr/0003-pure-state-machine.md) |
| 0004 | [Phoenix.PubSub as the App-to-Surfaces seam](docs/adr/0004-pubsub-app-to-surfaces.md) |
| 0005 | [No persistence of session state across crashes or restarts](docs/adr/0005-no-persistence.md) |
| 0006 | [Conditional supervisor children for optional surfaces](docs/adr/0006-conditional-supervisor-surfaces.md) |

## Things this app will not do

- No auto-click, ever. This is the line.
- No XP/hour goal-setting, no "you'll finish at 03:42 AM" countdowns.
- No "best training spot" guidance. RuneLite already does that better.
- No persistence across sessions. Fresh start every time you log in.
- No leaderboards or social features.
- No music or sound. The OSRS client owns the audio.

If a contribution drifts toward any of these, raise the conflict with the spec before writing code.

## License

MIT. See [LICENSE](LICENSE).
