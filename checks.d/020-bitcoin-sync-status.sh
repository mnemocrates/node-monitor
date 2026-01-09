#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECK_NAME="020-bitcoin-sync-status"

# Get blockchain info
blockchain_info="$("$BITCOIN_CLI" getblockchaininfo 2>/dev/null)" || {
    echo "CRIT|Unable to query Bitcoin Core blockchain info"
    echo "{}"
    exit 2
}

# Parse sync status
initialblockdownload=$(echo "$blockchain_info" | jq -r '.initialblockdownload // false')
verificationprogress=$(echo "$blockchain_info" | jq -r '.verificationprogress // 0')
blocks=$(echo "$blockchain_info" | jq -r '.blocks // 0')
headers=$(echo "$blockchain_info" | jq -r '.headers // 0')
chain=$(echo "$blockchain_info" | jq -r '.chain // "unknown"')

# Calculate percentage
verification_pct=$(echo "scale=4; $verificationprogress * 100" | bc -l)

metrics_json="{\"initialblockdownload\": ${initialblockdownload}, \"verificationprogress\": ${verificationprogress}, \"verification_pct\": ${verification_pct}, \"blocks\": ${blocks}, \"headers\": ${headers}, \"chain\": \"${chain}\"}"

# Check if in initial block download
if [[ "$initialblockdownload" == "true" ]]; then
    # Check if failure has persisted beyond grace period
    if check_failure_duration "$CHECK_NAME" "CRIT" "${BITCOIN_RPC_FAILURE_GRACE}"; then
        echo "CRIT|Bitcoin Core in initial block download for extended period (${verification_pct}% complete, ${blocks}/${headers} blocks)"
        echo "$metrics_json"
        exit 2
    else
        echo "WARN|Bitcoin Core in initial block download (${verification_pct}% complete, ${blocks}/${headers} blocks)"
        echo "$metrics_json"
        exit 1
    fi
fi

# Check verification progress
if [[ "$(echo "$verificationprogress < $BITCOIN_VERIFICATION_PROGRESS_WARN" | bc -l)" -eq 1 ]]; then
    echo "WARN|Bitcoin Core verification progress low: ${verification_pct}% (${blocks}/${headers} blocks)"
    echo "$metrics_json"
    exit 1
fi

# Check if blocks behind headers (catching up)
headers_behind=$((headers - blocks))
if (( headers_behind > 10 )); then
    echo "WARN|Bitcoin Core catching up: ${headers_behind} blocks behind headers (${blocks}/${headers})"
    echo "$metrics_json"
    exit 1
fi

echo "OK|Bitcoin Core fully synced (${blocks} blocks, ${verification_pct}% verified, chain: ${chain})"
echo "$metrics_json"
exit 0
