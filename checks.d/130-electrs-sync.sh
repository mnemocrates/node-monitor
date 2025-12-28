#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Query electrs using the supported Electrum protocol method
electrs_json=$(printf '{"jsonrpc":"2.0","id":1,"method":"blockchain.headers.subscribe","params":[]}\n' \
    | nc -w 2 127.0.0.1 50001 2>/dev/null || echo "")

# If empty or invalid, fail
if [[ -z "$electrs_json" ]]; then
    echo "CRIT|Electrs did not respond on 127.0.0.1:50001"
    exit 2
fi

# Extract height
electrs_height=$(echo "$electrs_json" | jq -r '.result.height // 0')
core_height="$("$BITCOIN_CLI" getblockcount 2>/dev/null || echo 0)"

if [[ "$electrs_height" -eq 0 || "$core_height" -eq 0 ]]; then
    echo "WARN|Unable to determine Electrs/Core heights (electrs=${electrs_height}, core=${core_height})"
    exit 1
fi

drift=$(( core_height - electrs_height ))

if (( drift <= 1 )); then
    echo "OK|Electrs in sync with Core (drift=${drift})"
    exit 0
elif (( drift <= 3 )); then
    echo "WARN|Electrs drift=${drift} behind Core"
    exit 1
else
    echo "CRIT|Electrs drift=${drift} behind Core"
    exit 2
fi

