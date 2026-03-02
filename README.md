# Argus — Event Router

Argus consolidates events from multiple brokers and fans them out to multiple
sinks, driven by declarative YAML configuration.

* **Core**: Elixir supervision tree (`apps/router_core`) — config loader,
  pipeline engine, metrics endpoint.
* **Connector host**: Rust binary (`crates/connector_host`) — broker/sink
  clients.  Elixir spawns it as a supervised child and communicates via
  line-delimited JSON over stdio.

---

## Prerequisites

### Option A — Docker only (recommended for quick start)

* Docker ≥ 24 and Docker Compose v2

### Option B — Local toolchain

* Elixir ≥ 1.16 / OTP 26
* Rust ≥ 1.77 (stable)
* Running Redpanda/Kafka broker

---

## Dependencies

### Quick setup (recommended)

Run the provided setup script to install all system, Elixir, and Rust
dependencies automatically.  It detects your OS and uses the right package
manager:

```bash
bash setup_deps.sh
```

Supported package managers: **apt-get** (Debian/Ubuntu), **dnf**
(Fedora/RHEL/CentOS), **zypper** (openSUSE), **xbps** (Void Linux).

---

### System dependencies

These packages must be present before building either the Rust or Elixir
components.

| Package | Purpose |
|---------|---------|
| `git` | Source control |
| `curl` | Download Rustup installer |
| `gcc` / `build-essential` | C compiler required by some Rust transitive deps (lz4, zstd) |
| `make` | Build tool for native extensions |
| `libssl-dev` / `openssl-devel` | TLS support (used at runtime and by some crates) |
| `erlang` / `erlang-base` | Erlang/OTP runtime (≥ OTP 26) — Elixir runs on the BEAM |
| `elixir` | Elixir language toolchain (≥ 1.16) |

> **Note:** Rust itself is installed via [rustup](https://rustup.rs/) rather
> than a system package, so that you always get the latest stable toolchain.

---

### Rust crate dependencies

Defined in [`crates/connector_host/Cargo.toml`](crates/connector_host/Cargo.toml).
Run `cargo fetch` (or `cargo build`) to download them.

| Crate | Version | Purpose |
|-------|---------|---------|
| `serde` | 1.0 | Serialization framework |
| `serde_json` | 1.0 | JSON encode/decode for IPC protocol |
| `tokio` | 1.36 | Async runtime (full feature set) |
| `chrono` | 0.4 | Timestamp handling in envelopes |
| `rskafka` | 0.5 | Pure-Rust Kafka client (consumer + producer) |
| `tracing` | 0.1 | Structured logging / diagnostics |
| `tracing-subscriber` | 0.3 | Log subscriber with env-filter support |
| `uuid` | 1.7 | Envelope ID generation (v4 random) |

Dev-only:

| Crate | Version | Purpose |
|-------|---------|---------|
| `tokio-test` | 0.4 | Async test utilities |

---

### Elixir package dependencies

Defined in [`apps/router_core/mix.exs`](apps/router_core/mix.exs).
Run `mix deps.get` inside `apps/router_core/` to download them.

| Package | Version | Purpose |
|---------|---------|---------|
| `yaml_elixir` | ~> 2.9 | YAML configuration file parsing |
| `plug_cowboy` | ~> 2.7 | HTTP server for the `/metrics` endpoint |
| `jason` | ~> 1.4 | Fast JSON encode/decode (IPC protocol + metrics) |

---

## Quick start with docker-compose

```bash
# 1. Start Redpanda + router
docker compose up --build -d

# 2. Wait ~10 s for Redpanda to be ready, then publish a test message
bash tools/demo_producers/publish_kafka.sh

# 3. Watch router logs
docker compose logs -f router

# 4. Consume the output topic
bash tools/demo_consumers/consume_kafka.sh
```

---

## Running locally (without Docker)

```bash
# Build the Rust connector host
cd crates/connector_host
cargo build --release
cd ../..

# Start Redpanda (or any Kafka-compatible broker) separately, then:
cd apps/router_core
mix deps.get
mix run --no-halt -- --config ../../configs/examples/kafka_to_log.yaml
```

---

## Publishing a test message

```bash
bash tools/demo_producers/publish_kafka.sh
```

This publishes one JSON message to the `input.events` Kafka topic.

---

## Observing the router

### Router logs (docker-compose)
```bash
docker compose logs -f router
```

### Output topic messages
```bash
bash tools/demo_consumers/consume_kafka.sh
```

### Metrics endpoint
```
GET http://localhost:4000/metrics
```
Returns a JSON object with ingested/emitted counters.

---

## Configuration

See [`docs/CONFIG.md`](docs/CONFIG.md) for the full schema reference.
Example configs live in [`configs/examples/`](configs/examples/).

---

## Roadmap

* MQTT / RabbitMQ connectors
* Database sinks (Postgres, ClickHouse)
* Richer transforms (JSONPath field mapping, filtering, enrichment)
* Config hot-reload (inotify / fswatch)
* Auth / TLS for all connectors
* Backpressure & drop policies
* Prometheus `/metrics` scrape endpoint
* Distributed mode (multi-node Elixir cluster)

