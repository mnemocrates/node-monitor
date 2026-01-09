#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="132-electrs-performance"

# Get electrs info (cached)
electrs_info=$(get_electrs_info_cached) || {
    echo "WARN|Unable to query Electrs for performance metrics"
    echo "{}"
    exit 1
}

# Parse cached results
success=$(echo "$electrs_info" | jq -r '.success // false')
response_time_ms=$(echo "$electrs_info" | jq -r '.response_time_ms // 0')
attempts=$(echo "$electrs_info" | jq -r '.attempts // 0')

if [[ "$success" != "true" ]]; then
    echo "WARN|Unable to query Electrs for performance metrics"
    echo "{}"
    exit 1
fi

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempts}}"

# Check response time thresholds
if (( response_time_ms > ELECTRS_RESPONSE_TIME_CRIT )); then
    echo "CRIT|Electrs response critically slow: ${response_time_ms}ms (threshold: ${ELECTRS_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    exit 2
elif (( response_time_ms > ELECTRS_RESPONSE_TIME_WARN )); then
    echo "WARN|Electrs response slow: ${response_time_ms}ms (threshold: ${ELECTRS_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    exit 1
else
    echo "OK|Electrs performance healthy: ${response_time_ms}ms"
    echo "$metrics_json"
    exit 0
fi
