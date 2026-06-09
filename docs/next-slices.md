# Next slices — plan

Status: **proposed**. Companion to `app-structure.md` and `testing-strategy.md`. Covers Pet through view labels and notification copy.

## UX correction recorded

The spec's pet/Tamagotchi metaphor stays as **internal code scaffolding** — module names (`Pet`), struct fields (`mood`, `fullness`, `energy`), function names (`derive_target_mood/2`), mood-keyed ASCII frame sets. These are clean abstractions for "derive a visual+audio signal from game state".

What changes: every **user-facing string** must reflect the actual in-game task — a 1/1/75 defence pure kicking monks at Edgeville Monastery for defence XP. The user should never see:

- "Brother Gerald"
- "♥ 0.74" (fullness gauge with a heart)
- "⚡ 0.62" (energy gauge with lightning bolt)
- "PANICKED" / "TRIUMPHANT" mood labels
- "🍞 feed" button in Telegram
- The word "Pet" anywhere in titles, captions, or push notifications

What the user _should_ see is documented in §3 below.

## Skill-generic combat tracking (resolved)

Defence-pures at monks are one user. Other pures train at other sites — 1-att-99-str pures at gem crabs, range pures at chinning sites, etc. The model needs to be skill-agnostic from the wire up.

**Wire**: every `%Tick{}` carries the _currently-trained combat skill_ plus its XP and level, not a specific skill's data:

```json
{ "skill": "defence", "skillXp": 1210421, "skillLevel": 75, ... }
```

**Codec**: `Tick.skill` is one of seven atoms (`:attack`, `:strength`, `:defence`, `:hitpoints`, `:ranged`, `:magic`, `:prayer`), parsed via a whitelist (no `String.to_atom/1`). Unknown skills decode to `nil` rather than crashing.

**Plugin contract**: when the player switches activities (monks → crabs), the next tick reports the new skill. The app treats a skill change as the start of a new training segment for that skill.

**XP curve**: identical across all 23 OSRS skills — one `Raxol.Monkwatcher.Osrs.XpTable` module serves any of them.

**Headline**: the user-facing view shows the _current_ tick's skill name + level + XP-to-next + XP/hr derived from that skill's session-start snapshot.

Status: **shipped** (slice 0 below).

## Slice order with UX callouts

Each slice lists what changes in code AND what (if anything) the user perceives.

### Slice 0 — extend `%Tick{}` with combat-skill fields + XP table (DONE)

- **Code**: `:skill`, `:skill_xp`, `:skill_level` on `%Tick{}` with whitelist atom parsing. Generic event decode handles `"level_up"` and `"player_death"`. New `Raxol.Monkwatcher.Osrs.XpTable` module (compile-time canonical curve, `xp_for_level/1`, `level_for_xp/1`, `xp_to_next/1`).
- **Tests added**: example tests for known XP values (L1=0, L2=83, L75=1,210,421, L99=13,034,431), `level_for_xp` boundaries, `xp_to_next` at max-level edge. Properties: roundtrip (`level_for_xp(xp_for_level(n)) == n` ∀ n ∈ 1..99) and monotonic (`x1 ≤ x2 → level_for_xp(x1) ≤ level_for_xp(x2)`). Codec roundtrip property now covers all seven skills via `member_of/1` generator.
- **User-facing**: none yet — wire-format prep.

### Slice 1 — `Pet` module (internal axes)

- **Code**: `Pet.derive_target_mood/2`, `Pet.fullness/2`, `Pet.energy/1`, `Pet.tick_mood/3`, `Pet.frame/2`. `Pet.Frames` with 8 frames × 6 moods. Pure module per `app-structure.md`.
- **Tests**: invariant (`fullness ∈ [0.0, 1.0]`, `energy ∈ [0.0, 1.0]`, mood ∈ known set), metamorphic (`:dead` → `:fainted` always wins; more kicks → non-decreasing `fullness`).
- **User-facing**: none yet — `Pet` only chooses which frame to render; labels come in slice 6.

### Slice 2 — `Updaters.plugin_tick/2` + `player_death` + `snooze` + `scroll`

- **Code**: thread `%Tick{}` through `StateMachine.apply_tick/2`, `Model.put_player/2`, `Pet.derive_target_mood/2`. Add `player_death/2` (increments deaths, sets `sm.state = :dead`, mood = `:fainted`), `snooze/3` (sets `muted_until_ms`), `scroll/2` (delegates to `Fidget`).
- **Tests**: invariants on each updater (e.g., `snooze`: `model.muted_until_ms == now + ms`).
- **User-facing**: none — pure update logic.

### Slice 3 — `Channels` + `MonkNames`

- **Code**: `Channels.alerts/0` returns `"alerts"` (one constant, four call sites).
- **`MonkNames`**: keep or drop? **Recommendation: drop.** Its sole purpose was supplying `"Brother Gerald"` to the header, which is the kind of string we just ruled out. Saves a `priv/` file and a `:persistent_term` load. If session-identifier-for-logs becomes a need, generate a short hex token at boot — not a thematic name.
- **User-facing**: none.

### Slice 4 — `Notifications` + `Commands`

- **Code**: extract milestone logic from `Updaters` into `Notifications.milestone_commands/1`. Add `Notifications.idle_alert_commands/3` and `pet_event_command/2`. Add `Commands.broadcast_alert/1` returning `{:broadcast_alert, payload}`.
- **User-facing**: this is where copy starts to matter. Payload shapes that downstream surfaces will render:
  - `{:idle_alert, :warning, model}` → watch sees title `"Monks"`, body `"4:00"`, no emoji.
  - `{:idle_alert, :critical, model}` → title `"Monks"`, body `"Click!"`, no action button (HIG penalty for second tap at 4:40).
  - `{:milestone, :hits, n}` → title varies with the current activity (`"Monks"` while at the monastery, `"Crabs"` at gem crab, etc.), body `to_string(n)` (e.g. `"100"`). The hit count is the meaningful unit — XP-drops per hit are what the player is grinding.
  - `{:milestone, :level, {skill, n}}` → title is the skill name (`"Defence"`, `"Strength"`, ...), body `to_string(n)`. Fires on any `"level_up"` event regardless of skill.
  - `{:death, _}` → title matches the activity context, body `"Died."`

### Slice 5 — `View.Components` + `PetView`

- **Code**: `bar/2`, `format_mmss/1`, `format_hms/1`, `sparkline/3`, `tabs/2`. `PetView.render(model, now)`.
- **User-facing — the corrected mockup**:

```
+- Edgeville Monastery * 02:47:33 ------------------------+
|                                                        |
|                    ...,,,,,...                         |
|                   .###########.        FIGHTING        |
|                   .##(  )(  )##.       --------        |
|                   .###...v...###.      DEFENCE  74     |
|                   .###########.        +14,832 xp      |
|                    .#########.         1 to 75         |
|                                                        |
|  state: FIGHTING                last hit: 2s ago       |
|                                                        |
|  HP   ############....  67/85                          |
|  PRA  ######..........  31/82                          |
|                                                        |
|  hits * 247   /hr * 312   xp/hr * 41,200               |
|                                                        |
|  .._.._..___.._.__..._...._.._.._.._..__               |
|                                                        |
|  < kicks   stats   history   sparkline >  scroll: 47   |
+--------------------------------------------------------+
```

Changes from the spec mockup: header is the location not a pet name; right rail shows the currently-trained skill (any combat skill, not just defence) with current level + XP gained this session + XP-remaining-to-next-level; no mood captions (the ASCII art still varies internally by mood); tab bar uses task labels. State labels (`FIGHTING`, `IDLE`, `RECOVERING`, `LOGGED OUT`, `DEAD`) come straight from `StateMachine.state` — already task-appropriate.

The ASCII art slot still gets one of 6 frame sets keyed by internal mood. From the user's perspective they just see an animated figure that looks more or less alert depending on session state — no mood word printed.

### Slice 6 — Watch and Telegram surfaces

- **Code**: `Surfaces.Watch` and `Surfaces.Telegram` subscribe to `"alerts"`.
- **User-facing copy** (locked here so it can't drift):
  - Watch warning: title varies with current activity (`"Monks"` at monastery, `"Crabs"` at gem crab, etc.; falls back to capitalized skill name if no location is known), body `"4:00"`, priority `:normal`, actions `[%{id: "snooze", label: "+60s"}]`
  - Watch critical: same title pattern, body `"Click!"`, priority `:high`, no actions
  - Watch hit milestone: same title pattern, body `to_string(n)` at every 100th hit
  - Watch level-up: title is the skill name (capitalized: `"Defence"`, `"Strength"`, ...), body `to_string(level)`. Fires on any `"level_up"` event.
  - Watch death: same title pattern, body `"Died."`, priority `:high`
  - Telegram pinned: `"<idle_mmss> * <hits> hits * <level> <skill> * <hp>/<max_hp>"` — e.g. `"4:12 * 247 hits * 74 def * 67/85"` (ASCII separator; no heart/lightning gauges)
  - Telegram inline keyboard: `[+60s]` snooze button only.

## What this changes in earlier docs

Three pre-existing docs make claims that the corrected UX overrides. Logging here so future-me sees the conflict:

- `raxol_monkwatcher.md` "The notification copy" — `"Monk"` title is fine. Spec said `+1 Def` for level-ups; we'll use `"75"` as the body with title `"Defence"`. Spec used 🧘 emoji in Telegram; we'll keep neutral ASCII.
- `raxol_monkwatcher.md` "The fidget surface" mockup — superseded by the mockup in slice 5.
- `app-structure.md` `MonkNames` module — recommended dropped (see slice 3).
- `app-structure.md` `Model.new(now, name)` — `name` arg becomes unused; can stay as positional for now and be removed when `Model` is revisited, or drop the second arg in a small refactor.
- `app-structure.md` mood-label rendering (`format_mood/1`) — keep the function for internal logging/debug but don't render the result to the terminal.

## Recommended execution order

The slice numbering is also the recommended order. Specifically:

1. Slice 0 (Tick extension) — small, removes a wire-format gap before we lean on tick data.
2. Slice 1 (Pet) — pure logic, property tests, no UX surface.
3. Slice 2 (remaining Updaters) — pure, completes the model-update layer.
4. Slice 3 (Channels) — trivial, two-line file.
5. Slice 4 (Notifications + Commands) — first place user-facing copy is encoded.
6. Slice 5 (View + Components) — terminal user-facing renders. Highest UX risk; review the mockup before implementing.
7. Slice 6 (Surfaces) — wires PubSub to external systems. Last because it needs `Phoenix.PubSub` and the surface deps (`telegex`, `raxol_watch`).

Slices 0-4 are still buildable with zero OTP processes. Slice 6 introduces the first GenServers (`Surfaces.*`) and `Phoenix.PubSub` as a runtime dep.
