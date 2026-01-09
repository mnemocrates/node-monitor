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
unbroadcastcount=$(echo "$mempool_info" | jq -r '.unbroadcastcount // 0')
size=$(echo "$mempool_info" | jq -r '.size // 0')

# Check thresholds
if [[ "$unbroadcastcount" -ge "${MEMPOOL_UNBROADCAST_CRIT}" ]]; then
    echo "CRIT|Bitcoin mempool has ${unbroadcastcount} unbroadcast transactions (network propagation issue, threshold: ${MEMPOOL_UNBROADCAST_CRIT})"
    echo "{\"unbroadcastcount\": ${unbroadcastcount}, \"size\": ${size}}"
    exit 2
elif [[ "$unbroadcastcount" -ge "${MEMPOOL_UNBROADCAST_WARN}" ]]; then
    echo "WARN|Bitcoin mempool has ${unbroadcastcount} unbroadcast transactions (possible network issue, threshold: ${MEMPOOL_UNBROADCAST_WARN})"
    echo "{\"unbroadcastcount\": ${unbroadcastcount}, \"size\": ${size}}"
    exit 1
else
    echo "OK|Bitcoin mempool unbroadcast transactions normal: ${unbroadcastcount}"
    echo "{\"unbroadcastcount\": ${unbroadcastcount}, \"size\": ${size}}"
    exit 0
fi
