#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

core_height="$(bitcoin_cli getblockcount 2>/dev/null || echo 0)"
lnd_height="$(lncli_safe getinfo 2>/dev/null | jq -r '.block_height // 0')"

if [[ "$core_height" -eq 0 || "$lnd_height" -eq 0 ]]; then
    echo "WARN|Unable to determine LND/Core block heights (core=${core_height}, lnd=${lnd_height})"
    echo "{\"core_height\":${core_height},\"lnd_height\":${lnd_height}}"
    exit 1
fi

drift=$(( core_height - lnd_height ))
abs_drift=${drift#-}  # absolute value

metrics_json="{\"core_height\": ${core_height}, \"lnd_height\": ${lnd_height}, \"drift\": ${drift}}"

# Check for negative drift (LND ahead of Core - should never happen)
if (( drift < 0 )); then
    echo "CRIT|LND block height ahead of Core (drift=${drift}) - invalid state"
    echo "$metrics_json"
    exit 2
fi

# Check positive drift (LND behind Core)
if (( drift <= 1 )); then
    echo "OK|LND block height in sync with Core (drift=${drift})"
    echo "$metrics_json"
    exit 0
elif (( drift <= LND_BLOCKHEIGHT_DRIFT_WARN )); then
    echo "WARN|LND block height drift=${drift} behind Core (threshold: ${LND_BLOCKHEIGHT_DRIFT_WARN})"
    echo "$metrics_json"
    exit 1
elif (( drift <= LND_BLOCKHEIGHT_DRIFT_CRIT )); then
    echo "CRIT|LND block height drift=${drift} behind Core (threshold: ${LND_BLOCKHEIGHT_DRIFT_CRIT})"
    echo "$metrics_json"
    exit 2
else
    echo "CRIT|LND block height significantly behind Core (drift=${drift})"
    echo "$metrics_json"
    exit 2
fi

