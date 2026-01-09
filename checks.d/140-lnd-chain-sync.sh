#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="080-lnd-chain-sync"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

if [[ -z "$info_json" ]]; then
    echo "CRIT|Unable to query LND chain sync status"
    echo "{}"
    exit 2
fi

synced=$(echo "$info_json" | jq -r '.synced_to_chain // false')
block_height=$(echo "$info_json" | jq -r '.block_height // 0')
block_hash=$(echo "$info_json" | jq -r '.block_hash // ""')

metrics_json="{\"synced\": ${synced}, \"block_height\": ${block_height}}"

if [[ "$synced" == "true" ]]; then
    echo "OK|LND is synced to chain (height: ${block_height})"
    echo "$metrics_json"
    exit 0
else
    # Check if unsync has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${LND_CHAIN_SYNC_GRACE}"; then
        echo "CRIT|LND NOT synced to chain persistently (height: ${block_height}, grace period exceeded)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|LND NOT synced to chain (height: ${block_height}, within grace period)"
        echo "$metrics_json"
        exit 1
    fi
fi

