# raxol_monkwatcher

> A Raxol app that watches an OSRS session via the RuneLite bridge plugin. One TEA module, three surfaces (terminal, Telegram, Apple Watch). Designed as a Tamagotchi-meets-fidget-spinner — ambient companionship for a 6-hour monk grind, not an alarm clock.

## Design pivot: the surface IS the product

The original framing was "stop me from getting logged out." That's a 0.5-second-per-hour interaction and a boring app. The actual framing:

A defense pure at monks is a six-hour grind. The user is going to be fidgeting with *something* for the duration — phone, scroll wheel, a coffee cup. Raxol's three surfaces become that fidget object. The watch is the pet's heartbeat. Telegram is the stat card you glance at while your eyes are on the OSRS window. The terminal scroll wheel spins a virtual monk avatar and ticks a counter. The actual idle-warning is just one expression of the pet's state — when it's hungry, you hear from it. Most of the time you're just checking in.

The pet IS the monk you're hitting. Kill rate is feeding it. Idle minutes are it getting restless. Death is it fainting. Level-ups are it growing.

This reframes the model:

```elixir
%{
  pet: %{
    mood: :content,        # :content | :sleepy | :hungry | :panicked | :triumphant
    fullness: 0.74,        # 0.0-1.0, decays with idle time, +0.02 per monk kill
    energy: 0.62,          # tied to player run energy + recent kill rate
    age_ticks: 8421337,    # game ticks since session start
    name: "Brother Gerald" # random monk name on session start, for vibes
  },
  session: %{
    started_at: 1701234000000,
    monks_killed: 247,
    kill_history: [...],   # last 50 {timestamp, npc_name}
    deaths: 0,
    levels_gained: [{:defence, 60, 1701234500000}]
  },
  sm: StateMachine.struct,
  player: %{hp: ..., prayer: ..., location: ...},
  fidget: %{
    scroll_position: 0,    # accumulated scroll wheel input
    last_pet_tick: ...,    # idle-pet animation phase
    view_mode: :pet        # :pet | :history | :stats | :sparkline
  }
}
```

The state machine still lives underneath, still fires the warning at 4:00, but the surface narrative is the pet.

## Repo layout

```
raxol_monkwatcher/
├── mix.exs
├── README.md
├── lib/
│   └── raxol/monkwatcher/
│       ├── application.ex
│       ├── plugin_bridge.ex      # UDS consumer
│       ├── state_machine.ex      # pure functional, unit-testable
│       ├── pet.ex                # pure functional, derives pet state from model
│       ├── app.ex                # TEA module — init/update/view
│       ├── view/
│       │   ├── pet_view.ex       # the fidget surface (default)
│       │   ├── history_view.ex   # scroll wheel cycles in
│       │   ├── stats_view.ex
│       │   └── sparkline_view.ex
│       └── surfaces/
│           ├── telegram.ex
│           └── watch.ex
├── priv/
│   └── monk_names.txt            # random pet name pool
├── test/
│   └── raxol/monkwatcher/
│       ├── state_machine_test.exs
│       ├── state_machine_property_test.exs
│       └── pet_test.exs
└── config/
    └── config.exs
```

## The notification copy (terse, dignified)

Three rules:

1. **One word title, one number body.** "Monk" + "4:00". Your wrist already knows what app it's from after seeing it twice.
2. **No emoji in watch pushes.** Inconsistent rendering across watchOS versions, adds visual weight without information. Save emoji for Telegram where rendering is reliable.
3. **One button max on the wrist.** HIG penalty for second-tap is real.

```elixir
# Warning at 4:00 idle
%{title: "Monk", body: "4:00", priority: :normal,
  actions: [%{id: "snooze", label: "+60s"}]}

# Critical at 4:40 — no actions, just glance and act
%{title: "Monk", body: "Click!", priority: :high}

# Pet milestones — soft, non-urgent
%{title: "Monk", body: "+1 Def", priority: :normal}      # level up
%{title: "Monk", body: "100", priority: :normal}         # round-number kill

# Telegram pinned message edits in place to a single line:
"🧘 4:12 · 247 · 67/85"
# (idle time · kills · HP/maxHP — that's the whole status)
```

The critical push deliberately drops the action — at 4:40 you don't want to read button labels, you want to glance and act.

## The fidget surface

The default terminal view is the pet. ~24 rows, fits in any terminal.

```
╭─ Brother Gerald · session 02:47:33 ─────────────────────╮
│                                                         │
│                    ░░░▄▄▄▄▄░░░                          │
│                   ░▄█████████▄░         content         │
│                   ▄███▀░░░▀███▄         ───────         │
│                   ███░░◉░◉░░███         ♥ 0.74          │
│                   ███░░░▽░░░███         ⚡ 0.62          │
│                   ▀███▄▄▄▄▄███▀                         │
│                    ▀█████████▀                          │
│                                                         │
│  state: FIGHTING                idle: --:--             │
│                                                         │
│  HP   ████████████░░░░  67/85                           │
│  PRA  ██████░░░░░░░░░░  31/82                           │
│                                                         │
│  kills · 247   last · 4s   /hr · 312                    │
│                                                         │
│  ▁▁▂▂▁▂▃▂▁▂▂▃▂▁▂▂▃▂▂▁▂▂▃▂▁▂▃▂▁▂                         │
│                                                         │
│  ◀ pet   stats   history   sparkline ▶   scroll: 47     │
╰─────────────────────────────────────────────────────────╯
```

### What the scroll wheel does

The scroll wheel is the primary fidget input. It does three things simultaneously:

1. **Spins the pet avatar.** Each scroll detent shifts the ASCII art by one frame. There are 8 rotation frames; spinning the wheel feels like spinning the monk model. This is the fidget-spinner part. Spinning faster doesn't do anything functional, it just feels good and ticks `scroll_position`.

2. **Beyond a threshold, cycles view mode.** Scroll up past +30 detents in one motion → switches to history view. Scroll down past -30 → stats view. -60 → sparkline view. The threshold prevents accidental view changes from casual fidgeting. Reset to zero on view change.

3. **Becomes the pet's exercise meter.** Every 10 scroll detents adds 0.01 to `pet.energy`. The pet's `energy` is shown as ⚡ in the status. So fidgeting the wheel literally takes care of the pet. This is the loop.

### The mood states (Pet.derive/1)

```elixir
def derive(model) do
  cond do
    model.sm.state == :dead -> :fainted
    model.sm.state == :idle and idle_seconds(model) > 270 -> :panicked
    model.sm.state == :idle and idle_seconds(model) > 60 -> :sleepy
    model.session.monks_killed > 0
        and just_leveled?(model) -> :triumphant
    pet_fullness(model) < 0.2 -> :hungry
    pet_fullness(model) > 0.8 -> :content
    true -> :content
  end
end
```

Each mood has its own ASCII art frame set (8 frames each, scroll-rotatable):

- `:content` — the monk-pet sits cross-legged, gentle breathing animation
- `:sleepy` — eyes drift closed, "z" floats up
- `:hungry` — looks toward you, slight frown, faster idle animation
- `:panicked` — eyes wide, sweat drops — this is the 4:00+ idle state
- `:triumphant` — arms raised, brief glow effect on level-up
- `:fainted` — X eyes, lying down (player death)

Mood transitions take 5-10 ticks (~3-6 seconds) so they don't snap jarringly. The state machine fires the watch notification; the pet just shows it changing on the screen.

### Three input surfaces, three fidget channels

1. **Scroll wheel (terminal)** — spin the pet, cycle views, exercise meter
2. **Phone tap (Telegram inline keyboard)** — single pinned message with two buttons: `[💤 +60s]` `[🍞 feed]`. The feed button does nothing mechanical — it just animates the pet eating in the terminal and bumps `pet.fullness` by 0.05. Pure fidget affordance.
3. **Watch double-tap** — when the watch buzzes, double-tap to acknowledge. Outside of notifications, raising the wrist shows the pet's complication: just a single glyph (the mood as a Unicode emoticon) and the kill count.

The user's hands are busy with the OSRS mouse. Their eyes flicker between OSRS and the secondary surface. The phone is on the desk; the watch is on the wrist; the scroll wheel is under the index finger. Whichever one they reach for, the pet's there.

## File: `lib/raxol/monkwatcher/application.ex`

```elixir
defmodule Raxol.Monkwatcher.Application do
  use Application

  @impl true
  def start(_type, _args) do
    socket_path = Application.fetch_env!(:raxol_monkwatcher, :socket_path)

    children = [
      {Phoenix.PubSub, name: Raxol.Monkwatcher.PubSub},
      {Raxol.Monkwatcher.App, []},
      {Raxol.Monkwatcher.PluginBridge, [socket_path: socket_path]}
      # Surfaces.Telegram and Surfaces.Watch added conditionally below
    ]

    children = children ++ optional_surfaces()

    opts = [strategy: :one_for_one, name: Raxol.Monkwatcher.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp optional_surfaces do
    []
    |> add_if(Application.get_env(:raxol_monkwatcher, :telegram_enabled, false),
             Raxol.Monkwatcher.Surfaces.Telegram)
    |> add_if(Application.get_env(:raxol_monkwatcher, :watch_enabled, false),
             Raxol.Monkwatcher.Surfaces.Watch)
  end

  defp add_if(list, true, mod), do: list ++ [mod]
  defp add_if(list, false, _), do: list
end
```

## File: `lib/raxol/monkwatcher/plugin_bridge.ex`

```elixir
defmodule Raxol.Monkwatcher.PluginBridge do
  @moduledoc """
  Connects to the RuneLite plugin's Unix socket, decodes
  newline-delimited JSON, dispatches messages to the TEA app.

  Reconnects with exponential backoff so RuneLite and Raxol can
  start in any order and either side can restart independently.
  """
  use Raxol.Core.Behaviours.BaseManager
  require Logger

  @reconnect_base_ms 500
  @reconnect_max_ms 10_000

  defstruct [:socket_path, :socket, :backoff_ms]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init_manager(opts) do
    state = %__MODULE__{
      socket_path: Keyword.fetch!(opts, :socket_path),
      backoff_ms: @reconnect_base_ms
    }
    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_manager_info(:connect, state) do
    case :gen_tcp.connect({:local, state.socket_path}, 0,
                          [:binary, active: :once, packet: :line]) do
      {:ok, socket} ->
        Logger.info("PluginBridge connected #{state.socket_path}")
        {:noreply, %{state | socket: socket, backoff_ms: @reconnect_base_ms}}

      {:error, reason} ->
        Logger.debug("PluginBridge connect failed: #{inspect(reason)}, retry in #{state.backoff_ms}ms")
        Process.send_after(self(), :connect, state.backoff_ms)
        {:noreply, %{state | backoff_ms: min(state.backoff_ms * 2, @reconnect_max_ms)}}
    end
  end

  def handle_manager_info({:tcp, socket, line}, %{socket: socket} = state) do
    case Jason.decode(line) do
      {:ok, %{"event" => type, "data" => data}} ->
        Raxol.Monkwatcher.App.dispatch({:game_event, type, data})
      {:ok, payload} ->
        Raxol.Monkwatcher.App.dispatch({:plugin_tick, payload})
      {:error, e} ->
        Logger.warning("PluginBridge bad JSON: #{inspect(e)}")
    end
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_manager_info({:tcp_closed, _socket}, state) do
    Logger.info("PluginBridge socket closed, reconnecting")
    send(self(), :connect)
    {:noreply, %{state | socket: nil}}
  end
end
```

Notes:

- `:gen_tcp.connect({:local, path}, 0, ...)` is Elixir's UDS syntax. Port `0` is required.
- `packet: :line` does the newline framing — no buffer accumulation needed.
- `active: :once` is the right backpressure mode. `active: true` would let a stuck App process buffer the entire session.

## File: `lib/raxol/monkwatcher/state_machine.ex`

```elixir
defmodule Raxol.Monkwatcher.StateMachine do
  @moduledoc """
  Pure functional state machine over plugin tick payloads.

  States:
    :unknown    — pre-first-tick
    :logged_out — GAME_STATE not LOGGED_IN
    :fighting   — interacting with a monk OR mid-attack animation
    :recovering — was fighting in the last `recovery_window_ms`
    :idle       — not fighting, not recovering, timer ticking
    :dead       — player death event

  Notifications fire on transitions and while in :idle.
  """

  defstruct [
    state: :unknown,
    state_since_ms: nil,
    last_combat_ms: nil,
    last_tick: nil,
    last_payload: nil,
    notified: MapSet.new()
  ]

  @attack_animations MapSet.new([
    422, 423, 1156, 1157, 1162,  # unarmed
    386, 390, 393, 400, 401, 406, 407, 412  # melee weapons
    # extend as discovered
  ])

  @recovery_window_ms 30_000
  @warning_idle_ms 240_000   # 4:00
  @critical_idle_ms 280_000  # 4:40

  def new, do: %__MODULE__{}

  def apply_tick(sm, payload) do
    now = payload["t"]
    cond do
      fighting?(payload) ->
        sm
        |> transition(:fighting, now)
        |> Map.put(:last_combat_ms, now)
        |> Map.put(:notified, MapSet.new())  # reset thresholds on combat
        |> Map.put(:last_payload, payload)
        |> Map.put(:last_tick, payload["tick"])

      recovering?(sm, now) ->
        sm
        |> transition(:recovering, now)
        |> Map.put(:last_payload, payload)
        |> Map.put(:last_tick, payload["tick"])

      true ->
        sm
        |> transition(:idle, now)
        |> Map.put(:last_payload, payload)
        |> Map.put(:last_tick, payload["tick"])
    end
  end

  def apply_event(sm, "game_state", %{"state" => "LOGGED_OUT"}, now),
    do: transition(sm, :logged_out, now)
  def apply_event(sm, "player_death", _, now),
    do: transition(sm, :dead, now)
  def apply_event(sm, _, _, _), do: sm

  @doc "Returns {sm, [:warning | :critical, ...]} for thresholds crossed."
  def check_thresholds(%__MODULE__{state: :idle, state_since_ms: since} = sm, now)
      when is_integer(since) do
    idle_for = now - since
    fires =
      []
      |> maybe_fire(:warning, idle_for >= @warning_idle_ms, sm.notified)
      |> maybe_fire(:critical, idle_for >= @critical_idle_ms, sm.notified)

    new_notified = Enum.reduce(fires, sm.notified, &MapSet.put(&2, &1))
    {%{sm | notified: new_notified}, fires}
  end

  def check_thresholds(sm, _now), do: {sm, []}

  @doc "How long the player has been in the current state."
  def time_in_state_ms(%__MODULE__{state_since_ms: nil}, _now), do: 0
  def time_in_state_ms(%__MODULE__{state_since_ms: since}, now), do: now - since

  # --- private ---

  defp fighting?(payload) do
    payload["isMonk"] == true or
      MapSet.member?(@attack_animations, payload["anim"] || -1)
  end

  defp recovering?(%__MODULE__{last_combat_ms: nil}, _), do: false
  defp recovering?(%__MODULE__{last_combat_ms: last}, now),
    do: now - last < @recovery_window_ms

  defp transition(%__MODULE__{state: same} = sm, same, _now), do: sm
  defp transition(sm, new_state, now),
    do: %{sm | state: new_state, state_since_ms: now}

  defp maybe_fire(list, level, true, notified) do
    if MapSet.member?(notified, level), do: list, else: [level | list]
  end
  defp maybe_fire(list, _, _, _), do: list
end
```

## File: `lib/raxol/monkwatcher/pet.ex`

```elixir
defmodule Raxol.Monkwatcher.Pet do
  @moduledoc """
  Pure functions deriving pet state from the model. The pet IS the
  emergent fiction over the underlying state machine + session stats.
  """

  alias Raxol.Monkwatcher.StateMachine

  @fullness_per_kill 0.02
  @fullness_decay_per_idle_minute 0.05
  @energy_per_scroll_detent 0.001

  def derive_mood(model, now) do
    cond do
      model.sm.state == :dead -> :fainted
      model.sm.state == :idle and idle_ms(model.sm, now) > 270_000 -> :panicked
      model.sm.state == :idle and idle_ms(model.sm, now) > 60_000 -> :sleepy
      just_leveled?(model, now) -> :triumphant
      fullness(model, now) < 0.2 -> :hungry
      fullness(model, now) > 0.8 -> :content
      true -> :content
    end
  end

  def fullness(model, now) do
    base = model.session.monks_killed * @fullness_per_kill
    idle_minutes = max(0, idle_ms(model.sm, now) / 60_000)
    decay = idle_minutes * @fullness_decay_per_idle_minute
    Float.round(clamp(base - decay + 0.5, 0.0, 1.0), 2)
  end

  def energy(model) do
    fidget_bonus = model.fidget.scroll_position * @energy_per_scroll_detent
    base = (model.player.run_energy || 50) / 100
    Float.round(clamp(base + fidget_bonus, 0.0, 1.0), 2)
  end

  # Returns the ASCII frame for current mood, rotated by scroll position.
  def frame(mood, scroll_pos) do
    frames = mood_frames(mood)
    idx = rem(abs(scroll_pos), length(frames))
    Enum.at(frames, idx)
  end

  defp mood_frames(:content), do: Raxol.Monkwatcher.Pet.Frames.content()
  defp mood_frames(:sleepy), do: Raxol.Monkwatcher.Pet.Frames.sleepy()
  defp mood_frames(:hungry), do: Raxol.Monkwatcher.Pet.Frames.hungry()
  defp mood_frames(:panicked), do: Raxol.Monkwatcher.Pet.Frames.panicked()
  defp mood_frames(:triumphant), do: Raxol.Monkwatcher.Pet.Frames.triumphant()
  defp mood_frames(:fainted), do: Raxol.Monkwatcher.Pet.Frames.fainted()

  defp idle_ms(sm, now), do: StateMachine.time_in_state_ms(sm, now)

  defp just_leveled?(model, now) do
    case model.session.levels_gained do
      [{_skill, _level, ts} | _] -> now - ts < 5_000
      _ -> false
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
end
```

Pet frames live in a separate module so the ASCII art doesn't clutter the logic. Each mood gets 8 frames; rotation comes from the scroll wheel.

## File: `lib/raxol/monkwatcher/app.ex`

```elixir
defmodule Raxol.Monkwatcher.App do
  use Raxol.Core.Runtime.Application

  alias Raxol.Monkwatcher.{StateMachine, Pet, View}

  @scroll_threshold_cycle 30

  def init(_ctx) do
    %{
      sm: StateMachine.new(),
      session: %{
        started_at: System.system_time(:millisecond),
        monks_killed: 0,
        kill_history: [],
        deaths: 0,
        levels_gained: []
      },
      player: %{
        hp: nil, max_hp: nil,
        prayer: nil, max_prayer: nil,
        run_energy: 50,
        location: nil
      },
      pet: %{
        name: random_monk_name(),
        mood: :content
      },
      fidget: %{
        scroll_position: 0,
        view_mode: :pet
      },
      muted_until_ms: 0
    }
  end

  # --- plugin tick ---
  def update({:plugin_tick, payload}, model) do
    now = payload["t"]
    sm = StateMachine.apply_tick(model.sm, payload)
    {sm, fires} = StateMachine.check_thresholds(sm, now)

    new_model = %{model |
      sm: sm,
      player: %{
        hp: payload["hp"], max_hp: payload["maxHp"],
        prayer: payload["prayer"], max_prayer: payload["maxPrayer"],
        run_energy: payload["runEnergy"],
        location: {payload["x"], payload["y"], payload["plane"]}
      }
    }
    new_model = %{new_model | pet: %{new_model.pet | mood: Pet.derive_mood(new_model, now)}}
    {new_model, build_notification_commands(fires, new_model, now)}
  end

  # --- game events ---
  def update({:game_event, "monk_killed", data}, model) do
    now = System.system_time(:millisecond)
    session = %{model.session |
      monks_killed: model.session.monks_killed + 1,
      kill_history: [{now, data} | model.session.kill_history] |> Enum.take(50)
    }
    new_model = %{model | session: session}
    new_model = %{new_model | pet: %{new_model.pet | mood: Pet.derive_mood(new_model, now)}}
    commands = milestone_commands(session.monks_killed)
    {new_model, commands}
  end

  def update({:game_event, "player_death", _}, model) do
    session = %{model.session | deaths: model.session.deaths + 1}
    new_model = %{model | session: session,
                          sm: %{model.sm | state: :dead,
                                state_since_ms: System.system_time(:millisecond)}}
    new_model = %{new_model | pet: %{new_model.pet | mood: :fainted}}
    {new_model, [broadcast_cmd({:pet_event, :fainted, new_model})]}
  end

  def update({:game_event, type, data}, model) do
    sm = StateMachine.apply_event(model.sm, type, data, System.system_time(:millisecond))
    {%{model | sm: sm}, []}
  end

  # --- fidget input ---
  def update({:scroll, delta}, model) do
    new_pos = model.fidget.scroll_position + delta
    {new_pos, new_view_mode} = maybe_cycle_view(new_pos, model.fidget.view_mode)
    new_fidget = %{model.fidget | scroll_position: new_pos, view_mode: new_view_mode}
    {%{model | fidget: new_fidget}, []}
  end

  def update({:feed}, model) do
    # No mechanical effect; just the pet's mood lifts briefly.
    # The pet derive function picks this up via fullness recalc.
    new_pet = %{model.pet | mood: :content}
    {%{model | pet: new_pet}, []}
  end

  def update({:snooze, ms}, model) do
    until = System.system_time(:millisecond) + ms
    {%{model | muted_until_ms: until}, []}
  end

  def update(_msg, model), do: {model, []}

  def view(model), do: View.render(model)

  # --- dispatch helper for external callers ---
  def dispatch(msg) do
    GenServer.cast(__MODULE__, {:dispatch, msg})
  end

  # --- private ---

  defp build_notification_commands(fires, model, now) do
    if now < model.muted_until_ms do
      []
    else
      Enum.map(fires, fn level ->
        broadcast_cmd({:idle_alert, level, model})
      end)
    end
  end

  defp milestone_commands(kills) when rem(kills, 100) == 0 and kills > 0,
    do: [broadcast_cmd({:milestone, :kills, kills})]
  defp milestone_commands(_), do: []

  defp broadcast_cmd(payload) do
    {:async, fn ->
      Phoenix.PubSub.broadcast(Raxol.Monkwatcher.PubSub, "alerts", payload)
    end}
  end

  defp maybe_cycle_view(pos, current) when pos > @scroll_threshold_cycle,
    do: {0, next_view(current, :forward)}
  defp maybe_cycle_view(pos, current) when pos < -@scroll_threshold_cycle,
    do: {0, next_view(current, :backward)}
  defp maybe_cycle_view(pos, current), do: {pos, current}

  defp next_view(:pet, :forward), do: :history
  defp next_view(:history, :forward), do: :stats
  defp next_view(:stats, :forward), do: :sparkline
  defp next_view(:sparkline, :forward), do: :pet
  defp next_view(:pet, :backward), do: :sparkline
  defp next_view(:sparkline, :backward), do: :stats
  defp next_view(:stats, :backward), do: :history
  defp next_view(:history, :backward), do: :pet

  defp random_monk_name do
    names = "priv/monk_names.txt"
            |> File.read!()
            |> String.split("\n", trim: true)
    Enum.random(names)
  end
end
```

## File: `lib/raxol/monkwatcher/surfaces/watch.ex`

```elixir
defmodule Raxol.Monkwatcher.Surfaces.Watch do
  @moduledoc """
  Subscribes to App alerts and pushes terse APNS to the wrist.
  Tap-back actions route to App.dispatch/1 via raxol_watch.
  """
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(Raxol.Monkwatcher.PubSub, "alerts")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:idle_alert, :warning, _model}, state) do
    Raxol.Watch.Notifier.push_to_all(%{
      title: "Monk",
      body: "4:00",
      priority: :normal,
      category: "monkwatcher",
      actions: [%{id: "snooze", label: "+60s"}]
    })
    {:noreply, state}
  end

  def handle_info({:idle_alert, :critical, _model}, state) do
    Raxol.Watch.Notifier.push_to_all(%{
      title: "Monk",
      body: "Click!",
      priority: :high,
      category: "monkwatcher"
    })
    {:noreply, state}
  end

  def handle_info({:milestone, :kills, n}, state) do
    Raxol.Watch.Notifier.push_to_all(%{
      title: "Monk",
      body: to_string(n),
      priority: :normal,
      category: "monkwatcher"
    })
    {:noreply, state}
  end

  def handle_info({:pet_event, :fainted, _model}, state) do
    Raxol.Watch.Notifier.push_to_all(%{
      title: "Monk",
      body: "Died.",
      priority: :high,
      category: "monkwatcher"
    })
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
```

The action map for tap-back (set in app config):

```elixir
config :raxol_watch,
  action_dispatcher: Raxol.Monkwatcher.App,
  action_map: %{
    "snooze" => {:snooze, 60_000}
  }
```

## File: `lib/raxol/monkwatcher/surfaces/telegram.ex`

The pinned message strategy — one message per session, edited in place. The message_id is held in surface state.

```elixir
defmodule Raxol.Monkwatcher.Surfaces.Telegram do
  use GenServer

  defstruct [:chat_id, :pinned_msg_id]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(Raxol.Monkwatcher.PubSub, "alerts")
    chat_id = Keyword.fetch!(opts, :chat_id)
    # Send the initial pinned message on startup
    msg = send_pinned(chat_id, "🧘 starting…", default_keyboard())
    {:ok, %__MODULE__{chat_id: chat_id, pinned_msg_id: msg.message_id}}
  end

  @impl true
  def handle_info({:idle_alert, level, model}, state) do
    body = format_status(model, level)
    edit_pinned(state, body)
    {:noreply, state}
  end

  def handle_info({:milestone, :kills, n}, state) do
    edit_pinned(state, "🎯 #{n} kills")
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp format_status(model, :warning),
    do: "💤 4:00 · #{model.session.monks_killed} · HP #{model.player.hp}/#{model.player.max_hp}"
  defp format_status(model, :critical),
    do: "⚠️ CLICK · #{model.session.monks_killed} · HP #{model.player.hp}/#{model.player.max_hp}"
  defp format_status(model, _),
    do: "🧘 ok · #{model.session.monks_killed} · HP #{model.player.hp}/#{model.player.max_hp}"

  defp default_keyboard do
    [
      [%{text: "💤 +60s", callback_data: "snooze:60"}],
      [%{text: "🍞 feed", callback_data: "feed"}]
    ]
  end

  defp send_pinned(chat_id, text, keyboard) do
    # Wrap Telegex.send_message + Telegex.pin_chat_message
    # (omitted; implementation depends on Telegex version)
  end

  defp edit_pinned(state, text) do
    # Telegex.edit_message_text with chat_id + msg_id
    # Edit dedup is handled by raxol_telegram's Session layer
  end
end
```

Callback queries from inline buttons route via `raxol_telegram`'s Bot module — wire `callback_data` to `Raxol.Monkwatcher.App.dispatch/1`.

## File: `lib/raxol/monkwatcher/view/pet_view.ex`

```elixir
defmodule Raxol.Monkwatcher.View.PetView do
  import Raxol.View
  alias Raxol.Monkwatcher.Pet

  def render(model) do
    now = System.system_time(:millisecond)
    mood = model.pet.mood
    frame = Pet.frame(mood, model.fidget.scroll_position)
    fullness_bar = bar(Pet.fullness(model, now), 16)
    energy_bar = bar(Pet.energy(model), 16)
    hp_bar = bar(safe_ratio(model.player.hp, model.player.max_hp), 16)
    prayer_bar = bar(safe_ratio(model.player.prayer, model.player.max_prayer), 16)

    column style: %{padding: 1, gap: 0} do
      [
        text(header(model), style: [:bold]),
        text(""),
        row do
          [
            text(frame),  # the 8-line pet ASCII frame
            column style: %{padding_left: 4} do
              [
                text("#{format_mood(mood)}", style: mood_style(mood)),
                text("───────"),
                text("♥ #{fullness_bar} #{Pet.fullness(model, now)}"),
                text("⚡ #{energy_bar} #{Pet.energy(model)}")
              ]
            end
          ]
        end,
        text(""),
        text("state: #{format_state(model.sm)}    #{idle_display(model.sm, now)}"),
        text(""),
        text("HP   #{hp_bar}  #{model.player.hp}/#{model.player.max_hp}"),
        text("PRA  #{prayer_bar}  #{model.player.prayer}/#{model.player.max_prayer}"),
        text(""),
        text("kills · #{model.session.monks_killed}   last · #{last_kill_age(model.session, now)}   /hr · #{kills_per_hour(model.session, now)}"),
        text(""),
        text(sparkline(model.session.kill_history, now)),
        text(""),
        text(view_tabs(model.fidget.view_mode, model.fidget.scroll_position))
      ]
    end
  end

  defp header(model) do
    session_age = (System.system_time(:millisecond) - model.session.started_at) |> ms_to_hms()
    "─ #{model.pet.name} · session #{session_age} ─"
  end

  defp bar(ratio, width) do
    filled = round(ratio * width)
    empty = width - filled
    String.duplicate("█", filled) <> String.duplicate("░", empty)
  end

  defp safe_ratio(_, nil), do: 0.0
  defp safe_ratio(nil, _), do: 0.0
  defp safe_ratio(v, max), do: v / max

  defp format_mood(:content), do: "content"
  defp format_mood(:sleepy), do: "sleepy"
  defp format_mood(:hungry), do: "hungry"
  defp format_mood(:panicked), do: "PANICKED"
  defp format_mood(:triumphant), do: "TRIUMPHANT"
  defp format_mood(:fainted), do: "fainted"

  defp mood_style(:panicked), do: [fg: :red, bold: true]
  defp mood_style(:triumphant), do: [fg: :yellow, bold: true]
  defp mood_style(:fainted), do: [fg: :magenta]
  defp mood_style(_), do: []

  defp format_state(%{state: state}), do: state |> to_string() |> String.upcase()

  defp idle_display(%{state: :idle, state_since_ms: since}, now) do
    "idle: #{ms_to_mmss(now - since)}"
  end
  defp idle_display(_, _), do: "idle: --:--"

  # ... ms_to_hms, ms_to_mmss, last_kill_age, kills_per_hour, sparkline, view_tabs
end
```

Other views (`HistoryView`, `StatsView`, `SparklineView`) are simpler — straightforward projections of `model.session`.

## Property tests for the state machine

```elixir
defmodule Raxol.Monkwatcher.StateMachinePropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Raxol.Monkwatcher.StateMachine

  property ":warning never fires before 4 minutes of continuous idle" do
    check all stream <- idle_only_tick_stream(max_seconds: 239) do
      sm = Enum.reduce(stream, StateMachine.new(), &StateMachine.apply_tick(&2, &1))
      last_t = List.last(stream)["t"] || 0
      {_sm, fires} = StateMachine.check_thresholds(sm, last_t)
      assert :warning not in fires
    end
  end

  property ":warning fires exactly once per continuous idle period" do
    check all stream <- idle_only_tick_stream(min_seconds: 300, max_seconds: 600) do
      {_sm, all_fires} =
        Enum.reduce(stream, {StateMachine.new(), []}, fn payload, {sm, acc} ->
          sm = StateMachine.apply_tick(sm, payload)
          {sm, fires} = StateMachine.check_thresholds(sm, payload["t"])
          {sm, acc ++ fires}
        end)
      assert Enum.count(all_fires, &(&1 == :warning)) == 1
    end
  end

  property "any combat tick resets the notification set" do
    check all idle_stream <- idle_only_tick_stream(min_seconds: 300, max_seconds: 400),
              fight_stream <- fighting_tick_stream(min_seconds: 5, max_seconds: 10),
              more_idle <- idle_only_tick_stream(min_seconds: 300, max_seconds: 400) do
      stream = idle_stream ++ fight_stream ++ more_idle
      {_sm, all_fires} =
        Enum.reduce(stream, {StateMachine.new(), []}, fn p, {sm, acc} ->
          sm = StateMachine.apply_tick(sm, p)
          {sm, f} = StateMachine.check_thresholds(sm, p["t"])
          {sm, acc ++ f}
        end)
      # Two separate idle periods → two warnings
      assert Enum.count(all_fires, &(&1 == :warning)) == 2
    end
  end

  defp idle_only_tick_stream(opts), do: ...
  defp fighting_tick_stream(opts), do: ...
end
```

The stream generators produce realistic tick payloads (one per 600ms) so the tests run against the real wire format.

## What to build first, in order

1. **RuneLite plugin sending ticks to UDS.** Verify with `nc -U` that JSON streams. No Elixir yet.
2. **PluginBridge + stub App that logs every tick to a file.** Get the wire format stable. Use the file to record real play sessions for tuning the state machine.
3. **StateMachine as pure module + property tests.** Replay recorded sessions against it. Tune `@recovery_window_ms`, the attack animations list, the thresholds.
4. **Pet module + ASCII frames + PetView.** This is the fun part. Take a day on the ASCII art alone.
5. **App with full update/view, terminal surface working end-to-end.**
6. **Watch surface.** Highest leverage — buzz on wrist while eyes on OSRS.
7. **Scroll wheel handling.** Wire raxol terminal's scroll event to `App.dispatch({:scroll, delta})`. This is when the fidget loop closes.
8. **Telegram surface.** Lowest priority — only matters when you step away from the laptop.

Realistic timing: 1-2 is an evening. 3 is an afternoon plus a week of tuning during real play. 4 is a day for art + integration. 5-7 are a day. 8 is two hours.

## Things deliberately not included

- **No XP/hour calculator beyond kills/hr.** Raxol isn't replacing RuneLite's XP tracker.
- **No "best monk location" guidance.** This is a companion, not a coach.
- **No memory of past sessions.** Each session is a fresh pet with a fresh name. Persistent stats are anti-Tamagotchi — half the charm is the temporary bond.
- **No auto-click anything ever.** This is the line. If the conversation ever reaches "what if we just sent a click after the 4:40 push…" — no.
- **No social features.** No leaderboard, no shared pets, no clan integration. One person, one pet, one grind.
- **No music or sound.** The OSRS client has its own audio; layering on top is rude.
- **No real-money anything.** This is the one place in the Raxol portfolio where the `raxol_payments` integration would be deeply wrong. Keep it out.
