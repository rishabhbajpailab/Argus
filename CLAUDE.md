# CLAUDE.md — Argus Event Router

This file provides guidance for AI assistants working in this repository.

---

## Project Overview

**Argus** is an open-source event router that consolidates messages from multiple brokers (e.g. Kafka) and fans them out to multiple sinks via declarative YAML configuration. It is a v0.1.0 early-stage project with a clear roadmap.

**Architecture**: Hybrid Elixir + Rust monorepo.
- **Elixir** (`apps/router_core`): OTP supervision tree, config loading, pipeline orchestration, metrics HTTP endpoint, IPC management.
- **Rust** (`crates/connector_host`): High-performance binary for all external I/O (Kafka consumer/producer, log sink). Communicates with Elixir via line-delimited JSON over stdin/stdout.

---

## Repository Layout

```
Argus/
├── apps/
│   └── router_core/          # Elixir OTP application
│       ├── lib/
│       │   ├── router_core.ex    # Application entry point
│       │   ├── supervisor.ex     # Top-level OTP supervisor
│       │   ├── config.ex         # YAML config loader & validator
│       │   ├── envelope.ex       # Canonical event struct
│       │   ├── pipeline.ex       # Per-pipeline GenServer
│       │   ├── metrics.ex        # Counters + HTTP endpoint (:4000/metrics)
│       │   └── ipc/
│       │       ├── protocol.ex   # Line-delimited JSON encode/decode
│       │       └── rust_host.ex  # Erlang Port manager for Rust binary
│       └── test/
│           ├── config_test.exs
│           ├── pipeline_test.exs
│           └── test_helper.exs
├── crates/
│   └── connector_host/       # Rust binary
│       └── src/
│           ├── main.rs           # Tokio async main; stdin/stdout IPC
│           ├── protocol.rs       # Serde types for IPC commands/events
│           ├── envelope.rs       # Event struct (mirrors Elixir)
│           ├── connectors/
│           │   └── kafka.rs      # Kafka consumer (rskafka)
│           └── sinks/
│               └── log.rs        # Structured log sink
├── configs/
│   └── examples/
│       ├── kafka_to_log.yaml     # Working demo config
│       └── mqtt_to_kafka.yaml    # Stub (MQTT not yet implemented)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONFIG.md
│   └── RUNBOOK.md
├── tools/
│   ├── demo_producers/publish_kafka.sh
│   └── demo_consumers/consume_kafka.sh
├── .github/workflows/ci.yml  # CI (currently disabled pending runner validation)
├── docker-compose.yml        # Local dev stack (Redpanda + router)
├── Dockerfile                # Multi-stage production build
├── setup_deps.sh             # OS-agnostic dependency installer
└── mix.exs / Cargo.toml     # Root manifests
```

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Orchestration language | Elixir | ~> 1.16 |
| Runtime | OTP/BEAM | 26 |
| I/O binary language | Rust | edition 2021 |
| Async runtime (Rust) | Tokio | 1.36 |
| Kafka client (Rust) | rskafka | 0.5 |
| Serialization | serde / serde_json | 1.0 |
| YAML parsing (Elixir) | yaml_elixir | 2.9 |
| HTTP server | plug_cowboy | 2.7 |
| JSON codec (Elixir) | jason | 1.4 |
| Broker (dev) | Redpanda | v23.3.13 |
| Container | Docker / Compose | v2 |

---

## Development Workflows

### Prerequisites

- Docker >= 24 + Docker Compose v2, **or**
- Elixir 1.16 + OTP 26 + Rust 1.77 installed locally

Auto-install dependencies (Debian, Fedora, openSUSE, Void Linux):
```bash
bash setup_deps.sh
```

### Docker (recommended for local dev)

```bash
docker compose up --build -d   # Start full stack (Redpanda + router)
docker compose logs -f router  # Follow router logs
docker compose down            # Tear down
```

### Local (without Docker)

```bash
# 1. Build Rust binary
cd crates/connector_host
cargo build --release
cd ../..

# 2. Run Elixir router (requires a Kafka broker already running)
cd apps/router_core
CONNECTOR_HOST_BIN=../../crates/connector_host/target/release/connector_host \
KAFKA_BROKERS=localhost:9092 \
mix run --no-halt -- --config ../../configs/examples/kafka_to_log.yaml
```

### Key Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ROUTER_CONFIG` | `configs/examples/kafka_to_log.yaml` | Path to YAML config |
| `CONNECTOR_HOST_BIN` | `./bin/connector_host` | Path to compiled Rust binary |
| `KAFKA_BROKERS` | `localhost:9092` | Comma-separated broker list |
| `METRICS_PORT` | `4000` | HTTP metrics port |

---

## Running Tests

### Elixir tests

```bash
cd apps/router_core
mix deps.get
mix test
```

- Uses ExUnit with `async: true` for parallelism.
- Config tests write temporary YAML to `/tmp`.
- Pipeline tests stub `RustHost` with a plain GenServer.

### Rust tests

```bash
cd crates/connector_host
cargo test
```

---

## Code Quality

### Elixir

```bash
cd apps/router_core
mix format --check-formatted   # Check formatting
mix format                     # Auto-format
```

### Rust

```bash
cd crates/connector_host
cargo fmt --check              # Check formatting
cargo fmt                      # Auto-format
cargo clippy -- -D warnings    # Lint (all warnings are errors)
```

---

## Key Conventions

### Elixir

- **OTP patterns**: `use Supervisor` for supervisor, `use GenServer` for workers; always implement `child_spec/1`.
- **Process naming**: via `Registry` — `{:via, Registry, {RouterCore.Registry, {ModuleName, name}}}`.
- **Return types**: Always use `{:ok, value} | {:error, reason}` tuples for fallible functions.
- **Logging**: `require Logger` at the top of each module; use `Logger.info/warning/error`.
- **Typespecs**: Add `@spec` to all public functions.
- **Testing**: `async: true` everywhere; stub external processes (RustHost) with simple GenServers.

### Rust

- **Async**: Use Tokio `#[tokio::main]`; all I/O is async/await.
- **Error handling**: Return `Result<T, E>`; use `.unwrap_or` / `?` operator; avoid panics in production paths.
- **Serialization**: Derive `serde::Serialize` / `Deserialize` on all IPC types.
- **Logging**: Use `tracing` macros (`info!`, `warn!`, `error!`) — not `println!`.
- **Concurrency**: `Arc<Mutex<_>>` for shared mutable state; `tokio::sync::mpsc` for event channels (1024-message buffer).
- **Module layout**: One connector per file under `connectors/`; one sink per file under `sinks/`.

### IPC Protocol

- **Format**: Line-delimited JSON — one message per line (`\n`-terminated).
- **Direction**: Elixir → Rust = commands; Rust → Elixir = events.
- **Envelope fields**: `id` (UUIDv4), `source` (string), `payload` (JSON object), `metadata` (map), `ts` (ISO 8601).
- Never add new IPC message types without updating both `ipc/protocol.ex` and `crates/connector_host/src/protocol.rs`.

### Configuration (YAML)

- Supports env-var interpolation with defaults: `${VAR:default_value}`.
- Validation is **fail-fast** at startup — invalid config exits immediately with a descriptive error.
- Top-level keys: `inputs`, `outputs`, `pipelines`.
- Each pipeline has `from` (input name), `to` (list of output names), optional `transforms`.
- Only `add_fields` transform is currently implemented.
- See `docs/CONFIG.md` for the full schema reference.

---

## Adding New Connectors or Sinks

### New Rust connector (input)

1. Create `crates/connector_host/src/connectors/<name>.rs`.
2. Implement an async function that reads from the source and sends `Event::Ingest` over the mpsc channel.
3. Register it in `connectors/mod.rs`.
4. Handle the new `StartInput { connector_type: "<name>", ... }` command in `main.rs`.

### New Rust sink (output)

1. Create `crates/connector_host/src/sinks/<name>.rs`.
2. Implement an `emit(envelope)` function (async).
3. Register it in `sinks/mod.rs`.
4. Handle the new `StartOutput { sink_type: "<name>", ... }` command in `main.rs`.

### New transform (Elixir)

1. Add a clause to `RouterCore.Pipeline.apply_transform/2` in `apps/router_core/lib/pipeline.ex`.
2. Add tests in `apps/router_core/test/pipeline_test.exs`.
3. Document the new transform in `docs/CONFIG.md`.

---

## Metrics

The router exposes a JSON metrics endpoint at `http://localhost:4000/metrics`:

```json
{
  "envelopes_ingested": 42,
  "envelopes_emitted": 42,
  "pipeline_errors": 0
}
```

Use `RouterCore.Metrics.inc(:counter_name)` to increment a counter. Define new counters as atoms in `metrics.ex`.

---

## Current Limitations and Roadmap

**Not yet implemented** (safe to add):
- MQTT connector (`configs/examples/mqtt_to_kafka.yaml` is a stub)
- RabbitMQ connector
- Database sinks (Postgres, ClickHouse)
- Advanced transforms: `filter`, `rename_fields`, JSONPath, Lua scripting
- Config hot-reload (no restart required)
- TLS / auth for Kafka
- Prometheus `/metrics` format (currently JSON only)
- Consumer group offset management (currently single-partition)
- Backpressure / drop policies
- Multi-node Elixir clustering

**CI**: `.github/workflows/ci.yml` is present but disabled (manual trigger only). To enable, uncomment the `on:` section after verifying runner capacity.

---

## Useful Commands Reference

```bash
# Docker full stack
docker compose up --build -d
docker compose logs -f router
docker compose down

# Publish a test Kafka message
bash tools/demo_producers/publish_kafka.sh

# Consume output topic
bash tools/demo_consumers/consume_kafka.sh

# Elixir: get deps, test, format
cd apps/router_core && mix deps.get && mix test && mix format --check-formatted

# Rust: build, test, lint, format
cd crates/connector_host && cargo build --release && cargo test && cargo clippy -- -D warnings && cargo fmt --check

# Check metrics
curl -s http://localhost:4000/metrics | jq .
```

---

## File Map for Common Tasks

| Task | Files to read/edit |
|------|--------------------|
| Add a transform | `apps/router_core/lib/pipeline.ex`, `docs/CONFIG.md`, `apps/router_core/test/pipeline_test.exs` |
| Add a connector (input) | `crates/connector_host/src/connectors/`, `crates/connector_host/src/main.rs`, `ipc/protocol.ex`, `protocol.rs` |
| Add a sink (output) | `crates/connector_host/src/sinks/`, `crates/connector_host/src/main.rs`, `ipc/protocol.ex`, `protocol.rs` |
| Change config schema | `apps/router_core/lib/config.ex`, `docs/CONFIG.md`, `apps/router_core/test/config_test.exs` |
| Add a metric counter | `apps/router_core/lib/metrics.ex` |
| Change IPC protocol | `apps/router_core/lib/ipc/protocol.ex`, `crates/connector_host/src/protocol.rs` |
| Change envelope schema | `apps/router_core/lib/envelope.ex`, `crates/connector_host/src/envelope.rs`, `ipc/protocol.ex`, `protocol.rs` |
| Update dependencies | `apps/router_core/mix.exs` (Elixir), `crates/connector_host/Cargo.toml` (Rust) |
