#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"
synced=$(echo "$info_json" | jq -r '.synced_to_graph // false')

if [[ "$synced" == "true" ]]; then
    echo "OK|LND is synced to graph"
    exit 0
else
    echo "WARN|LND graph is not fully synced"
    exit 1
fi

