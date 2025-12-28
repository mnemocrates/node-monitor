#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

if lncli_safe getinfo >/dev/null 2>&1; then
    echo "OK|LND wallet unlocked and reachable"
    exit 0
else
    echo "CRIT|LND wallet locked or LND unreachable"
    exit 2
fi

