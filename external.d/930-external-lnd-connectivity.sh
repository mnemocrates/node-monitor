#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

CHECK_NAME="930-external-lnd-connectivity"

# Verify connection method is available
if ! test_tor_connection; then
    echo "CRIT|Connection method not available (Tor required but not running)"
    echo "{}"
    exit 2
fi

# Check required config
if [[ -z "${NODE_LND_HOST}" ]]; then
    echo "WARN|LND host not configured"
    echo "{}"
    exit 1
fi

# Default to P2P port 9735 if not specified
LND_P2P_PORT="${NODE_LND_P2P_PORT:-9735}"

# Test LND P2P connectivity over Tor (no credentials needed)
attempt=0
success=false
response_time_ms=0

while (( attempt < EXT_RETRIES )); do
    attempt=$((attempt + 1))
    
    # Measure response time
    start_time=$(get_time_ms)
    
    # Try to connect to LND P2P port (simple TCP check)
    if echo "" | smart_nc "${NODE_LND_HOST}" "${LND_P2P_PORT}" 5 >/dev/null 2>&1; then
        end_time=$(get_time_ms)
        response_time_ms=$((end_time - start_time))
        success=true
        break
    fi
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    if (( attempt < EXT_RETRIES )); then
        sleep "${EXT_RETRY_DELAY}"
    fi
done

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"port\": ${LND_P2P_PORT}}"

if ! $success; then
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "CRIT|LND P2P not reachable via ${connection_type} (${NODE_LND_HOST}:${LND_P2P_PORT})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "LND P2P not reachable" "$metrics_json"
    
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: LND Unreachable" "LND P2P on ${NODE_LND_HOST}:${LND_P2P_PORT} is not reachable via ${connection_type} (${attempt} attempts)"
    fi
    exit 2
fi

# Check response time thresholds
if (( response_time_ms > LND_RESPONSE_TIME_CRIT )); then
    echo "CRIT|LND P2P response critically slow: ${response_time_ms}ms (threshold: ${LND_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "LND P2P critically slow: ${response_time_ms}ms" "$metrics_json"
    exit 2
elif (( response_time_ms > LND_RESPONSE_TIME_WARN )); then
    echo "WARN|LND P2P response slow: ${response_time_ms}ms (threshold: ${LND_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "LND P2P slow: ${response_time_ms}ms" "$metrics_json"
    exit 1
else
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "OK|LND P2P reachable (${connection_type}): ${response_time_ms}ms"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "OK" "LND P2P reachable: ${response_time_ms}ms" "$metrics_json"
    exit 0
fi
