#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="300-electrs-connectivity"

# Get electrs info (cached)
electrs_info=$(get_electrs_info_cached) || electrs_info='{"success": false}'

# Parse cached results
success=$(echo "$electrs_info" | jq -r '.success // false')
attempts=$(echo "$electrs_info" | jq -r '.attempts // 0')
response_time_ms=$(echo "$electrs_info" | jq -r '.response_time_ms // 0')
server_version=$(echo "$electrs_info" | jq -r '.server_version // "unknown"')

metrics_json="{\"responding\": ${success}, \"attempts\": ${attempts}, \"response_time_ms\": ${response_time_ms}, \"server_version\": \"${server_version}\"}"

if [[ "$success" == "true" ]]; then
    echo "OK|Electrs responding (${response_time_ms}ms, ${attempts} attempt(s), ${server_version})"
    echo "$metrics_json"
    exit 0
else
    # Check if failure has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ELECTRS_FAILURE_GRACE}"; then
        echo "CRIT|Electrs not responding on ${ELECTRS_HOST}:${ELECTRS_PORT} persistently (${attempts} attempts)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Electrs not responding on ${ELECTRS_HOST}:${ELECTRS_PORT} (${attempts} attempts, within grace period)"
        echo "$metrics_json"
        exit 1
    fi
fi
