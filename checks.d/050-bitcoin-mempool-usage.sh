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
usage=$(echo "$mempool_info" | jq -r '.usage // 0')
maxmempool=$(echo "$mempool_info" | jq -r '.maxmempool // 300000000')  # default 300MB

# Calculate usage percentage
if [[ "$maxmempool" -gt 0 ]]; then
    usage_pct=$(( usage * 100 / maxmempool ))
else
    usage_pct=0
fi

# Format usage in MB for readability
usage_mb=$(echo "scale=2; $usage / 1048576" | bc -l)
maxmempool_mb=$(echo "scale=2; $maxmempool / 1048576" | bc -l)

# Check thresholds
if [[ "$usage_pct" -ge "${MEMPOOL_USAGE_CRIT_HIGH}" ]]; then
    echo "CRIT|Bitcoin mempool usage critical: ${usage_pct}% (${usage_mb}MB / ${maxmempool_mb}MB, threshold: ${MEMPOOL_USAGE_CRIT_HIGH}%)"
    echo "{\"usage\": ${usage}, \"maxmempool\": ${maxmempool}, \"usage_pct\": ${usage_pct}, \"usage_mb\": ${usage_mb}}"
    exit 2
elif [[ "$usage_pct" -ge "${MEMPOOL_USAGE_WARN_HIGH}" ]]; then
    echo "WARN|Bitcoin mempool usage high: ${usage_pct}% (${usage_mb}MB / ${maxmempool_mb}MB, threshold: ${MEMPOOL_USAGE_WARN_HIGH}%)"
    echo "{\"usage\": ${usage}, \"maxmempool\": ${maxmempool}, \"usage_pct\": ${usage_pct}, \"usage_mb\": ${usage_mb}}"
    exit 1
else
    echo "OK|Bitcoin mempool usage healthy: ${usage_pct}% (${usage_mb}MB / ${maxmempool_mb}MB)"
    echo "{\"usage\": ${usage}, \"maxmempool\": ${maxmempool}, \"usage_pct\": ${usage_pct}, \"usage_mb\": ${usage_mb}}"
    exit 0
fi
