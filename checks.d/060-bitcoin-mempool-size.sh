#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Fetch mempool info (cached)
mempool_info="$(get_mempool_info_cached)" || {
    echo "CRIT|Unable to fetch mempool info from Bitcoin Core"
    echo "{}"
    exit 2
}

# Parse metrics
size=$(echo "$mempool_info" | jq -r '.size // 0')
unbroadcastcount=$(echo "$mempool_info" | jq -r '.unbroadcastcount // 0')

# Check thresholds
if [[ "$size" -le "${MEMPOOL_SIZE_CRIT_LOW}" && "$unbroadcastcount" -gt 0 ]]; then
    echo "CRIT|Bitcoin mempool empty with ${unbroadcastcount} unbroadcast transactions (possible network isolation)"
    echo "{\"size\": ${size}, \"unbroadcastcount\": ${unbroadcastcount}}"
    exit 2
elif [[ "$size" -le "${MEMPOOL_SIZE_WARN_LOW}" ]]; then
    echo "WARN|Bitcoin mempool size low: ${size} transactions (possible low connectivity, threshold: ${MEMPOOL_SIZE_WARN_LOW})"
    echo "{\"size\": ${size}, \"unbroadcastcount\": ${unbroadcastcount}}"
    exit 1
else
    echo "OK|Bitcoin mempool size healthy: ${size} transactions"
    echo "{\"size\": ${size}, \"unbroadcastcount\": ${unbroadcastcount}}"
    exit 0
fi
