# Argus — Runbook

## Starting the router

### docker-compose (recommended)

```bash
docker compose up --build -d
docker compose logs -f router
```

### Local (Elixir + Rust already installed)

```bash
# Build Rust binary
cd crates/connector_host && cargo build --release && cd ../..

# Start router
cd apps/router_core
CONNECTOR_HOST_BIN=../../crates/connector_host/target/release/connector_host \
KAFKA_BROKERS=localhost:9092 \
mix run --no-halt -- --config ../../configs/examples/kafka_to_log.yaml
```

---

## Producing a test message

```bash
bash tools/demo_producers/publish_kafka.sh
```

Publishes one JSON event to `input.events`.

---

## Consuming the output topic

```bash
bash tools/demo_consumers/consume_kafka.sh
```

---

## Checking metrics

```bash
curl http://localhost:4000/metrics
```

Returns JSON:
```json
{
  "envelopes_ingested": 42,
  "envelopes_emitted": 84,
  "pipeline_errors": 0
}
```

---

## Graceful shutdown

```bash
docker compose down          # stops all containers
# or locally: Ctrl+C / SIGTERM
```

The Elixir supervisor sends `{"cmd":"shutdown"}` to the Rust host before
terminating, allowing it to flush and close consumer group offsets.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `router` exits immediately | Config parse error | Check `ROUTER_CONFIG` path and YAML syntax |
| No messages consumed | Wrong broker address | Verify `KAFKA_BROKERS` env var |
| `redpanda-init` exits 1 | Broker not ready | Increase `depends_on` health retries |
| Rust host crash on startup | Missing binary | Run `cargo build --release` in `crates/connector_host` |

---

## Linting and formatting

### Rust
```bash
cd crates/connector_host
cargo fmt --check
cargo clippy -- -D warnings
```

### Elixir
```bash
cd apps/router_core
mix format --check-formatted
mix credo --strict
```

> **Issue:** Add `credo` to dev dependencies in mix.exs and enable `mix credo --strict` in CI.

---

## Running tests

```bash
# Elixir
cd apps/router_core && mix test

# Rust
cd crates/connector_host && cargo test
```
