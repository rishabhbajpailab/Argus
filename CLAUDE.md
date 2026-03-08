# CLAUDE.md — Argus Event Router

This file provides guidance for AI assistants (Claude, Copilot, etc.) working on this codebase.

---

## Project Overview

**Argus** is a declarative event-routing system that consolidates messages from multiple sources (e.g., Kafka topics) and fans them out to multiple sinks (e.g., log, Postgres). It uses a two-process architecture:

- **Elixir/OTP** (`apps/router_core`) — orchestration, supervision, pipeline execution, metrics HTTP endpoint
- **Rust** (`crates/connector_host`) — native I/O connectors and sinks, communicating with Elixir via line-delimited JSON over stdio

---

## Repository Layout

```
Argus/
├── apps/router_core/          # Elixir OTP application
│   ├── lib/
│   │   ├── router_core.ex     # Entry point; loads config
│   │   ├── supervisor.ex      # OTP supervision tree
│   │   ├── config.ex          # YAML config loading & validation
│   │   ├── envelope.ex        # Canonical event struct
│   │   ├── pipeline.ex        # GenServer: transforms + fan-out
│   │   ├── metrics.ex         # HTTP /metrics (JSON counters)
│   │   └── ipc/
│   │       ├── rust_host.ex   # GenServer managing Erlang Port to Rust
│   │       └── protocol.ex    # JSON encode/decode for IPC
│   ├── test/
│   │   ├── config_test.exs    # Config loading, validation, env-var tests
│   │   └── pipeline_test.exs  # Pipeline transform/fan-out tests
│   ├── mix.exs
│   └── config/
├── crates/connector_host/     # Rust binary
│   └── src/
│       ├── main.rs            # Tokio main loop; stdin/stdout IPC dispatch
│       ├── protocol.rs        # Serde types for IPC commands & events
│       ├── envelope.rs        # Canonical envelope (mirrors Elixir)
│       ├── connectors/
│       │   └── kafka.rs       # rskafka Kafka consumer
│       └── sinks/
│           └── log.rs         # Log sink (stderr via tracing)
├── configs/examples/          # Example YAML configs
├── docs/
│   ├── ARCHITECTURE.md        # Component overview, IPC protocol, design decisions
│   ├── CONFIG.md              # YAML schema reference
│   └── RUNBOOK.md             # Start, produce, consume, metrics, troubleshooting
├── tools/
│   ├── demo_producers/        # Scripts to publish test events
│   └── demo_consumers/        # Scripts to consume test events
├── Dockerfile                 # Multi-stage: Rust build → Elixir build → slim runtime
├── docker-compose.yml         # Redpanda + topic init + router service
└── setup_deps.sh              # Install system dependencies
```

---

## Tech Stack

| Layer | Language | Key Libraries |
|---|---|---|
| Router core | Elixir 1.16 / OTP 26 | plug_cowboy, jason, yaml_elixir |
| Connector host | Rust 1.77 (stable) | tokio, serde_json, rskafka, tracing, chrono, uuid |
| Message broker | Redpanda (Kafka-compatible) | |
| Container | Docker / docker compose | |

---

## IPC Protocol

Elixir sends **commands** to Rust on stdin; Rust sends **events** to Elixir on stdout. All messages are newline-terminated JSON.

**Commands (Elixir → Rust):**
| `type` | Purpose |
|---|---|
| `start_input` | Start a named connector (e.g., Kafka consumer) |
| `start_output` | Register a named sink |
| `send_output` | Route an envelope to a named sink |
| `shutdown` | Terminate the Rust process |

**Events (Rust → Elixir):**
| `type` | Purpose |
|---|---|
| `ingest` | New message received from a connector |
| `ack` | Sink successfully processed an envelope |
| `error` | Connector or sink error |

The canonical **Envelope** structure:
```json
{
  "id": "<uuid>",
  "source": "<input-name>",
  "payload": { ... },
  "metadata": { ... },
  "ts": "<ISO-8601 timestamp>"
}
```

---

## Configuration

Config files are YAML with environment variable interpolation using `${VAR:default}` syntax.

**Top-level keys:** `inputs`, `outputs`, `pipelines`

Example (`configs/examples/kafka_to_log.yaml`):
```yaml
inputs:
  - name: orders
    type: kafka
    brokers: "${KAFKA_BROKERS:localhost:9092}"
    topic: orders

outputs:
  - name: log_sink
    type: log

pipelines:
  - name: orders_to_log
    from: orders
    transforms:
      - type: add_fields
        fields:
          env: production
    to:
      - log_sink
```

**Validation rules:**
- All `from` and `to` refs must name a declared input/output
- `type` must be a recognised value (unknown types cause startup errors)
- Required fields are enforced at load time

**Key environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `ROUTER_CONFIG` | `configs/examples/kafka_to_log.yaml` | Path to YAML config |
| `KAFKA_BROKERS` | `localhost:9092` | Comma-separated broker addresses |
| `CONNECTOR_HOST_BIN` | `./bin/connector_host` | Path to compiled Rust binary |
| `METRICS_PORT` | `4000` | Port for HTTP metrics endpoint |

---

## Development Workflows

### Prerequisites

Install system dependencies:
```bash
./setup_deps.sh
```

Requires: Elixir 1.16+, Erlang/OTP 26+, Rust 1.77+ (stable), Docker + Compose.

### Local stack (recommended)

```bash
docker compose up --build -d
```

This starts Redpanda, creates topics, and runs the router. Metrics available at `http://localhost:4000/metrics`.

### Build manually

```bash
# Rust connector host
cd crates/connector_host
cargo build --release
# Binary: target/release/connector_host

# Elixir release
cd apps/router_core
mix deps.get
MIX_ENV=prod mix release
# Release: _build/prod/rel/router_core
```

### Running locally without Docker

```bash
export ROUTER_CONFIG=configs/examples/kafka_to_log.yaml
export KAFKA_BROKERS=localhost:9092
export CONNECTOR_HOST_BIN=./crates/connector_host/target/release/connector_host
cd apps/router_core && iex -S mix
```

---

## Testing

### Elixir tests

```bash
cd apps/router_core
mix test
```

Tests live in `test/`. Key test files:
- `config_test.exs` — config loading, env-var interpolation, validation errors
- `pipeline_test.exs` — transform application, fan-out behaviour

### Rust tests

```bash
cd crates/connector_host
cargo test
```

### Linting & formatting

```bash
# Elixir
cd apps/router_core
mix format --check-formatted   # check
mix format                     # fix

# Rust
cd crates/connector_host
cargo fmt --check              # check
cargo fmt                      # fix
cargo clippy -- -D warnings    # lint (warnings are errors)
```

All four checks run in CI. **Do not leave Clippy warnings or formatting violations.**

---

## CI/CD

`.github/workflows/ci.yml` — currently disabled (manual trigger only via `workflow_dispatch`). To enable, uncomment the `on:` triggers for push/PR.

When enabled, the pipeline runs:
1. **Rust job**: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
2. **Elixir job**: `mix format --check-formatted`, `mix test`

---

## Code Conventions

### Elixir

- **OTP patterns**: use GenServer for all stateful components; avoid raw processes
- **Modules**: every module has a `@moduledoc` string
- **Private functions**: use `defp`; keep public API minimal
- **Formatting**: enforced by `mix format` (Elixir defaults, see `.formatter.exs`)
- **Error handling**: use tagged tuples `{:ok, value}` / `{:error, reason}`; avoid throwing exceptions across module boundaries

### Rust

- **Async**: all I/O is async via Tokio; use `tokio::spawn` for concurrent tasks
- **Serialisation**: derive `serde::Serialize` / `serde::Deserialize` on protocol types
- **Logging**: use `tracing` macros (`info!`, `warn!`, `error!`); do not use `println!` for diagnostics
- **Error handling**: prefer explicit `match` or `?`; minimise `unwrap()` in production paths
- **Formatting/linting**: `cargo fmt` + `cargo clippy -- -D warnings` must pass

### General

- **Indentation**: 2 spaces (Elixir/YAML), 4 spaces (Rust) — enforced by `.editorconfig`
- **Line endings**: LF, UTF-8
- **No trailing whitespace**

---

## Adding a New Connector or Sink

1. **Rust side** — create `crates/connector_host/src/connectors/<name>.rs` (or `sinks/<name>.rs`) and register it in `main.rs`'s command dispatch.
2. **Protocol** — add any new command/event variants to `protocol.rs` (Rust) and `ipc/protocol.ex` (Elixir).
3. **Config validation** — add the new `type` string to the allowlist in `apps/router_core/lib/config.ex`.
4. **Tests** — add at least one ExUnit test covering the new config path.
5. **Docs** — update `docs/CONFIG.md` with the new input/output type schema.

---

## Known Limitations / Planned Work

The following are explicitly unimplemented (tracked as `TODO(CODEX)` comments in source):

- **MQTT connector** — stub config exists; Rust implementation missing
- **RabbitMQ connector** — config type recognised but not implemented
- **Database sinks** — Postgres, ClickHouse planned
- **Advanced transforms** — only `add_fields` is implemented; `filter`, `jmespath_extract`, `lua_script` planned
- **Config hot-reload** — inotify watcher not implemented
- **Prometheus metrics** — current `/metrics` is basic JSON; not Prometheus-compatible
- **Auth / TLS** — not implemented for any connector or sink
- **Backpressure / drop policies** — not implemented
- **Distributed / multi-node mode** — single-node only

---

## Metrics

`GET http://localhost:4000/metrics` returns:

```json
{
  "envelopes_ingested": 1024,
  "envelopes_emitted": 1020,
  "pipeline_errors": 4
}
```

Unknown routes return HTTP 404.

---

## Useful References

- `docs/ARCHITECTURE.md` — IPC design decisions, extension points
- `docs/CONFIG.md` — full YAML schema reference
- `docs/RUNBOOK.md` — operational commands, troubleshooting steps
