#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"
synced=$(echo "$info_json" | jq -r '.synced_to_chain // false')

if [[ "$synced" == "true" ]]; then
    echo "OK|LND is synced to chain"
    exit 0
else
    echo "CRIT|LND is NOT synced to chain"
    exit 2
fi

