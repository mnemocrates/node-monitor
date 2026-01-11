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
if [[ -z "${NODE_LND_HOST}" ]] || [[ -z "${NODE_LND_MACAROON_HEX}" ]]; then
    echo "WARN|LND not fully configured (need host and macaroon)"
    echo "{}"
    exit 1
fi

# Test LND REST API over Tor
attempt=0
success=false
response_time_ms=0
lnd_version=""
num_peers=0

while (( attempt < EXT_RETRIES )); do
    ((attempt++))
    
    # Measure response time
    start_time=$(get_time_ms)
    
    # Try to query LND getinfo endpoint
    lnd_response=$(smart_curl "http://${NODE_LND_HOST}:${NODE_LND_REST_PORT}/v1/getinfo" \
        -H "Grpc-Metadata-macaroon: ${NODE_LND_MACAROON_HEX}" \
        2>/dev/null || echo "")
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    # Check if we got a valid response
    if [[ -n "$lnd_response" ]] && echo "$lnd_response" | jq -e '.identity_pubkey' >/dev/null 2>&1; then
        success=true
        lnd_version=$(echo "$lnd_response" | jq -r '.version // "unknown"')
        num_peers=$(echo "$lnd_response" | jq -r '.num_peers // 0')
        break
    fi
    
    if (( attempt < EXT_RETRIES )); then
        sleep "${EXT_RETRY_DELAY}"
    fi
done

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"num_peers\": ${num_peers}}"

if ! $success; then
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "CRIT|LND not reachable via ${connection_type} (${NODE_LND_HOST})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "LND not reachable" "$metrics_json"
    
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: LND Unreachable" "LND REST API on ${NODE_LND_HOST} is not reachable via ${connection_type} (${attempt} attempts)"
    fi
    exit 2
fi

# Check response time thresholds
if (( response_time_ms > LND_RESPONSE_TIME_CRIT )); then
    echo "CRIT|LND response critically slow: ${response_time_ms}ms (threshold: ${LND_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "LND critically slow: ${response_time_ms}ms" "$metrics_json"
    exit 2
elif (( response_time_ms > LND_RESPONSE_TIME_WARN )); then
    echo "WARN|LND response slow: ${response_time_ms}ms (threshold: ${LND_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "LND slow: ${response_time_ms}ms" "$metrics_json"
    exit 1
else
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "OK|LND reachable (${connection_type}): ${response_time_ms}ms (${lnd_version}, ${num_peers} peers)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "OK" "LND reachable: ${response_time_ms}ms" "$metrics_json"
    exit 0
fi
