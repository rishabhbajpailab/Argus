#!/usr/bin/env bash
# tools/demo_consumers/consume_kafka.sh
#
# Consume messages from the output.events topic and print them.
# Requires rpk (Redpanda CLI) to be available, or falls back to kcat.
#
# Usage:
#   KAFKA_BROKERS=localhost:9092 bash tools/demo_consumers/consume_kafka.sh

set -euo pipefail

BROKERS="${KAFKA_BROKERS:-localhost:9092}"
TOPIC="output.events"

echo "Consuming from topic '${TOPIC}' on broker '${BROKERS}' (Ctrl+C to stop)..."

if command -v rpk &>/dev/null; then
  rpk topic consume "${TOPIC}" --brokers "${BROKERS}" --offset start
elif command -v kcat &>/dev/null; then
  kcat -b "${BROKERS}" -t "${TOPIC}" -C -o beginning
elif command -v kafkacat &>/dev/null; then
  kafkacat -b "${BROKERS}" -t "${TOPIC}" -C -o beginning
else
  echo "ERROR: Neither rpk, kcat, nor kafkacat found. Install one and retry." >&2
  exit 1
fi
