#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Check name for state tracking
CHECK_NAME="120-tor-onion"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"
uris=$(echo "$info_json" | jq -r '.uris[]? // empty')

# If no URIs, treat as OK
if [[ -z "$uris" ]]; then
    echo "OK|No LND onion URIs to test"
    echo "{\"uris\": [], \"fail_count\": 0}"
    exit 0
fi

fail_count=0
total_count=0
messages=()
metrics_entries=()

for uri in $uris; do
    ((total_count++))
    
    # Expect pubkey@host:port
    if [[ "$uri" != *@*:* ]]; then
        messages+=("INVALID $uri")
        metrics_entries+=("{\"uri\": \"${uri}\", \"status\": \"INVALID\"}")
        ((fail_count++))
        continue
    fi

    onion="${uri#*@}"
    host="${onion%%:*}"
    port="${onion##*:}"

    if [[ -z "$host" || -z "$port" ]]; then
        messages+=("INVALID $uri")
        metrics_entries+=("{\"uri\": \"${onion}\", \"status\": \"INVALID\"}")
        ((fail_count++))
        continue
    fi

    # Retry connection attempts for this URI
    attempt=0
    success=false
    
    while (( attempt < TOR_CHECK_RETRIES )); do
        ((attempt++))
        
        if timeout "${TOR_CHECK_TIMEOUT}" nc -x "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" -z "$host" "$port" >/dev/null 2>&1; then
            success=true
            break
        fi
        
        # If not last attempt, wait before retry
        if (( attempt < TOR_CHECK_RETRIES )); then
            sleep "${TOR_CHECK_RETRY_DELAY}"
        fi
    done
    
    if $success; then
        messages+=("OK ${host}:${port}")
        metrics_entries+=("{\"uri\": \"${host}:${port}\", \"status\": \"OK\", \"attempts\": ${attempt}}")
    else
        messages+=("FAIL ${host}:${port}")
        metrics_entries+=("{\"uri\": \"${host}:${port}\", \"status\": \"FAIL\", \"attempts\": ${attempt}}")
        ((fail_count++))
    fi
done

# Build metrics JSON
metrics_json=$(printf '{"uris": [%s], "fail_count": %d, "total_count": %d}' "$(IFS=,; echo "${metrics_entries[*]}")" "$fail_count" "$total_count")

# Determine severity based on failure ratio
fail_ratio=$(( fail_count * 100 / total_count ))

# Output status + message
if (( fail_count == 0 )); then
    echo "OK|All LND onion URIs reachable via Tor"
    echo "$metrics_json"
    exit 0
elif (( fail_ratio < 50 )); then
    # Less than half failed - WARN only
    echo "WARN|Some LND onion URIs unreachable (${fail_count}/${total_count}): ${messages[*]}"
    echo "$metrics_json"
    exit 1
else
    # Majority failed - check if persistent before escalating to CRIT
    if check_failure_duration "$CHECK_NAME" "CRIT" "${TOR_FAILURE_CRIT_DURATION}"; then
        echo "CRIT|Most/all LND onions unreachable persistently (${fail_count}/${total_count}): ${messages[*]}"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Most/all LND onions unreachable (${fail_count}/${total_count}, will escalate if persistent): ${messages[*]}"
        echo "$metrics_json"
        exit 1
    fi
fi
