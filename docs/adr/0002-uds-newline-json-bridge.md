# 2. Use a Unix Domain Socket with newline-delimited JSON for the RuneLite bridge

Date: 2026-06-09

## Status

Proposed

## Context

The RuneLite plugin (a Java program inside the OSRS client) needs to stream game state to the Elixir app. Both processes run on the same machine — this is a personal tool, not a distributed system.

Options considered:

- **Local TCP socket on localhost**. Works. Adds a listening port that other processes on the machine can see and connect to. Requires choosing a port.
- **Unix Domain Socket**. Same `:gen_tcp` API in Elixir with `{:local, path}`. Filesystem permissions handle access control. No port to choose. Lower kernel overhead than TCP loopback.
- **stdin/stdout pipe**. Tightest coupling — RuneLite plugin would need to be a subprocess of the Elixir app, which inverts the natural lifecycle (RuneLite is the user-facing program, Elixir is the watcher).
- **WebSocket**. Heavyweight for a same-host link; only justified if a browser is on one side.
- **A message broker** (Redis, NATS). Operationally absurd for one user.

Wire format options: protobuf (schema overhead), MessagePack (smaller but needs a Java decoder), newline-delimited JSON (readable, debuggable with `nc -U`, every language has a parser).

## Decision

We will use a Unix Domain Socket at a path configured per environment (e.g., `~/.cache/raxol_monkwatcher/plugin.sock`). The wire format is newline-delimited JSON: one event per line, framed by `\n`, parsed with `Jason`.

`PluginBridge` connects with `:gen_tcp.connect({:local, path}, 0, [:binary, active: :once, packet: :line])`. Either side may restart at any time; `PluginBridge` reconnects with exponential backoff (500ms doubling to 10s cap).

The plugin emits two shapes:

- `{"event": "<type>", "data": {...}}` for discrete events (kill, death, game-state change)
- A tick payload with `t`, `tick`, `isMonk`, `anim`, `hp`, `prayer`, `runEnergy`, `x`, `y`, `plane` fields for continuous state

## Consequences

**Positive**

- Debuggable: `nc -U ~/.cache/.../plugin.sock` prints the live stream.
- Filesystem permissions are the access model — no TLS, no auth tokens.
- `packet: :line` does framing in the kernel; no buffer accumulator in Elixir.
- `active: :once` applies backpressure: if `App` falls behind, the kernel buffers and eventually blocks the producer.
- Reconnect logic decouples lifecycle — RuneLite and Elixir start in any order.

**Negative**

- Same-host only. Cannot stream to Elixir on a different machine without a TCP proxy.
- JSON is verbose. At one tick per 600ms with ~10 fields, this is ~50KB/min — irrelevant on local IPC.
- The protocol is schemaless. A field rename in the plugin without a coordinated Elixir change goes undetected until runtime. Mitigation: include a `"v"` (protocol version) field in every message and reject unknown versions in `PluginBridge`.
- Windows support requires `AF_UNIX` named pipes; unverified on Erlang/OTP for Windows. Not a target platform.
