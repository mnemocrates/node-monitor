#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

peers=$(echo "$info_json" | jq -r '.num_peers // 0')

if (( peers >= 3 )); then
    echo "OK|LND peers=${peers}"
    exit 0
elif (( peers >= 1 )); then
    echo "WARN|LND peers low (peers=${peers})"
    exit 1
else
    echo "CRIT|LND has no peers"
    exit 2
fi

