#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

stamp_file="${SCRIPT_DIR}/state/last-heartbeat"
today=$(date +%Y-%m-%d)

if [[ ! -f "$stamp_file" ]] || [[ "$(cat "$stamp_file")" != "$today" ]]; then
    echo "$today" > "$stamp_file"
    send_alert "Node Heartbeat" "btc-node-01 heartbeat: node is alive and checks are running"
fi

echo "OK|Heartbeat processed for ${today}"
exit 0

