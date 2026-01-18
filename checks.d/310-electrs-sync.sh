#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="131-electrs-sync"

# Get electrs info (cached)
electrs_info=$(get_electrs_info_cached) || {
    echo "CRIT|Unable to query Electrs for sync status"
    echo "{}"
    exit 2
}

# Parse cached results
success=$(echo "$electrs_info" | jq -r '.success // false')
electrs_height=$(echo "$electrs_info" | jq -r '.height // 0')

if [[ "$success" != "true" ]]; then
    echo "CRIT|Unable to query Electrs for sync status"
    echo "{}"
    exit 2
fi

# Get Bitcoin Core height
core_height="$(bitcoin_cli getblockcount 2>/dev/null || echo 0)"

if [[ "$electrs_height" -eq 0 || "$core_height" -eq 0 ]]; then
    echo "WARN|Unable to determine Electrs/Core heights (electrs=${electrs_height}, core=${core_height})"
    echo "{\"electrs_height\":${electrs_height},\"core_height\":${core_height}}"
    exit 1
fi

# Calculate drift
drift=$(( core_height - electrs_height ))
abs_drift=${drift#-}  # absolute value

metrics_json="{\"electrs_height\": ${electrs_height}, \"core_height\": ${core_height}, \"drift\": ${drift}}"

# Check for negative drift (Electrs ahead of Core - should never happen)
if (( drift < 0 )); then
    echo "CRIT|Electrs ahead of Core by ${abs_drift} blocks (invalid state)"
    echo "$metrics_json"
    exit 2
fi

# Check positive drift (Electrs behind Core)
if (( drift > ELECTRS_DRIFT_CRIT )); then
    echo "CRIT|Electrs drift=${drift} blocks behind Core (threshold: ${ELECTRS_DRIFT_CRIT})"
    echo "$metrics_json"
    exit 2
elif (( drift > ELECTRS_DRIFT_WARN )); then
    echo "WARN|Electrs drift=${drift} blocks behind Core (threshold: ${ELECTRS_DRIFT_WARN})"
    echo "$metrics_json"
    exit 1
else
    echo "OK|Electrs in sync with Core (drift=${drift})"
    echo "$metrics_json"
    exit 0
fi
