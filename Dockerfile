# Argus — multi-stage Dockerfile
#
# Stage 1: Build Rust connector host
# Stage 2: Build Elixir release
# Stage 3: Minimal runtime image

# ---------------------------------------------------------------------------
# Stage 1 — Rust build
# ---------------------------------------------------------------------------
FROM rust:1.77-slim AS rust-build

WORKDIR /build/crates/connector_host
COPY crates/connector_host/Cargo.toml ./
COPY crates/connector_host/src ./src

RUN cargo build --release

# ---------------------------------------------------------------------------
# Stage 2 — Elixir build
# ---------------------------------------------------------------------------
FROM elixir:1.16-otp-26-slim AS elixir-build

ENV MIX_ENV=prod

WORKDIR /build/apps/router_core
COPY apps/router_core/mix.exs ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get

COPY apps/router_core .
RUN mix release

# ---------------------------------------------------------------------------
# Stage 3 — Runtime
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl ca-certificates libncurses6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=rust-build  /build/crates/connector_host/target/release/connector_host ./bin/connector_host
COPY --from=elixir-build /build/apps/router_core/_build/prod/rel/router_core ./
COPY configs/ ./configs/

ENV RELEASE_NODE=router@127.0.0.1
ENV CONNECTOR_HOST_BIN=/app/bin/connector_host

CMD ["./bin/router_core", "start"]
