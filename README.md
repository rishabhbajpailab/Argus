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

