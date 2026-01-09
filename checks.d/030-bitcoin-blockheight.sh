#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Get local height
local_height="$("$BITCOIN_CLI" getblockcount 2>/dev/null || echo 0)"

if [[ "$local_height" -eq 0 ]]; then
    echo "WARN|Unable to determine local block height"
    echo "{\"local_height\":0}"
    exit 1
fi

# Parse external sources
IFS=',' read -ra SOURCES <<< "$BITCOIN_BLOCKHEIGHT_SOURCES"

# Try each source with retries
public_height=0
source_used=""

for source in "${SOURCES[@]}"; do
    attempt=0
    
    while (( attempt < BITCOIN_BLOCKHEIGHT_CHECK_RETRIES )); do
        ((attempt++))
        
        # Use Tor if configured
        if [[ "$BITCOIN_BLOCKHEIGHT_USE_TOR" == "true" ]]; then
            public_height=$(eval "$TOR_CURL" "$source" 2>/dev/null | grep -o '^[0-9]\+$' || echo 0)
        else
            public_height=$(curl -s --connect-timeout 10 --max-time 20 "$source" 2>/dev/null | grep -o '^[0-9]\+$' || echo 0)
        fi
        
        if [[ "$public_height" -gt 0 ]]; then
            source_used="$source"
            break 2  # Break out of both loops
        fi
        
        # If not last attempt, wait before retry
        if (( attempt < BITCOIN_BLOCKHEIGHT_CHECK_RETRIES )); then
            sleep 3
        fi
    done
done

# If all sources failed
if [[ "$public_height" -eq 0 ]]; then
    echo "WARN|Unable to query external block height sources"
    echo "{\"local_height\":${local_height},\"public_height\":0}"
    exit 1
fi

# Calculate drift
drift=$(( public_height - local_height ))
abs_drift=${drift#-}  # absolute value

metrics_json="{\"local_height\": ${local_height}, \"public_height\": ${public_height}, \"drift\": ${drift}, \"source\": \"${source_used}\"}"

# Check for negative drift (local ahead of public - unusual but possible)
if (( drift < -3 )); then
    echo "WARN|Bitcoin Core ahead of public sources by ${abs_drift} blocks (local: ${local_height}, public: ${public_height})"
    echo "$metrics_json"
    exit 1
fi

# Check positive drift (local behind public)
if (( drift > BITCOIN_BLOCKHEIGHT_DRIFT_CRIT )); then
    echo "CRIT|Bitcoin block height ${drift} blocks behind public (threshold: ${BITCOIN_BLOCKHEIGHT_DRIFT_CRIT})"
    echo "$metrics_json"
    exit 2
elif (( drift > BITCOIN_BLOCKHEIGHT_DRIFT_WARN )); then
    echo "WARN|Bitcoin block height ${drift} blocks behind public (threshold: ${BITCOIN_BLOCKHEIGHT_DRIFT_WARN})"
    echo "$metrics_json"
    exit 1
else
    echo "OK|Bitcoin block height in sync with public (drift=${drift})"
    echo "$metrics_json"
    exit 0
fi
