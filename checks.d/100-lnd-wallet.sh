#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Retry logic: LND can be temporarily slow to respond
attempt=0
success=false

while (( attempt < LND_RPC_RETRIES )); do
    ((attempt++))
    
    if lncli_safe getinfo >/dev/null 2>&1; then
        success=true
        break
    fi
    
    # If not last attempt, wait before retry
    if (( attempt < LND_RPC_RETRIES )); then
        sleep "${LND_RPC_RETRY_DELAY}"
    fi
done

metrics_json="{\"responding\": ${success}, \"attempts\": ${attempt}}"

if $success; then
    echo "OK|LND wallet unlocked and reachable (${attempt} attempt(s))"
    echo "$metrics_json"
    exit 0
else
    echo "CRIT|LND wallet locked or LND unreachable (${attempt} attempts failed)"
    echo "$metrics_json"
    exit 2
fi

