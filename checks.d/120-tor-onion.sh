#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"
uris=$(echo "$info_json" | jq -r '.uris[]? // empty')

# If no URIs, treat as OK (matches your health-check behavior)
if [[ -z "$uris" ]]; then
    echo "OK|No LND onion URIs to test"
    exit 0
fi

fail_count=0
messages=()

for uri in $uris; do
    # Expect pubkey@host:port
    if [[ "$uri" != *@*:* ]]; then
        messages+=("INVALID $uri")
        ((fail_count++))
        continue
    fi

    onion="${uri#*@}"     # strip pubkey@
    host="${onion%%:*}"   # before :
    port="${onion##*:}"   # after :

    # Validate host/port
    if [[ -z "$host" || -z "$port" ]]; then
        messages+=("INVALID $uri")
        ((fail_count++))
        continue
    fi

    # Use nc over Tor SOCKS (correct for Lightning)
    if nc -x "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" -z "$host" "$port" >/dev/null 2>&1; then
        messages+=("OK ${host}:${port}")
    else
        messages+=("FAIL ${host}:${port}")
        ((fail_count++))
    fi
done

if (( fail_count == 0 )); then
    echo "OK|All LND onion URIs reachable via Tor"
    exit 0
elif (( fail_count == 1 )); then
    echo "WARN|One LND onion unreachable: ${messages[*]}"
    exit 1
else
    echo "CRIT|Multiple LND onions unreachable: ${messages[*]}"
    exit 2
fi

