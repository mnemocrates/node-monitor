#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"
uris=$(echo "$info_json" | jq -r '.uris[]? // empty')

# If no URIs, treat as OK
if [[ -z "$uris" ]]; then
    echo "OK|No LND onion URIs to test"
    echo "{\"uris\": [], \"fail_count\": 0}"
    exit 0
fi

fail_count=0
messages=()
metrics_entries=()

for uri in $uris; do
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

    if nc -x "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" -z "$host" "$port" >/dev/null 2>&1; then
        messages+=("OK ${host}:${port}")
        metrics_entries+=("{\"uri\": \"${host}:${port}\", \"status\": \"OK\"}")
    else
        messages+=("FAIL ${host}:${port}")
        metrics_entries+=("{\"uri\": \"${host}:${port}\", \"status\": \"FAIL\"}")
        ((fail_count++))
    fi
done

# Build metrics JSON
metrics_json=$(printf '{"uris": [%s], "fail_count": %d}' "$(IFS=,; echo "${metrics_entries[*]}")" "$fail_count")

# Output status + message
if (( fail_count == 0 )); then
    echo "OK|All LND onion URIs reachable via Tor"
    echo "$metrics_json"
    exit 0
elif (( fail_count == 1 )); then
    echo "WARN|One LND onion unreachable: ${messages[*]}"
    echo "$metrics_json"
    exit 1
else
    echo "CRIT|Multiple LND onions unreachable: ${messages[*]}"
    echo "$metrics_json"
    exit 2
fi
