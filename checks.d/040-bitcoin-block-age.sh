#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Get blockchain info
blockchain_info="$(bitcoin_cli getblockchaininfo 2>/dev/null)" || {
    echo "WARN|Unable to query Bitcoin Core for block age"
    echo "{}"
    exit 1
}

# Get the timestamp of the most recent block
last_block_time=$(echo "$blockchain_info" | jq -r '.time // 0')
current_time=$(date +%s)

if [[ "$last_block_time" -eq 0 ]]; then
    echo "WARN|Unable to determine last block timestamp"
    echo "{}"
    exit 1
fi

# Calculate block age in seconds
block_age=$((current_time - last_block_time))

# Convert to human-readable format
if (( block_age >= 3600 )); then
    age_hours=$(echo "scale=1; $block_age / 3600" | bc -l)
    age_display="${age_hours}h"
elif (( block_age >= 60 )); then
    age_minutes=$(( block_age / 60 ))
    age_display="${age_minutes}m"
else
    age_display="${block_age}s"
fi

blocks=$(echo "$blockchain_info" | jq -r '.blocks // 0')

metrics_json="{\"block_age_seconds\": ${block_age}, \"last_block_time\": ${last_block_time}, \"blocks\": ${blocks}}"

# Check thresholds
if (( block_age > BITCOIN_BLOCK_AGE_CRIT )); then
    echo "CRIT|Last Bitcoin block received ${age_display} ago (threshold: $((BITCOIN_BLOCK_AGE_CRIT / 60))m) - possible network isolation"
    echo "$metrics_json"
    exit 2
elif (( block_age > BITCOIN_BLOCK_AGE_WARN )); then
    echo "WARN|Last Bitcoin block received ${age_display} ago (threshold: $((BITCOIN_BLOCK_AGE_WARN / 60))m)"
    echo "$metrics_json"
    exit 1
else
    echo "OK|Bitcoin block age healthy: ${age_display} ago (block ${blocks})"
    echo "$metrics_json"
    exit 0
fi
