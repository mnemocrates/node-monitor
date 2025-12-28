#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

if "$BITCOIN_CLI" getblockchaininfo >/dev/null 2>&1; then
    echo "OK|Bitcoin Core RPC reachable"
    exit 0
else
    echo "CRIT|Bitcoin Core RPC unreachable"
    exit 2
fi

