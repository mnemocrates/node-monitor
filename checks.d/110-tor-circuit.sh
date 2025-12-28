#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

if "$CURL_BIN" --socks5-hostname "${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT}" \
    -s https://check.torproject.org >/dev/null 2>&1; then
    echo "OK|Tor circuits appear healthy"
    exit 0
else
    echo "WARN|Tor circuit health uncertain (check tor logs/onions)"
    exit 1
fi

