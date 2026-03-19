# Argus — Architecture

## Overview

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  Elixir (BEAM)                      │
                    │                                                     │
  ┌──────────────┐  │  ┌─────────────┐   ┌───────────────────────────┐   │
  │  YAML Config │──┼─▶│  Config     │   │  Pipeline Engine          │   │
  └──────────────┘  │  │  Loader /   │──▶│  • receive envelopes      │   │
                    │  │  Validator  │   │  • apply transforms       │   │
                    │  └─────────────┘   │  • fan-out to outputs     │   │
                    │                    └───────────┬───────────────┘   │
                    │  ┌─────────────────────────────▼───────────────┐   │
                    │  │  IPC: RustHost  (Port / stdio JSON)         │   │
                    │  └─────────────────────────────┬───────────────┘   │
                    └────────────────────────────────┼───────────────────┘
                                                     │ line-delimited JSON
                    ┌────────────────────────────────▼───────────────────┐
                    │                  Rust (Tokio)                      │
                    │                                                     │
                    │  connector_host binary                              │
                    │  ┌──────────────────┐   ┌────────────────────────┐ │
                    │  │  Connectors      │   │  Sinks                 │ │
                    │  │  • Kafka consumer│   │  • Log (stdout/stderr) │ │
                    │  │  • (ROADMAP) MQTT│   │  • Kafka producer      │ │
                    │  │  • (ROADMAP) AMQP│   │  • (ROADMAP) DB sink   │ │
                    │  └──────────────────┘   └────────────────────────┘ │
                    └─────────────────────────────────────────────────────┘
```

## Components

### `apps/router_core` (Elixir)

| Module | Responsibility |
|--------|----------------|
| `RouterCore.Config` | Load and validate YAML; fail fast with helpful errors |
| `RouterCore.Envelope` | Canonical event struct |
| `RouterCore.Pipeline` | Receive envelopes from Rust host, apply transforms, fan-out |
| `RouterCore.Supervisor` | OTP supervision tree |
| `RouterCore.IPC.RustHost` | Spawn/manage Rust process via Erlang Port |
| `RouterCore.IPC.Protocol` | Encode/decode line-delimited JSON IPC messages |
| `RouterCore.Metrics` | HTTP endpoint (`:4000/metrics`) — JSON counters |

### `crates/connector_host` (Rust)

| Module | Responsibility |
|--------|----------------|
| `protocol` | Serde types for IPC commands / events |
| `envelope` | Canonical event struct (mirrors Elixir) |
| `connectors::kafka` | Kafka consumer (rskafka) |
| `sinks::log` | Print envelope as JSON to stderr |
| Kafka producer | Inline in `main.rs` dispatch loop |

## IPC Protocol

Line-delimited JSON over the process's stdio:

### Elixir → Rust (commands)

```json
{ "cmd": "start_input",  "name": "kafka_in",  "config": { "brokers": "...", "topic": "..." } }
{ "cmd": "start_output", "name": "kafka_out", "config": { "brokers": "...", "topic": "..." } }
{ "cmd": "send_output",  "name": "kafka_out", "envelope": { ... } }
{ "cmd": "send_output",  "name": "log_out",   "envelope": { ... } }
{ "cmd": "shutdown" }
```

### Rust → Elixir (events)

```json
{ "event": "ingest", "input": "kafka_in", "envelope": { ... } }
{ "event": "ack",    "ref": "optional-correlation-id" }
{ "event": "error",  "message": "...", "details": { ... } }
```

## Extension Points

* **New connector**: add a module under `crates/connector_host/src/connectors/`
  and handle the new `type` in `Config` validation.
* **New sink**: add a module under `crates/connector_host/src/sinks/`.
* **New transform**: implement `RouterCore.Transform` behaviour in
  `apps/router_core/lib/transforms/`.
* **Config hot-reload**: > **Issue:** Config hot-reload — add inotify watcher and reload signal to RouterCore.Supervisor.

## Design Decisions

* **IPC over stdio** was chosen for bootstrap simplicity; replace with Unix
  domain socket or gRPC later if latency matters.
* **Redpanda** is used instead of Kafka+ZooKeeper — same API, single container,
  no coordination overhead.
* **No NIFs** — all native work happens in the separately-spawned Rust process.
