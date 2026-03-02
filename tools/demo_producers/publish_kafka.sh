#!/usr/bin/env bash
# tools/demo_producers/publish_kafka.sh
#
# Publish a single test message to the input.events topic.
# Requires rpk (Redpanda CLI) to be available, or falls back to kcat.
#
# Usage:
#   KAFKA_BROKERS=localhost:9092 bash tools/demo_producers/publish_kafka.sh

set -euo pipefail

BROKERS="${KAFKA_BROKERS:-localhost:9092}"
TOPIC="input.events"
PAYLOAD='{"msg":"hello from argus","source":"demo","value":42}'

echo "Publishing to topic '${TOPIC}' on broker '${BROKERS}'..."
echo "${PAYLOAD}"

if command -v rpk &>/dev/null; then
  echo "${PAYLOAD}" | rpk topic produce "${TOPIC}" --brokers "${BROKERS}"
elif command -v kcat &>/dev/null; then
  echo "${PAYLOAD}" | kcat -b "${BROKERS}" -t "${TOPIC}" -P
elif command -v kafkacat &>/dev/null; then
  echo "${PAYLOAD}" | kafkacat -b "${BROKERS}" -t "${TOPIC}" -P
else
  echo "ERROR: Neither rpk, kcat, nor kafkacat found. Install one and retry." >&2
  exit 1
fi

echo "Message published."
