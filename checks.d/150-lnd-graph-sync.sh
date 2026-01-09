#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="090-lnd-graph-sync"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

if [[ -z "$info_json" ]]; then
    echo "WARN|Unable to query LND graph sync status"
    echo "{}"
    exit 1
fi

synced=$(echo "$info_json" | jq -r '.synced_to_graph // false')

# Get graph info for additional context
graph_info=$(lncli_safe describegraph 2>/dev/null || echo "{}")
num_nodes=$(echo "$graph_info" | jq -r '.nodes | length // 0')
num_channels=$(echo "$graph_info" | jq -r '.edges | length // 0')

metrics_json="{\"synced\": ${synced}, \"num_nodes\": ${num_nodes}, \"num_channels\": ${num_channels}}"

if [[ "$synced" == "true" ]]; then
    echo "OK|LND is synced to graph (${num_nodes} nodes, ${num_channels} channels)"
    echo "$metrics_json"
    exit 0
else
    # Check if unsync has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "WARN" "${LND_GRAPH_SYNC_GRACE}"; then
        echo "WARN|LND graph not fully synced for extended period (${num_nodes} nodes, ${num_channels} channels)"
        echo "$metrics_json"
        exit 1
    else
        # Within grace period - don't alert (OK status but informational)
        echo "OK|LND graph syncing in progress (${num_nodes} nodes, ${num_channels} channels)"
        echo "$metrics_json"
        exit 0
    fi
fi

