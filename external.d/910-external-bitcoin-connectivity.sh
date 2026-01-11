#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

CHECK_NAME="910-external-bitcoin-connectivity"

# Verify connection method is available
if ! test_tor_connection; then
    echo "CRIT|Connection method not available (Tor required but not running)"
    echo "{}"
    exit 2
fi

# Check required config
if [[ -z "${NODE_BITCOIN_HOST}" ]] || [[ -z "${NODE_BITCOIN_RPC_USER}" ]] || [[ -z "${NODE_BITCOIN_RPC_PASS}" ]]; then
    echo "WARN|Bitcoin Core RPC not fully configured"
    echo "{}"
    exit 1
fi

# Test Bitcoin Core RPC over Tor
attempt=0
success=false
response_time_ms=0
block_count=0

while (( attempt < EXT_RETRIES )); do
    ((attempt++))
    
    # Measure response time
    start_time=$(get_time_ms)
    
    # Try to query blockchain info via RPC
    rpc_response=$(smart_curl "http://${NODE_BITCOIN_HOST}:${NODE_BITCOIN_PORT}/" \
        -u "${NODE_BITCOIN_RPC_USER}:${NODE_BITCOIN_RPC_PASS}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"1.0","id":"external-monitor","method":"getblockcount","params":[]}' \
        2>/dev/null || echo "")
    
    end_time=$(get_time_ms)
    response_time_ms=$((end_time - start_time))
    
    # Check if we got a valid response
    if [[ -n "$rpc_response" ]] && echo "$rpc_response" | jq -e '.result' >/dev/null 2>&1; then
        success=true
        block_count=$(echo "$rpc_response" | jq -r '.result')
        break
    fi
    
    if (( attempt < EXT_RETRIES )); then
        sleep "${EXT_RETRY_DELAY}"
    fi
done

metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"block_count\": ${block_count}}"

if ! $success; then
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "CRIT|Bitcoin Core RPC not reachable via ${connection_type} (${NODE_BITCOIN_HOST})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "Bitcoin Core RPC not reachable" "$metrics_json"
    
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: Bitcoin Core Unreachable" "Bitcoin Core RPC on ${NODE_BITCOIN_HOST} is not reachable via ${connection_type} (${attempt} attempts)"
    fi
    exit 2
fi

# Check response time thresholds
if (( response_time_ms > BITCOIN_RESPONSE_TIME_CRIT )); then
    echo "CRIT|Bitcoin RPC response critically slow: ${response_time_ms}ms (threshold: ${BITCOIN_RESPONSE_TIME_CRIT}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "Bitcoin RPC critically slow: ${response_time_ms}ms" "$metrics_json"
    exit 2
elif (( response_time_ms > BITCOIN_RESPONSE_TIME_WARN )); then
    echo "WARN|Bitcoin RPC response slow: ${response_time_ms}ms (threshold: ${BITCOIN_RESPONSE_TIME_WARN}ms)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "Bitcoin RPC slow: ${response_time_ms}ms" "$metrics_json"
    exit 1
else
    connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
    echo "OK|Bitcoin Core reachable (${connection_type}): ${response_time_ms}ms (block ${block_count})"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "OK" "Bitcoin Core reachable: ${response_time_ms}ms" "$metrics_json"
    exit 0
fi
