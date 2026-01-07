#!/usr/bin/env bash
set -euo pipefail

message="$1"

# Load config
source /usr/local/node-monitor/config.sh

# Exit silently if ntfy is disabled
if [[ "${NTFY_ENABLED:-false}" != "true" ]]; then
    exit 0
fi

# Build curl command based on Tor setting
if [[ "${NTFY_USE_TOR:-false}" == "true" ]]; then
    curl_cmd=(curl --socks5-hostname 127.0.0.1:9050 -s -d "$message")
else
    curl_cmd=(curl -s -d "$message")
fi

# Add Authorization header if token is configured
if [[ -n "${NTFY_TOKEN:-}" ]]; then
    curl_cmd+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
fi

# Append the full URL (NTFY_TOPIC already contains it)
curl_cmd+=("${NTFY_TOPIC}")

# Execute
"${curl_cmd[@]}"