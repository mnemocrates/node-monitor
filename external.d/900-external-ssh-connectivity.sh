#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

CHECK_NAME="900-external-ssh-connectivity"

# Verify connection method is available
if ! test_tor_connection; then
    echo "CRIT|Connection method not available (Tor required but not running)"
    echo "{}"
    exit 2
fi

# Check required config
if [[ -z "${NODE_SSH_HOST}" ]]; then
    echo "WARN|NODE_SSH_HOST not configured"
    echo "{}"
    exit 1
fi

# Test SSH connectivity over Tor
attempt=0
success=false
response_time_ms=0
ssh_banner=""

while (( attempt < EXT_RETRIES )); do
    attempt=$((attempt + 1))
    
    # Measure response time
    start_time=$(get_time_ms)
    
    # Try to connect and get SSH banner
    ssh_banner=$(echo "quit" | smart_nc "${NODE_SSH_HOST}" "${NODE_SSH_PORT}" "${EXT_TIMEOUT}" | head -n 1 || echo "")
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    # Check if we got an SSH banner
    if [[ "$ssh_banner" =~ ^SSH-[0-9] ]]; then
        success=true
        break
    fi
    
    if (( attempt < EXT_RETRIES )); then
        sleep "${EXT_RETRY_DELAY}"
    fi
done

# Extract SSH version from banner for metrics
ssh_version=""
if [[ "$ssh_banner" =~ ^SSH-([0-9.]+) ]]; then
    ssh_version="${BASH_REMATCH[1]}"
fi

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"ssh_version\": \"${ssh_version}\"}"

if ! $success; then
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "CRIT|Node SSH not reachable via ${connection_type} (${NODE_SSH_HOST})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "Node SSH not reachable" "$metrics_json"
    
    # Send alert if failure persists beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: Node Unreachable" "SSH service is not reachable via ${connection_type} (${attempt} attempts)"
    fi
    exit 2
fi

# Check response time thresholds
if (( response_time_ms > SSH_RESPONSE_TIME_CRIT )); then
    echo "CRIT|SSH response critically slow: ${response_time_ms}ms (threshold: ${SSH_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "SSH response critically slow: ${response_time_ms}ms" "$metrics_json"
    exit 2
elif (( response_time_ms > SSH_RESPONSE_TIME_WARN )); then
    echo "WARN|SSH response slow: ${response_time_ms}ms (threshold: ${SSH_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "SSH response slow: ${response_time_ms}ms" "$metrics_json"
    exit 1
else
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "OK|Node reachable via SSH (${connection_type}): ${response_time_ms}ms"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "OK" "Node reachable via SSH: ${response_time_ms}ms" "$metrics_json"
    exit 0
fi
