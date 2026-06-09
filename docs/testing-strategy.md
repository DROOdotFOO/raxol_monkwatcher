# Testing strategy

Status: **proposed**, pre-implementation. Companion to `architecture.md` and `app-structure.md`. Applies the `tdd` and `property-testing` skills to this codebase's specific shape.

The two docs already say "no mocks" and "property tests for `StateMachine`". This doc makes that concrete: which property type per module, what the tracer bullet is, where dependency injection is needed for testability, and how the system-boundary stubs are built.

## 1. TDD workflow mapped to this project

| Phase                | What it means here                                                                    |
|----------------------|----------------------------------------------------------------------------------------|
| 1. Planning          | `architecture.md` + `app-structure.md` define interfaces. Done — no more design before code.|
| 2. Tracer bullet     | One end-to-end test that proves the test infrastructure works. See §2 below.          |
| 3. Incremental loop  | One example test per behavior, RED -> GREEN, one at a time. Never batch.              |
| 3.5. Property tests  | Add properties (§4) once the per-module example tests are green.                       |
| 4. Refactor          | Only while green. The extractions in `app-structure.md` are post-tracer-bullet refactors. |

**Critical rule from the TDD skill**: write all the example tests first is waterfall in TDD's clothing. The extraction plan in `app-structure.md` lists 12 modules in build order — that order is correct, but within each module the discipline is one test -> implement -> next test, not "write every test for Session, then implement Session".

## 2. The tracer bullet

The smallest behavior that proves the pure stack interlocks:

```elixir
defmodule Raxol.Monkwatcher.TracerTest do
  use ExUnit.Case, async: true

  alias Raxol.Monkwatcher.{Model, App.Updaters}

  test "monk_killed increments session.monks_killed and emits no command" do
    model = Model.new(1_000_000, "Brother Test")
    {model_after, commands} = Updaters.monk_killed(model, %{}, 1_000_001)

    assert model_after.session.monks_killed == 1
    assert commands == []
  end
end
```

This is two lines of production code (`Model.new/2`, `Updaters.monk_killed/3`) calling into `Session.record_kill/3` and `Pet.derive_target_mood/2`. Six minutes of work, but it proves:

- `Model.new/2` returns a valid struct
- The session slice is reachable and mutable through `Updaters`
- The Updater returns the `{model, commands}` tuple shape the rest of the system depends on
- The dispatch path from message -> updater -> model interlocks

**Order**: write this test FIRST. It will be RED because none of those modules exist. Implement them — minimal stubs, just enough to go GREEN. Then begin the incremental loop.

## 3. Property catalog — by module and by type

The `property-testing` skill defines five property types. Here's the mapping for our modules:

### `Plugin.Codec` — roundtrip

The classic case. Wire bytes must survive a parse:

```elixir
property "Codec.decode is the inverse of encoding" do
  check all tick <- tick_generator() do
    wire = Jason.encode!(to_wire_map(tick))
    assert {:ok, ^tick} = Codec.decode(wire <> "\n")
  end
end
```

`to_wire_map/1` lives in `test/support/codec_helpers.ex` — a test-only helper that inverts the production decode. Production never encodes (the plugin is the encoder), so this stays in test support.

### `StateMachine` — invariant + metamorphic

**Invariants** (spec already lists three; add two more):

1. `:warning` never fires before 4:00 of continuous idle.
2. `:warning` fires exactly once per continuous idle period.
3. Any combat tick resets the notification set.
4. **NEW** `sm.state` is always one of `[:unknown, :logged_out, :fighting, :recovering, :idle, :dead]` after any `apply_tick`/`apply_event`.
5. **NEW** `state_since_ms` is monotonically non-decreasing within a session.

**Metamorphic** (relating outputs for related inputs):

6. Longer continuous idle period -> warning timestamp ≥ shorter idle period's warning timestamp.
7. Inserting a combat tick into an idle sequence delays warning by at least the recovery window.

### `Pet` — invariant + metamorphic

**Invariants**:

1. `fullness/2` is always in `[0.0, 1.0]`.
2. `energy/1` is always in `[0.0, 1.0]`.
3. `derive_target_mood/2` returns one of the six known mood atoms.

**Metamorphic** (the spec's "mood ordering" promise becomes a property):

4. For any model: setting `sm.state = :dead` always returns `:fainted` regardless of other fields.
5. For any model where the cond chain reaches `:hungry`: increasing `monks_killed` by enough to push `fullness > 0.2` switches the mood off `:hungry`.
6. More scroll detents (no other change) -> non-decreasing `energy/1`.

### `Session` — invariant

1. `record_kill/3` increases `monks_killed` by exactly 1.
2. `kill_history` length is always `min(monks_killed, 50)`.
3. The head of `kill_history` after `record_kill` is the just-recorded `{now, data}`.
4. `kills_per_hour/2` is non-negative.

### `Fidget` — model-based (the right fit, finally)

`Fidget` is a small state machine: scroll position accumulates, view cycles at threshold. Model it:

```elixir
defmodule FidgetModel do
  defstruct scroll: 0, view: :pet

  @views [:pet, :history, :stats, :sparkline]

  def scroll(m, delta) do
    new_pos = m.scroll + delta
    cond do
      new_pos > 30  -> %FidgetModel{scroll: 0, view: cycle(m.view, +1)}
      new_pos < -30 -> %FidgetModel{scroll: 0, view: cycle(m.view, -1)}
      true          -> %FidgetModel{m | scroll: new_pos}
    end
  end

  defp cycle(view, dir) do
    idx = Enum.find_index(@views, &(&1 == view))
    Enum.at(@views, rem(idx + dir + length(@views), length(@views)))
  end
end

property "Fidget matches the textbook scroll-cycle model" do
  check all deltas <- list_of(integer(-100..100), max_length: 200) do
    {model, real} =
      Enum.reduce(deltas, {%FidgetModel{}, %Fidget{}}, fn d, {m, r} ->
        {FidgetModel.scroll(m, d), Fidget.scroll(r, d)}
      end)

    assert model.scroll == real.scroll_position
    assert model.view == real.view_mode
  end
end
```

The textbook model is 20 lines. The real `Fidget` should match for every sequence StreamData throws at it.

### `Notifications` — invariant + metamorphic

1. `idle_alert_commands(fires, model, now)` returns `[]` when `now < model.muted_until_ms` (muting invariant).
2. `milestone_commands(n)` returns a single command iff `rem(n, 100) == 0 and n > 0`.
3. Metamorphic: lifting a mute (advancing `now` past `muted_until_ms`) produces commands that were previously suppressed for the same fires list.

### `Updaters` — invariant

1. `plugin_tick(model, tick).session.started_at == model.session.started_at` (Updater never resets the session).
2. After `monk_killed`, `model.session.monks_killed` strictly increased.
3. After `snooze(model, ms, now)`, `new_model.muted_until_ms == now + ms`.
4. `scroll(model, delta).fidget.scroll_position` matches `Fidget.scroll/2`'s output — i.e. Updater is a thin wrapper, no scroll logic leakage.

### `View.Components` — invariant + property

1. `bar(ratio, width)` returns a string of length `width` for any `ratio in [0.0, 1.0]`.
2. `format_mmss/1` is never longer than 5 characters for any non-negative ms.
3. `sparkline(history, now)` length equals min(history length, configured width).

## 4. Mock policy

Restating from the `tdd` skill and the project's existing rules:

- **Never mock internal modules.** Pure modules are tested with real inputs. GenServer surfaces are tested with real PubSub.
- **Stub only at system boundaries.** Three exist:
  1. **RuneLite UDS socket** — `test/support/fake_plugin.ex` opens a UDS server, accepts a list of lines to write, lets the test assert what `Plugin.Bridge` does with them.
  2. **Telegram Bot API** — `Bypass` (a real HTTP server on a local port) returns canned responses. `Telegex` is configured with the Bypass URL in test env.
  3. **APNS via raxol_watch** — `raxol_watch` should accept an adapter module. The test adapter buffers pushes; the test asserts on the buffer.

If a test would require mocking something else, that's a signal the structure is wrong, not that we need a mock.

## 5. Dependency injection — where it's actually needed

Most modules need none: they take data, return data. Two modules need DI for testability:

### `Plugin.Bridge` — inject the dispatch function

`Plugin.Bridge` currently calls `App.dispatch/1` directly. That couples Bridge tests to App's process. The fix is one keyword arg:

```elixir
def start_link(opts) do
  GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
end

def init_manager(opts) do
  {:ok, %__MODULE__{
    socket_path: Keyword.fetch!(opts, :socket_path),
    dispatch_fn: Keyword.get(opts, :dispatch_fn, &App.dispatch/1),
    backoff_ms: @reconnect_base_ms
  }}
end
```

Bridge tests pass `dispatch_fn: fn msg -> send(test_pid, msg) end` and `assert_receive {:tick, %Tick{}}`. No App needed.

This is the only non-trivial DI in the system.

### `Surfaces.*` — inject the outbound client

`Surfaces.Watch` and `Surfaces.Telegram` should accept their adapter modules so tests can substitute a buffering adapter. The spec's `Raxol.Watch.Notifier.push_to_all/1` is a candidate for this pattern — make it configurable via Application env at `:raxol_watch, :notifier`.

## 6. Deterministic CI

The `property-testing` skill requires reproducible runs. Configure ExUnit and StreamData:

```elixir
# config/test.exs
config :stream_data,
  max_runs: 200,
  max_run_time: 1_000,
  initial_size: 1
```

```bash
# CI invocation
MIX_ENV=test mix test --seed 0
```

Local exploration should drop the seed (`mix test`) to let StreamData find new failures. CI must always pin it.

## 7. System-boundary stub: `FakePlugin`

The most important test fixture. It lets every `Plugin.Bridge` test use a real UDS connection:

```elixir
defmodule Raxol.Monkwatcher.Test.FakePlugin do
  @moduledoc """
  Spins up a UDS listener that emits a script of lines, then closes.
  Use to drive Plugin.Bridge integration tests with the real wire format.
  """

  def start(socket_path, lines) when is_list(lines) do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        ifaddr: {:local, socket_path},
        active: false,
        reuseaddr: true
      ])

    spawn_link(fn ->
      {:ok, sock} = :gen_tcp.accept(listen)
      Enum.each(lines, fn line -> :gen_tcp.send(sock, line <> "\n") end)
      :gen_tcp.close(sock)
      :gen_tcp.close(listen)
    end)
  end
end
```

Tests:

```elixir
test "Bridge dispatches a tick from a real UDS line" do
  path = tmp_socket_path()
  FakePlugin.start(path, [~s({"t":123,"tick":1,"hp":50,"maxHp":85})])

  test_pid = self()
  {:ok, _} = Plugin.Bridge.start_link(
    socket_path: path,
    dispatch_fn: fn msg -> send(test_pid, msg) end
  )

  assert_receive %Plugin.Codec.Tick{t: 123, tick: 1, hp: 50, max_hp: 85}, 500
end
```

This test exercises real `:gen_tcp`, real `Jason.decode`, real `Plugin.Codec`, real `Plugin.Bridge` — every layer except `App`. It runs in <100ms.

## 8. What's out of scope here

- **Mutation testing** (`muzak` for Elixir) — the TDD skill calls this Phase 4. Worth considering once example + property tests stabilize, but not before. The two existing property catalogs already give strong coverage of the pure modules.
- **Concurrency stress tests** — the only concurrent surface is PubSub fan-out. Standard ExUnit message-passing assertions handle it; no Concuerror.
- **Load testing** — single user, ~1Hz events. N/A.
- **Snapshot testing of View output** — terminals make snapshots noisy. The view properties in §3 ("bar/2 returns exactly `width` chars") give more durable coverage.

## 9. Suggested first 5 tests

Build vertically. After the tracer bullet:

1. `StateMachine` invariant 4 (`state ∈ valid set`). One-line property; if it fails, the FSM has a hole.
2. `Session.record_kill` invariant 1 + 2 (count increases by 1, history capped at 50).
3. `Fidget` model-based property (the whole scroll-cycle).
4. `Pet.derive_target_mood` metamorphic 4 (`:dead` -> `:fainted` always).
5. `Plugin.Codec` roundtrip on the `%Tick{}` generator.

If those five pass, the pure stack is in shape. Move to the OTP layer with confidence.
