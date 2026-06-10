# App structure — module contracts as built

Status: **implemented**. Originally drafted as a pre-implementation extraction plan; preserved here as the contract reference for the modules that landed. The original spec (`raxol_monkwatcher.md`) is deleted — this is now the authoritative description of the responsibility split.

## Goal (achieved)

`App` is a **thin GenServer shell**: `init/1`, `handle_cast({:dispatch, msg}, state)`, `handle_call(:view, _, state)`, `dispatch/1`. The only impure thing App does is read the wall clock (`now_fn.()`) per `:dispatch` / `:view` call and pass it to a pure updater. Everything below it is unit-testable without a process.

## Where each responsibility lives

The original App carried ten distinct responsibilities. They are split as follows in the shipped code:

1. **Model schema** — `Raxol.Monkwatcher.Model` struct
2. **Initial state construction** — `Model.new(now)` (pet naming was dropped from scope; see ADR-0005)
3. **Dispatch routing** — `App.handle_cast({:dispatch, msg}, state)` routes by struct/tuple shape to one `App.Updaters.*` function
4. **StateMachine threading** — `App.Updaters.plugin_tick/2` calls `StateMachine.apply_tick` + `check_thresholds`
5. **Player slice updates** — `Model.put_player/2` copies fields from a typed `%Tick{}`
6. **Session updates** — `Session.record_kill/3`, `Session.record_death/1`; hit history capped at 50 by `Session.@kill_history_cap`
7. **Pet mood derivation** — `App.Updaters.advance_pet/2` calls `Pet.derive_target_mood/2` + `Pet.tick_mood/3`
8. **Scroll input handling** — `Fidget.scroll/2` owns the ±30 cycle threshold and the view cycle order
9. **Notification command construction** — `Notifications.idle_alert_commands/3`, `milestone_commands/3`, `death_command/2`, `level_up_command/2`; envelopes built by `Commands.broadcast_alert/1`; muting check (`muted_until_ms`) lives inside `Notifications`
10. **View dispatch** — `View.render(model, now)`

## Responsibility → module map

| Responsibility                      | Module                                  | Kind        |
|-------------------------------------|-----------------------------------------|-------------|
| 1. Model schema                     | `Raxol.Monkwatcher.Model`               | pure data   |
| 2. Initial state                    | `Model.new/1`                           | pure        |
| 3. Dispatch routing                 | `Raxol.Monkwatcher.App.Updaters`        | pure        |
| 4. StateMachine threading           | `App.Updaters.plugin_tick/2` (uses `StateMachine`) | pure |
| 5. Player slice updates             | `Model.put_player/2`                    | pure        |
| 6. Session math                     | `Raxol.Monkwatcher.Session`             | pure        |
| 7. Pet mood derivation              | `Raxol.Monkwatcher.Pet`                 | pure        |
| 7b. Mood transition smoothing       | `Pet.tick_mood/3`                       | pure        |
| 8. Scroll + view cycling            | `Raxol.Monkwatcher.Fidget`              | pure        |
| 9a. Notification commands           | `Raxol.Monkwatcher.Notifications`       | pure        |
| 9b. PubSub command builder          | `Raxol.Monkwatcher.Commands`            | pure        |
| 9c. Topic name                      | `Raxol.Monkwatcher.Channels`            | pure        |
| 10. View dispatch                   | `Raxol.Monkwatcher.View` (with `now`)   | pure        |
| Plugin wire decoding                | `Raxol.Monkwatcher.Plugin.Codec`        | pure        |
| Surface title derivation            | `Raxol.Monkwatcher.Activity`            | pure        |

`Channels` and `Plugin.Codec` also addressed R9 and isolated the JSON-shape contract respectively. The ADR-0002 protocol-version field was deferred.

## Proposed file tree

```
lib/raxol/monkwatcher/
├── application.ex                  # OTP app, supervisor, conditional surfaces
├── activity.ex                     # region-or-skill title for surfaces
├── channels.ex                     # alerts/0 — topic constant
├── model.ex                        # Model struct + put_player/2
├── state_machine.ex                # pure FSM
├── session.ex                      # session slice + hit recording
├── fidget.ex                       # scroll + view cycling
├── pet.ex                          # mood derivation + fullness/energy + smoothing
├── pet/
│   └── frames.ex                   # ASCII art data (placeholder frames)
├── notifications.ex                # idle_alert / milestone / death / level_up commands; muting
├── commands.ex                     # broadcast_alert/1 envelope
├── plugin/
│   ├── bridge.ex                   # GenServer, UDS connect/reconnect
│   └── codec.ex                    # decode line → %Tick{} | %Event{}
├── app.ex                          # GenServer shell
├── app/
│   └── updaters.ex                 # per-message pure updaters
├── osrs/
│   └── xp_table.ex                 # XP lookup helpers
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

Renames during implementation: `PluginBridge` -> `Plugin.Bridge`, single `View` module -> `View` + `View.Components` + subviews.

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
  def plugin_tick(model, %Tick{} = tick)
  def monk_killed(model, data, now)
  def player_death(model, now)
  def scroll(model, delta)
  def snooze(model, ms, now)
end
```

Level-up events are routed in `App` itself (a single `Notifications.level_up_command/2` call), not through Updaters — the event carries no model mutation.

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

### `Raxol.Monkwatcher.Plugin.Codec`

```elixir
defmodule Raxol.Monkwatcher.Plugin.Codec do
  @supported_version 1

  defmodule Tick do
    @enforce_keys [:t, :tick]
    defstruct [:t, :tick, :is_monk, :anim, :hp, :max_hp,
               :prayer, :max_prayer, :run_energy, :x, :y, :plane,
               :skill, :skill_xp, :skill_level]
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

## The slim App

```elixir
defmodule Raxol.Monkwatcher.App do
  use GenServer

  alias Raxol.Monkwatcher.{Channels, Model, Notifications, View}
  alias Raxol.Monkwatcher.App.Updaters
  alias Raxol.Monkwatcher.Plugin.Codec.{Event, Tick}

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def dispatch(msg, name \\ __MODULE__), do: GenServer.cast(name, {:dispatch, msg})
  def view(name \\ __MODULE__), do: GenServer.call(name, :view)

  @impl true
  def init(opts) do
    now_fn = Keyword.get(opts, :now_fn, &default_now/0)
    pubsub = Keyword.get(opts, :pubsub, Raxol.Monkwatcher.PubSub)
    {:ok, %{model: Model.new(now_fn.()), pubsub: pubsub, now_fn: now_fn}}
  end

  @impl true
  def handle_cast({:dispatch, msg}, state) do
    {new_model, commands} = apply_update(msg, state)
    Enum.each(commands, &execute(&1, state.pubsub))
    {:noreply, %{state | model: new_model}}
  end

  @impl true
  def handle_call(:view, _from, state),
    do: {:reply, View.render(state.model, state.now_fn.()), state}

  defp apply_update(%Tick{} = tick, state), do: Updaters.plugin_tick(state.model, tick)
  defp apply_update(%Event{type: "monk_killed", data: d, t: t}, state),
    do: Updaters.monk_killed(state.model, d, t)
  defp apply_update(%Event{type: "player_death", t: t}, state),
    do: Updaters.player_death(state.model, t)
  defp apply_update(%Event{type: "level_up", data: %{"skill" => s, "level" => l}}, state),
    do: {state.model, [Notifications.level_up_command(parse_skill(s), l)]}
  defp apply_update({:scroll, delta}, state), do: Updaters.scroll(state.model, delta)
  defp apply_update({:snooze, ms}, state), do: Updaters.snooze(state.model, ms, state.now_fn.())
  defp apply_update(_, state), do: {state.model, []}

  defp execute({:broadcast_alert, payload}, pubsub),
    do: Phoenix.PubSub.broadcast(pubsub, Channels.alerts(), payload)
  defp execute(_, _), do: :ok

  defp default_now, do: System.system_time(:millisecond)
end
```

(Skill-atom whitelist and `level_up` parsing elided — see `lib/raxol/monkwatcher/app.ex` for the full source.) The body holds no domain logic: routing by struct/tuple shape, then delegate. Anything that needs testing lives in a module App calls.

The three injection points (`:now_fn`, `:pubsub`, `:name`) are what makes the GenServer testable without monkey-patching: tests pass a fixed-clock function and a private PubSub server, then assert on broadcasts with `Phoenix.PubSub.subscribe` + `assert_receive`.

## What stays in App (and why)

- **The `update/2` dispatch table.** This is the TEA contract; the cost of moving it elsewhere is more indirection than it's worth.
- **The `now/0` helper.** A single read per update, threaded into every updater. Centralizing it here means time discipline is enforced by the type signature, not by convention.
- **`dispatch/1`.** Public API for external callers (`Plugin.Bridge`, watch tap-back, Telegram callback queries). It belongs on the named process.

## Deviations from the original spec

| Spec name                                            | Shipped name                                   | Why                                                                                 |
|------------------------------------------------------|------------------------------------------------|-------------------------------------------------------------------------------------|
| `Raxol.Monkwatcher.PluginBridge`                     | `Raxol.Monkwatcher.Plugin.Bridge`              | Makes room for `Plugin.Codec` as a sibling; matches the file layout.                |
| Single `View` module                                 | `View` + `View.Components`                     | Shared widgets (bars, sparkline, formatters) used across all subviews.              |
| `Pet.derive_mood/2`                                  | `Pet.derive_target_mood/2` + `Pet.tick_mood/3` | The spec promised mood smoothing in prose; this is the API that delivers it.        |
| Random pet name on `App.init/1`                      | Dropped                                        | Pet naming was cut from scope (ADR-0005). `Model.new/1` takes only `now`.           |
| Wire decode in `PluginBridge.handle_manager_info/2`  | `Plugin.Codec.decode/1`                        | Isolates the schema from the connection loop.                                       |
| Raxol TEA runtime (`use Raxol.Core.Runtime.Application`) | Plain `GenServer`                          | `raxol` was never added as a dependency; routing-by-shape inside `handle_cast` covers it. |

## Build order, as it happened

The implementation followed this dependency order. Recorded for posterity; future module additions should slot in at the appropriate layer.

1. **`Channels`** — topic constant, no dependencies.
2. **`StateMachine`** — pure FSM, property-tested first.
3. **`Session`, `Fidget`, `Model`** — pure data layer, no dependencies on App.
4. **`Pet` + `Pet.Frames`** — depends on `StateMachine` for idle time; pure.
5. **`Plugin.Codec`** — pure; tested against synthesized fixtures (no real plugin recordings yet).
6. **`Commands`, `Notifications`** — depends on `Channels`, `Model`. Still pure.
7. **`App.Updaters`** — composes everything above. Property tests on model invariants.
8. **`View.Components`, subviews, `View`** — depends on `Model`, `Pet`, `Session`. Pure render with `(model, now)`.
9. **`Activity`** — pure title derivation for surfaces.
10. **`App`** — the GenServer shell. Trivial once `Updaters` exists.
11. **`Plugin.Bridge`** — connects `Plugin.Codec` to `App.dispatch/1`. GenServer with injected `dispatch_fn` for tests.
12. **`Application`** — wires the supervisor, conditionally adds Plugin.Bridge and surfaces.
13. **`Surfaces.Watch`, `Surfaces.Telegram`** — subscribers with pure formatting contracts and injected `send_fn`.

Items 1-9 are fully property-tested without starting a process. That was the win.

## Pattern conformance notes

Cross-checked against the droo-stack `elixir-patterns` and `elixir-testing` rules:

- **Function dispatch by shape**, not body-level `if`/`cond`. `App.update/2`, `Updaters.*`, and `Plugin.Codec.decode/1` use multi-clause function heads that pattern-match on the inbound message or struct. Body-level conditionals are reserved for cases where the discriminator is a computed value (e.g. `Pet.derive_target_mood/2` matches on idle time and fullness ratio — `cond` is correct there).
- **Typed structs at module boundaries.** `%Plugin.Codec.Tick{}` and `%Plugin.Codec.Event{}` are the only types domain modules see. The string-keyed JSON map dies inside `Codec.decode/1`. Renaming a wire field becomes a one-line Codec change.
- **`with` chains** in `Plugin.Bridge.handle_info/2` (decode -> dispatch) and any future Telegram callback handler with multiple validation steps. Reserved for genuine multi-step failure flows, not for happy-path data transformation (pipes do that).
- **Pure data pipelines.** `Updaters.*` functions flow `model |> Module.f(...) |> Module.g(...)` for state transformations; effects (PubSub broadcast) are returned as commands the runtime executes, never inlined in pipes.
- **No mocks.** Pure modules (`StateMachine`, `Pet`, `Session`, `Fidget`, `Notifications`, `Plugin.Codec`, `View.*`) are tested as pure functions with `StreamData` properties and concrete examples. `Surfaces.Telegram` and `Surfaces.Watch` are tested with real `Phoenix.PubSub` + `assert_receive` (the surface registers itself; the test broadcasts on `"alerts"` and asserts the outbound side effect via a stub HTTP layer or by inspecting the surface's GenServer state).
- **Test organization.** One test file per production module. `describe "function/arity"` blocks per public function. Test names describe behavior, not implementation: `test "returns :warning fires only after 4 minutes of continuous idle"`, not `test "check_thresholds_idle_240s"`.
- **`async: true`** on every test module touching only pure modules; `async: false` for surface tests that share the PubSub namespace.
