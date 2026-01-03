#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

if "$CURL_BIN" --socks5-hostname "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" \
    -s https://check.torproject.org >/dev/null 2>&1; then
    echo "OK|Tor SOCKS reachable and circuits working"
    echo "" #no additional metrics
    exit 0
else
    echo "CRIT|Tor SOCKS unreachable or circuits failing"
    echo "" #no additional metrics
    exit 2
fi

