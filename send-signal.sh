#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/usr/local/node-monitor/config.sh
. "${SCRIPT_DIR}/config.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"message text\"" >&2
  exit 1
fi

MESSAGE="$1"

"${SIGNAL_CLI}" -u "${SIGNAL_FROM}" send -m "${MESSAGE}" "${SIGNAL_TO}"
