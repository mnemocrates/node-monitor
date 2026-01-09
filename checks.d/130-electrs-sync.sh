#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="130-electrs-sync"

# Retry logic with latency tracking
attempt=0
success=false
electrs_json=""
response_time_ms=0
server_version=""

while (( attempt < ELECTRS_RETRIES )); do
    ((attempt++))
    
    # Measure response time
    start_time=$(get_time_ms)  # milliseconds
    
    # Query electrs using blockchain.headers.subscribe
    electrs_json=$(printf '{"jsonrpc":"2.0","id":1,"method":"blockchain.headers.subscribe","params":[]\}\n' \
        | timeout "${ELECTRS_TIMEOUT}" nc -w "${ELECTRS_TIMEOUT}" "${ELECTRS_HOST}" "${ELECTRS_PORT}" 2>/dev/null || echo "")
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    # Check if we got a valid response
    if [[ -n "$electrs_json" ]] && echo "$electrs_json" | jq -e '.result' >/dev/null 2>&1; then
        success=true
        
        # Try to get server version for additional info
        server_version=$(printf '{"jsonrpc":"2.0","id":2,"method":"server.version","params":[]}\n' \
            | timeout 5 nc -w 5 "${ELECTRS_HOST}" "${ELECTRS_PORT}" 2>/dev/null \
            | jq -r '.result[0] // "unknown"' 2>/dev/null || echo "unknown")
        
        break
    fi
    
    # If not last attempt, wait before retry
    if (( attempt < ELECTRS_RETRIES )); then
        sleep "${ELECTRS_RETRY_DELAY}"
    fi
done

# If all retries failed
if ! $success; then
    metrics_json="{\"responding\": false, \"attempts\": ${attempt}}"
    
    # Check if failure has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ELECTRS_FAILURE_GRACE}"; then
        echo "CRIT|Electrs not responding on ${ELECTRS_HOST}:${ELECTRS_PORT} persistently (${attempt} attempts)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Electrs not responding on ${ELECTRS_HOST}:${ELECTRS_PORT} (${attempt} attempts, within grace period)"
        echo "$metrics_json"
        exit 1
    fi
fi

# Parse height from response
electrs_height=$(echo "$electrs_json" | jq -r '.result.height // 0')
core_height="$("$BITCOIN_CLI" getblockcount 2>/dev/null || echo 0)"

if [[ "$electrs_height" -eq 0 || "$core_height" -eq 0 ]]; then
    echo "WARN|Unable to determine Electrs/Core heights (electrs=${electrs_height}, core=${core_height})"
    echo "{\"electrs_height\":${electrs_height},\"core_height\":${core_height},\"response_time_ms\":${response_time_ms}}"
    exit 1
fi

# Calculate drift
drift=$(( core_height - electrs_height ))
abs_drift=${drift#-}  # absolute value

# Build metrics JSON
metrics_json="{\"electrs_height\": ${electrs_height}, \"core_height\": ${core_height}, \"drift\": ${drift}, \"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"server_version\": \"${server_version}\"}"

# Initialize issues array
issues=()
severity="OK"

# Check for negative drift (Electrs ahead of Core - should never happen)
if (( drift < 0 )); then
    issues+=("Electrs ahead of Core by ${abs_drift} blocks (invalid state)")
    severity="CRIT"
fi

# Check positive drift (Electrs behind Core)
if (( drift > ELECTRS_DRIFT_CRIT )); then
    issues+=("drift=${drift} blocks (threshold: ${ELECTRS_DRIFT_CRIT})")
    severity="CRIT"
elif (( drift > ELECTRS_DRIFT_WARN )); then
    if [[ "$severity" != "CRIT" ]]; then
        severity="WARN"
    fi
    issues+=("drift=${drift} blocks (threshold: ${ELECTRS_DRIFT_WARN})")
fi

# Check response time
if (( response_time_ms > ELECTRS_RESPONSE_TIME_CRIT )); then
    if [[ "$severity" != "CRIT" ]]; then
        severity="CRIT"
    fi
    issues+=("slow response ${response_time_ms}ms (threshold: ${ELECTRS_RESPONSE_TIME_CRIT}ms)")
elif (( response_time_ms > ELECTRS_RESPONSE_TIME_WARN )); then
    if [[ "$severity" != "CRIT" ]]; then
        severity="WARN"
    fi
    issues+=("slow response ${response_time_ms}ms (threshold: ${ELECTRS_RESPONSE_TIME_WARN}ms)")
fi

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    message="Electrs healthy: in sync (drift=${drift}, ${response_time_ms}ms, v${server_version})"
else
    issue_str=$(IFS=', '; echo "${issues[*]}")
    message="Electrs issues: ${issue_str}"
fi

echo "${severity}|${message}"
echo "$metrics_json"

if [[ "$severity" == "CRIT" ]]; then
    exit 2
elif [[ "$severity" == "WARN" ]]; then
    exit 1
else
    exit 0
fi

