#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

core_height="$("$BITCOIN_CLI" getblockcount 2>/dev/null || echo 0)"
lnd_height="$(lncli_safe getinfo 2>/dev/null | jq -r '.block_height // 0')"

if [[ "$core_height" -eq 0 || "$lnd_height" -eq 0 ]]; then
    echo "WARN|Unable to determine LND/Core block heights (core=${core_height}, lnd=${lnd_height})"
    echo "{\"core_height\":${core_height},\"lnd_height\":${lnd_height}}"
    exit 1
fi

drift=$(( core_height - lnd_height ))

if (( drift <= 1 )); then
    echo "OK|LND block height in sync with Core (drift=${drift})"
    echo "{\"drift\":${drift}}"
    exit 0
elif (( drift <= 3 )); then
    echo "WARN|LND block height drift=${drift} behind Core"
    echo "{\"drift\":${drift}}"
    exit 1
else
    echo "CRIT|LND block height drift=${drift} behind Core"
    echo "{\"drift\":${drift}}"
    exit 2
fi

