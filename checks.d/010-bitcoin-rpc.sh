#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="010-bitcoin-rpc"

# Retry logic with latency tracking
attempt=0
success=false
latency_ms=0

while (( attempt < BITCOIN_RPC_RETRIES )); do
    attempt=$((attempt + 1))
    
    # Measure latency
    start_ms=$(get_time_ms)
    if bitcoin_cli getblockchaininfo >/dev/null 2>&1; then
        success=true
        end_ms=$(get_time_ms)
        latency_ms=$(( end_ms - start_ms ))
        break
    fi
    end_ms=$(get_time_ms)
    latency_ms=$(( end_ms - start_ms ))
    
    # If not last attempt, wait before retry
    if (( attempt < BITCOIN_RPC_RETRIES )); then
        sleep "${BITCOIN_RPC_RETRY_DELAY}"
    fi
done

metrics_json="{\"responding\": ${success}, \"latency_ms\": ${latency_ms}, \"attempts\": ${attempt}}"

if ! $success; then
    # Check if failure has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${BITCOIN_RPC_FAILURE_GRACE}"; then
        echo "CRIT|Bitcoin Core RPC unreachable persistently (${attempt} attempts)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Bitcoin Core RPC unreachable (${attempt} attempts, within grace period)"
        echo "$metrics_json"
        exit 1
    fi
fi

# RPC is responding - check latency
if (( latency_ms > BITCOIN_RPC_LATENCY_CRIT )); then
    echo "CRIT|Bitcoin Core RPC critically slow: ${latency_ms}ms (threshold: ${BITCOIN_RPC_LATENCY_CRIT}ms)"
    echo "$metrics_json"
    exit 2
elif (( latency_ms > BITCOIN_RPC_LATENCY_WARN )); then
    echo "WARN|Bitcoin Core RPC slow: ${latency_ms}ms (threshold: ${BITCOIN_RPC_LATENCY_WARN}ms)"
    echo "$metrics_json"
    exit 1
else
    echo "OK|Bitcoin Core RPC reachable (${latency_ms}ms, ${attempt} attempt(s))"
    echo "$metrics_json"
    exit 0
fi
