#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Check name for state tracking
CHECK_NAME="110-tor-circuit"

# Retry logic: attempt multiple times with backoff
attempt=0
success=false

while (( attempt < TOR_CHECK_RETRIES )); do
    ((attempt++))
    
    if "$CURL_BIN" --socks5-hostname "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" \
        --connect-timeout "${TOR_CHECK_TIMEOUT}" \
        --max-time "${TOR_CHECK_TIMEOUT}" \
        -s https://check.torproject.org >/dev/null 2>&1; then
        success=true
        break
    fi
    
    # If not last attempt, wait before retry
    if (( attempt < TOR_CHECK_RETRIES )); then
        sleep "${TOR_CHECK_RETRY_DELAY}"
    fi
done

# Build metrics
metrics_json="{\"attempts\": ${attempt}, \"success\": ${success}}"

if $success; then
    echo "OK|Tor circuits appear healthy (${attempt} attempt(s))"
    echo "$metrics_json"
    exit 0
else
    # Check if failure has persisted beyond threshold
    if check_failure_duration "$CHECK_NAME" "CRIT" "${TOR_FAILURE_CRIT_DURATION}"; then
        echo "CRIT|Tor circuit health critically degraded (${attempt} attempts, ${TOR_CHECK_TIMEOUT}s timeout)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Tor circuit health uncertain (${attempt} attempts, ${TOR_CHECK_TIMEOUT}s timeout, will escalate if persistent)"
        echo "$metrics_json"
        exit 1
    fi
fi

