#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

CHECK_NAME="920-external-electrs-connectivity"

# Verify connection method is available
if ! test_tor_connection; then
    echo "CRIT|Connection method not available (Tor required but not running)"
    echo "{}"
    exit 2
fi

# Check required config
if [[ -z "${NODE_ELECTRS_HOST}" ]]; then
    echo "WARN|NODE_ELECTRS_HOST not configured"
    echo "{}"
    exit 1
fi

# Test Electrs connectivity over Tor
attempt=0
success=false
response_time_ms=0
height=0

while (( attempt < EXT_RETRIES )); do
    attempt=$((attempt + 1))
    
    # Measure response time
    start_time=$(get_time_ms)
    
    # Try to query Electrs using server.ping
    electrs_response=$(printf '{"jsonrpc":"2.0","id":1,"method":"server.ping","params":[]}\n' \
        | smart_nc "${NODE_ELECTRS_HOST}" "${NODE_ELECTRS_PORT}" "${EXT_TIMEOUT}" \
        | head -n 1 || echo "")
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    # Check if we got a valid response
    if [[ -n "$electrs_response" ]] && echo "$electrs_response" | jq -e 'has("jsonrpc")' >/dev/null 2>&1; then
        success=true
        
        # Get block height for additional info
        height_response=$(printf '{"jsonrpc":"2.0","id":2,"method":"blockchain.headers.subscribe","params":[]}\n' \
            | smart_nc "${NODE_ELECTRS_HOST}" "${NODE_ELECTRS_PORT}" 5 \
            | head -n 1 || echo "")
        height=$(echo "$height_response" | jq -r '.result.height // 0' 2>/dev/null)
        
        break
    fi
    
    if (( attempt < EXT_RETRIES )); then
        sleep "${EXT_RETRY_DELAY}"
    fi
done

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"height\": ${height}}"

if ! $success; then
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "CRIT|Electrs not reachable via ${connection_type} (${NODE_ELECTRS_HOST})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "Electrs not reachable" "$metrics_json"
    
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: Electrs Unreachable" "Electrs is not reachable via ${connection_type} (${attempt} attempts)"
    fi
    exit 2
fi

# Check response time thresholds
if (( response_time_ms > ELECTRS_EXT_RESPONSE_TIME_CRIT )); then
    echo "CRIT|Electrs response critically slow: ${response_time_ms}ms (threshold: ${ELECTRS_EXT_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "Electrs critically slow: ${response_time_ms}ms" "$metrics_json"
    exit 2
elif (( response_time_ms > ELECTRS_EXT_RESPONSE_TIME_WARN )); then
    echo "WARN|Electrs response slow: ${response_time_ms}ms (threshold: ${ELECTRS_EXT_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "Electrs slow: ${response_time_ms}ms" "$metrics_json"
    exit 1
else
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "OK|Electrs reachable (${connection_type}): ${response_time_ms}ms (block ${height})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "OK" "Electrs reachable: ${response_time_ms}ms" "$metrics_json"
    exit 0
fi
