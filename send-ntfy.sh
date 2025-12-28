#!/usr/bin/env bash
set -euo pipefail

message="$1"

source /usr/local/node-monitor/config.sh

if [ "${NTFY_ENABLED:-false}" != "true" ]; then
    exit 0
fi

if [ -n "${NTFY_TOKEN:-}" ]; then
    curl -s -H "Authorization: Bearer ${NTFY_TOKEN}" \
         -d "${message}" \
         "${NTFY_TOPIC}"
else
    curl -s -d "${message}" "${NTFY_TOPIC}"
fi
