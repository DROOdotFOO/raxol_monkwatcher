# App structure — extraction plan

Status: **proposed**, pre-implementation. Companion to `architecture.md` §4 R1 ("App is a god-module candidate"). This doc converts that finding into concrete module boundaries before code lands.

## Goal

`App` should be a **thin TEA shell**: `init/1`, `update/2`, `view/2`, `dispatch/1`. Nothing else. Every other concern — model shape, session math, mood derivation, scroll cycling, command building, name picking, notification gating, view rendering — lives in a sibling module that takes pure inputs and returns pure outputs.

When this is done, the only impure thing App does is read the wall clock once per update/view and call the (pure) updater. Everything below it is unit-testable without a process.

## What the spec's App currently owns

Reading `raxol_monkwatcher.md` §"File: app.ex" carefully, App carries ~10 distinct responsibilities:

1. **Model schema** — the giant nested map in `init/1`
2. **Initial state construction** — including reading `priv/monk_names.txt` from disk
3. **Dispatch routing** — 7 `update/2` branches (`:plugin_tick`, 3× `:game_event`, `:scroll`, `:feed`, `:snooze`)
4. **StateMachine threading** — `apply_tick`, `check_thresholds`, transition on events
5. **Player slice updates** — copying tick payload fields into `model.player`
6. **Session updates** — kill count, kill history (with 50-cap), death count, level history
7. **Pet mood derivation** — calling `Pet.derive_mood/2` after every relevant update
8. **Scroll input handling** — accumulating `scroll_position`, threshold-cycling view mode, the `next_view/2` 8-clause helper
9. **Notification command construction** — building `{:async, fn -> broadcast end}` tuples, milestone detection (`rem(kills, 100) == 0`), muting check (`muted_until_ms`)
10. **View dispatch** — calls `View.render(model)`

This is a god-module trajectory. The fix is mechanical: each numbered item maps to a named module with a tight API.

## Responsibility → module map

| Responsibility (above)              | New module                              | Kind        |
|-------------------------------------|-----------------------------------------|-------------|
| 1. Model schema                     | `Raxol.Monkwatcher.Model`               | pure data   |
| 2a. Initial state                   | `Model.new/2`                           | pure        |
| 2b. Pet name pool                   | `Raxol.Monkwatcher.MonkNames`           | boot-loaded |
| 3. Dispatch routing                 | `Raxol.Monkwatcher.App.Updaters`        | pure        |
| 4. StateMachine threading           | `App.Updaters.plugin_tick/2` (uses `StateMachine`) | pure |
| 5. Player slice updates             | `Model.put_player/2`                    | pure        |
| 6. Session math                     | `Raxol.Monkwatcher.Session`             | pure        |
| 7. Pet mood derivation              | `Raxol.Monkwatcher.Pet` (already pure)  | pure        |
| 7b. Mood transition smoothing       | `Pet.tick_mood/3`                       | pure (new)  |
| 8. Scroll + view cycling            | `Raxol.Monkwatcher.Fidget`              | pure        |
| 9a. Notification commands           | `Raxol.Monkwatcher.Notifications`       | pure        |
| 9b. PubSub command builder          | `Raxol.Monkwatcher.Commands`            | pure        |
| 9c. Topic name                      | `Raxol.Monkwatcher.Channels`            | pure        |
| 10. View dispatch                   | `Raxol.Monkwatcher.View` (with `now`)   | pure        |
| Plugin wire decoding                | `Raxol.Monkwatcher.Plugin.Codec`        | pure        |

Three of these (`Channels`, `MonkNames`, `Plugin.Codec`) also address R3, R9, and the ADR-0002 version-field gap.

## Proposed file tree

```
lib/raxol/monkwatcher/
├── application.ex                  # OTP app, supervisor, boots MonkNames
├── channels.ex                     # alerts/0 — topic constant
├── monk_names.ex                   # load!/0, random/0 — persistent_term backed
├── model.ex                        # Model struct + slice helpers
├── state_machine.ex                # pure FSM (per spec)
├── session.ex                      # session slice + derived stats
├── fidget.ex                       # scroll + view cycling
├── pet.ex                          # mood derivation + fullness/energy + smoothing
├── pet/
│   └── frames.ex                   # ASCII art data (8 frames × 6 moods)
├── notifications.ex                # commands_for/2, milestones, muting check
├── commands.ex                     # broadcast command builders
├── plugin/
│   ├── bridge.ex                   # GenServer, UDS connect/reconnect
│   └── codec.ex                    # decode line → typed message
├── app.ex                          # TEA shell only
├── app/
│   └── updaters.ex                 # per-message pure updaters
├── view.ex                         # render dispatcher (model, now)
├── view/
│   ├── components.ex               # bar, sparkline, formatters, tabs
│   ├── pet_view.ex
│   ├── history_view.ex
│   ├── stats_view.ex
│   └── sparkline_view.ex
└── surfaces/
    ├── telegram.ex
    └── watch.ex
```

Renames from spec: `PluginBridge` -> `Plugin.Bridge`, `View` (was a single module) -> `View` + `View.Components` + subviews. Everything else keeps spec names.

## Module contracts

### `Raxol.Monkwatcher.Model`

```elixir
defmodule Raxol.Monkwatcher.Model do
  alias Raxol.Monkwatcher.{StateMachine, Session, Fidget}
  alias Raxol.Monkwatcher.Plugin.Codec.Tick

  defstruct [
    :sm,             # %StateMachine{}
    :session,        # %Session{}
    :player,         # %{hp, max_hp, prayer, max_prayer, run_energy, location}
    :pet,            # %{name, mood, target_mood, transition_remaining}
    :fidget,         # %Fidget{}
    :muted_until_ms  # integer
  ]

  @spec new(integer, String.t()) :: t
  def new(now, name) when is_integer(now) and is_binary(name)

  @spec put_player(t, Tick.t()) :: t
  def put_player(model, %Tick{} = tick)

  @spec set_mood(t, atom) :: t
  def set_mood(model, mood)

  @spec mute_until(t, integer) :: t
  def mute_until(model, ms)
end
```

`put_player/2` pattern-matches on the typed `%Tick{}` struct from `Plugin.Codec` rather than a stringly-keyed JSON map. The wire format stays at the boundary.

### `Raxol.Monkwatcher.Session`

```elixir
defmodule Raxol.Monkwatcher.Session do
  @kill_history_cap 50

  defstruct [:started_at, monks_killed: 0, kill_history: [], deaths: 0, levels_gained: []]

  def new(now)
  def record_kill(session, now, data)
  def record_death(session)
  def record_level(session, skill, level, now)
  def kills_per_hour(session, now)
  def last_kill_age_ms(session, now)            # nil if no kills
  def just_leveled?(session, now, window_ms \\ 5_000)
end
```

### `Raxol.Monkwatcher.Fidget`

```elixir
defmodule Raxol.Monkwatcher.Fidget do
  @cycle_threshold 30
  @views [:pet, :history, :stats, :sparkline]

  defstruct scroll_position: 0, view_mode: :pet

  # Returns updated fidget; cycles view + resets scroll past ±threshold.
  def scroll(fidget, delta)

  def cycle_view(fidget, :forward | :backward)
end
```

`Fidget` owns the view cycle order and threshold — App no longer cares.

### `Raxol.Monkwatcher.Pet`

Per spec, plus the transition smoothing the spec describes in prose but doesn't implement (architecture.md R5):

```elixir
defmodule Raxol.Monkwatcher.Pet do
  @transition_ticks 8

  def derive_target_mood(model, now)             # the cond chain
  def tick_mood(pet, target, now)                # advances toward target; returns new pet
  def fullness(model, now)
  def energy(model)
  def frame(mood, scroll_pos)                    # delegates to Pet.Frames
end
```

Mood ordering (`:fainted` > `:panicked` > `:sleepy` > `:triumphant` > `:hungry` > `:content`) is enforced by an ExUnit test against `derive_target_mood/2`.

### `Raxol.Monkwatcher.App.Updaters`

The heart of the extraction. Every branch of `update/2` is a pure function here:

```elixir
defmodule Raxol.Monkwatcher.App.Updaters do
  # All return {model, [command]}
  def plugin_tick(model, payload)
  def monk_killed(model, data, now)
  def player_death(model, now)
  def game_event(model, type, data, now)          # generic — sm.apply_event/4
  def scroll(model, delta)
  def feed(model, now)
  def snooze(model, ms, now)
end
```

Each function:
1. Calls the appropriate pure module (`StateMachine`, `Session`, `Fidget`, `Pet`)
2. Asks `Notifications` for any commands to emit
3. Returns `{new_model, commands}`

Property tests verify the model invariants per updater (e.g. "after `monk_killed`, `monks_killed` increased by exactly 1 and `kill_history` head is the new entry").

### `Raxol.Monkwatcher.Notifications`

```elixir
defmodule Raxol.Monkwatcher.Notifications do
  alias Raxol.Monkwatcher.Commands

  # Threshold fires from StateMachine.check_thresholds/2.
  def idle_alert_commands(fires, model, now)
  def milestone_commands(kill_count)
  def pet_event_command(event, model)            # e.g. :fainted, :triumphant

  # private: muted?(model, now)
end
```

Muting is enforced here, not in App. App doesn't know about thresholds or milestones — it just merges the command list.

### `Raxol.Monkwatcher.Commands`

```elixir
defmodule Raxol.Monkwatcher.Commands do
  alias Raxol.Monkwatcher.Channels

  # Returns a {:async, fn -> ... end} tuple Raxol's runtime executes.
  def broadcast_alert(payload)
end
```

Wrapping `Phoenix.PubSub.broadcast` here means tests can match on `{:broadcast_alert, payload}` shapes instead of executing the function.

### `Raxol.Monkwatcher.Channels`

```elixir
defmodule Raxol.Monkwatcher.Channels do
  def alerts, do: "alerts"
end
```

One file, two lines, removes a class of typo bugs across `App`, `Commands`, `Surfaces.Telegram`, `Surfaces.Watch`.

### `Raxol.Monkwatcher.MonkNames`

```elixir
defmodule Raxol.Monkwatcher.MonkNames do
  @persistent_key {__MODULE__, :names}

  def load! do
    path = Application.app_dir(:raxol_monkwatcher, "priv/monk_names.txt")
    names = path |> File.read!() |> String.split("\n", trim: true)
    :persistent_term.put(@persistent_key, names)
  end

  def random do
    @persistent_key |> :persistent_term.get() |> Enum.random()
  end
end
```

Called from `Application.start/2` before children start. Fixes R3 and works under `mix release`.

### `Raxol.Monkwatcher.Plugin.Codec`

```elixir
defmodule Raxol.Monkwatcher.Plugin.Codec do
  @supported_version 1

  defmodule Tick do
    @enforce_keys [:t, :tick]
    defstruct [:t, :tick, :is_monk, :anim, :hp, :max_hp,
               :prayer, :max_prayer, :run_energy, :x, :y, :plane]
    @type t :: %__MODULE__{...}
  end

  defmodule Event do
    @enforce_keys [:type, :data, :t]
    defstruct [:type, :data, :t]
    @type t :: %__MODULE__{type: String.t(), data: map, t: integer}
  end

  @spec decode(String.t()) ::
          {:ok, Tick.t() | Event.t()}
          | {:error, {:bad_json, term} | {:unsupported_version, term}}
  def decode(line)
end
```

Codec is the only place that touches stringly-keyed JSON. Every downstream module (`StateMachine.apply_tick/2`, `Model.put_player/2`, `Updaters.*`) takes `%Tick{}` or `%Event{}` and pattern-matches on the struct in its function head. This means renaming `isMonk` -> `is_combat` in the wire format is a one-line change in Codec, not a sweep across every consumer.

`Plugin.Bridge` decodes and dispatches via the injected `dispatch_fn` (see below), using a `with` chain for the failure path:

```elixir
with {:ok, msg} <- Codec.decode(line) do
  state.dispatch_fn.(msg)
else
  {:error, reason} -> Logger.warning("Plugin.Bridge bad line: #{inspect(reason)}")
end
```

### `Raxol.Monkwatcher.Plugin.Bridge`

```elixir
defmodule Raxol.Monkwatcher.Plugin.Bridge do
  defstruct [:socket_path, :socket, :backoff_ms, :dispatch_fn]

  # Required: socket_path
  # Optional: dispatch_fn (default: &Raxol.Monkwatcher.App.dispatch/1)
  #           name        (default: __MODULE__)
  def start_link(opts)
end
```

`dispatch_fn` injection is the only nontrivial DI in the system. It lets `Plugin.Bridge` integration tests run against a real UDS socket and the real `Plugin.Codec` without starting `App` — tests pass `dispatch_fn: fn msg -> send(test_pid, msg) end` and `assert_receive` the decoded `%Tick{}` or `%Event{}`. See `testing-strategy.md` §5.

A test-only `to_wire_map/1` helper inverts the production decode for the `Codec` roundtrip property — kept in `test/support/`, never linked into release.

### `Raxol.Monkwatcher.View` + `View.Components`

```elixir
defmodule Raxol.Monkwatcher.View do
  def render(model, now)                          # dispatch by model.fidget.view_mode
end

defmodule Raxol.Monkwatcher.View.Components do
  def bar(ratio, width)
  def sparkline(history, now, opts \\ [])
  def format_mmss(ms)
  def format_hms(ms)
  def tabs(current_view, scroll_position)
end
```

Subviews (`PetView`, `HistoryView`, `StatsView`, `SparklineView`) take `(model, now)` and return view trees. They import `Components` for shared widgets. No `System.system_time` calls inside views (fixes R2).

## The slim App, after extraction

```elixir
defmodule Raxol.Monkwatcher.App do
  use Raxol.Core.Runtime.Application

  alias Raxol.Monkwatcher.{Model, MonkNames, View}
  alias Raxol.Monkwatcher.App.Updaters

  @impl true
  def init(_ctx) do
    Model.new(now(), MonkNames.random())
  end

  @impl true
  def update({:plugin_tick, payload}, model),
    do: Updaters.plugin_tick(model, payload)

  def update({:game_event, "monk_killed", data}, model),
    do: Updaters.monk_killed(model, data, now())

  def update({:game_event, "player_death", _}, model),
    do: Updaters.player_death(model, now())

  def update({:game_event, type, data}, model),
    do: Updaters.game_event(model, type, data, now())

  def update({:scroll, delta}, model),
    do: Updaters.scroll(model, delta)

  def update({:feed}, model),
    do: Updaters.feed(model, now())

  def update({:snooze, ms}, model),
    do: Updaters.snooze(model, ms, now())

  def update(_msg, model), do: {model, []}

  @impl true
  def view(model), do: View.render(model, now())

  def dispatch(msg), do: GenServer.cast(__MODULE__, {:dispatch, msg})

  defp now, do: System.system_time(:millisecond)
end
```

Forty lines, no logic, no constants, no `priv/` reads, no command construction. Anything that needs testing lives in a module App calls.

## What stays in App (and why)

- **The `update/2` dispatch table.** This is the TEA contract; the cost of moving it elsewhere is more indirection than it's worth.
- **The `now/0` helper.** A single read per update, threaded into every updater. Centralizing it here means time discipline is enforced by the type signature, not by convention.
- **`dispatch/1`.** Public API for external callers (`Plugin.Bridge`, watch tap-back, Telegram callback queries). It belongs on the named process.

## Deviations from the spec

| Spec name                      | New name                          | Why                                                                  |
|--------------------------------|-----------------------------------|----------------------------------------------------------------------|
| `Raxol.Monkwatcher.PluginBridge` | `Raxol.Monkwatcher.Plugin.Bridge` | Makes room for `Plugin.Codec` as a sibling; matches the file layout. |
| Single `View` module           | `View` + `View.Components`        | Shared widgets (bars, sparkline, formatters) used across all subviews. |
| `Pet.derive_mood/2`            | `Pet.derive_target_mood/2` + `Pet.tick_mood/3` | The spec promises mood smoothing in prose; this is the API that delivers it. |
| Pet name read in `App.init/1`  | `MonkNames.load!` at boot, `MonkNames.random/0` in init | Survives `mix release`; one disk read per process lifetime. |
| Wire decode in `PluginBridge.handle_manager_info/2` | `Plugin.Codec.decode/1` | Isolates the schema + version check from the connection loop. |

## Recommended extraction order

The dependencies between modules dictate the build order. None of this changes the spec's recommended product build order (RuneLite plugin -> bridge -> StateMachine -> Pet -> App -> Watch -> scroll -> Telegram); it refines the *implementation order within each step*.

1. **`Channels`, `MonkNames`** — trivial, prerequisites for boot.
2. **`StateMachine`** — already in the spec, pure, property-tested first.
3. **`Session`, `Fidget`, `Model`** — pure data layer, no dependencies on App.
4. **`Pet` + `Pet.Frames`** — depends on `StateMachine` for idle time; pure.
5. **`Plugin.Codec`** — pure; can be tested against recorded fixtures before `Plugin.Bridge` exists.
6. **`Commands`, `Notifications`** — depends on `Channels`, `Model`. Still pure.
7. **`App.Updaters`** — composes everything above. Property tests on model invariants.
8. **`View.Components`, subviews, `View`** — depends on `Model`, `Pet`, `Session`. Pure render.
9. **`App`** — the TEA shell. Trivial once `Updaters` exists.
10. **`Plugin.Bridge`** — connects `Plugin.Codec` to `App.dispatch/1`. GenServer.
11. **`Application`** — wires the supervisor, boots `MonkNames`, conditionally adds surfaces.
12. **`Surfaces.Watch`, `Surfaces.Telegram`** — subscribers; can be developed in either order, last.

The first nine items can be built and fully property-tested without ever starting a process. That's the win.

## Pattern conformance notes

Cross-checked against the droo-stack `elixir-patterns` and `elixir-testing` rules:

- **Function dispatch by shape**, not body-level `if`/`cond`. `App.update/2`, `Updaters.*`, and `Plugin.Codec.decode/1` use multi-clause function heads that pattern-match on the inbound message or struct. Body-level conditionals are reserved for cases where the discriminator is a computed value (e.g. `Pet.derive_target_mood/2` matches on idle time and fullness ratio — `cond` is correct there).
- **Typed structs at module boundaries.** `%Plugin.Codec.Tick{}` and `%Plugin.Codec.Event{}` are the only types domain modules see. The string-keyed JSON map dies inside `Codec.decode/1`. Renaming a wire field becomes a one-line Codec change.
- **`with` chains** in `Plugin.Bridge.handle_info/2` (decode -> dispatch) and any future Telegram callback handler with multiple validation steps. Reserved for genuine multi-step failure flows, not for happy-path data transformation (pipes do that).
- **Pure data pipelines.** `Updaters.*` functions flow `model |> Module.f(...) |> Module.g(...)` for state transformations; effects (PubSub broadcast) are returned as commands the runtime executes, never inlined in pipes.
- **No mocks.** Pure modules (`StateMachine`, `Pet`, `Session`, `Fidget`, `Notifications`, `Plugin.Codec`, `View.*`) are tested as pure functions with `StreamData` properties and concrete examples. `Surfaces.Telegram` and `Surfaces.Watch` are tested with real `Phoenix.PubSub` + `assert_receive` (the surface registers itself; the test broadcasts on `"alerts"` and asserts the outbound side effect via a stub HTTP layer or by inspecting the surface's GenServer state).
- **Test organization.** One test file per production module. `describe "function/arity"` blocks per public function. Test names describe behavior, not implementation: `test "returns :warning fires only after 4 minutes of continuous idle"`, not `test "check_thresholds_idle_240s"`.
- **`async: true`** on every test module touching only pure modules; `async: false` for surface tests that share the PubSub namespace.
