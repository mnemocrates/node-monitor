#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

channels=$(echo "$info_json" | jq -r '.num_active_channels // 0')

if (( channels >= 3 )); then
    echo "OK|LND active channels=${channels}"
    echo "{\"channels\":${channels}}"
    exit 0
elif (( channels >= 1 )); then
    echo "WARN|LND few active channels (channels=${channels})"
    echo "{\"channels\":${channels}}"
    exit 1
else
    echo "CRIT|LND has no active channels"
    echo "" #no additional metrics
    exit 2
fi

