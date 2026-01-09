#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Fetch mempool info (cached)
mempool_info="$(get_mempool_info_cached)" || {
    echo "CRIT|Unable to fetch mempool info from Bitcoin Core"
    echo "{}"
    exit 2
}

# Parse metrics
mempoolminfee=$(echo "$mempool_info" | jq -r '.mempoolminfee // 0')
minrelaytxfee=$(echo "$mempool_info" | jq -r '.minrelaytxfee // 0.00001')

# Calculate minfee multiplier
if [[ "$(echo "$minrelaytxfee > 0" | bc -l)" -eq 1 ]]; then
    minfee_multiplier=$(echo "scale=2; $mempoolminfee / $minrelaytxfee" | bc -l)
else
    minfee_multiplier=1
fi

# Check thresholds
if [[ "$(echo "$minfee_multiplier >= ${MEMPOOL_MINFEE_MULTIPLIER_CRIT}" | bc -l)" -eq 1 ]]; then
    echo "CRIT|Bitcoin mempool minimum fee critically elevated: ${minfee_multiplier}x (mempoolminfee=${mempoolminfee}, threshold: ${MEMPOOL_MINFEE_MULTIPLIER_CRIT}x)"
    echo "{\"mempoolminfee\": ${mempoolminfee}, \"minrelaytxfee\": ${minrelaytxfee}, \"minfee_multiplier\": ${minfee_multiplier}}"
    exit 2
elif [[ "$(echo "$minfee_multiplier >= ${MEMPOOL_MINFEE_MULTIPLIER_WARN}" | bc -l)" -eq 1 ]]; then
    echo "WARN|Bitcoin mempool minimum fee elevated: ${minfee_multiplier}x (mempoolminfee=${mempoolminfee}, threshold: ${MEMPOOL_MINFEE_MULTIPLIER_WARN}x)"
    echo "{\"mempoolminfee\": ${mempoolminfee}, \"minrelaytxfee\": ${minrelaytxfee}, \"minfee_multiplier\": ${minfee_multiplier}}"
    exit 1
else
    echo "OK|Bitcoin mempool minimum fee normal: ${minfee_multiplier}x (mempoolminfee=${mempoolminfee})"
    echo "{\"mempoolminfee\": ${mempoolminfee}, \"minrelaytxfee\": ${minrelaytxfee}, \"minfee_multiplier\": ${minfee_multiplier}}"
    exit 0
fi
