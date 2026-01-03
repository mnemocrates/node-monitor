#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Measure latency
start_ms=$(date +%s%3N)
if "$BITCOIN_CLI" getblockchaininfo >/dev/null 2>&1; then
    exit_code=0
else
    exit_code=2
fi
end_ms=$(date +%s%3N)

latency_ms=$(( end_ms - start_ms ))

if [[ $exit_code -eq 0 ]]; then
    echo "OK|Bitcoin Core RPC reachable (latency=${latency_ms}ms)"
    echo "{\"latency_ms\": ${latency_ms}}"
    exit 0
else
    echo "CRIT|Bitcoin Core RPC unreachable"
    echo "{\"latency_ms\": ${latency_ms}}"
    exit 2
fi
