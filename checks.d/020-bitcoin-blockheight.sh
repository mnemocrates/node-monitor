#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

local_height="$("$BITCOIN_CLI" getblockcount 2>/dev/null || echo 0)"
public_height="$(curl -s https://blockstream.info/api/blocks/tip/height 2>/dev/null || echo 0)"

if [[ "$local_height" -eq 0 || "$public_height" -eq 0 ]]; then
    echo "WARN|Unable to determine block heights (local=${local_height}, public=${public_height})"
    echo "{\"local_height\":${local_height},\"public_height\":${public_height}}"
    exit 1
fi

drift=$(( public_height - local_height ))

if (( drift <= 1 )); then
    echo "OK|Bitcoin block height in sync (drift=${drift})"
    echo "{\"drift\":${drift}}"
    exit 0
elif (( drift <= 3 )); then
    echo "WARN|Bitcoin block height drift=${drift} blocks behind public"
    echo "{\"drift\":${drift}}"
    exit 1
else
    echo "CRIT|Bitcoin block height drift=${drift} blocks behind public"
    echo "{\"drift\":${drift}}"
    exit 2
fi

