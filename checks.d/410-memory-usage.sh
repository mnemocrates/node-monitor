#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Check if free command is available
if ! command -v free >/dev/null 2>&1; then
    echo "WARN|Memory monitoring unavailable (free command not found)"
    echo "{}"
    exit 1
fi

# Get memory info
mem_info=$(free -b | awk 'NR==2 {printf "%d %d %d", $2, $3, $7}')
read -r total_mem used_mem available_mem <<< "$mem_info"

# Calculate memory usage percentage (used - buffers/cache = actual used)
if [[ "$total_mem" -gt 0 ]]; then
    mem_used_pct=$(( (total_mem - available_mem) * 100 / total_mem ))
else
    echo "WARN|Unable to determine memory usage"
    echo "{}"
    exit 1
fi

# Get swap info
swap_info=$(free -b | awk 'NR==3 {printf "%d %d", $2, $3}')
read -r total_swap used_swap <<< "$swap_info"

swap_used_pct=0
if [[ "$total_swap" -gt 0 ]]; then
    swap_used_pct=$(( used_swap * 100 / total_swap ))
fi

# Convert to human-readable
mem_used_human=$(echo "scale=1; ($total_mem - $available_mem) / 1073741824" | bc -l)
mem_total_human=$(echo "scale=1; $total_mem / 1073741824" | bc -l)
mem_avail_human=$(echo "scale=1; $available_mem / 1073741824" | bc -l)

swap_used_human=$(echo "scale=1; $used_swap / 1073741824" | bc -l)
swap_total_human=$(echo "scale=1; $total_swap / 1073741824" | bc -l)

metrics_json="{\"memory\": {\"total_bytes\": ${total_mem}, \"used_bytes\": $((total_mem - available_mem)), \"available_bytes\": ${available_mem}, \"used_pct\": ${mem_used_pct}}, \"swap\": {\"total_bytes\": ${total_swap}, \"used_bytes\": ${used_swap}, \"used_pct\": ${swap_used_pct}}}"

issues=()
severity="OK"

# Check memory thresholds
if (( mem_used_pct >= MEMORY_CRIT_PCT )); then
    severity="CRIT"
    issues+=("RAM at ${mem_used_pct}% (${mem_used_human}G/${mem_total_human}G, threshold: ${MEMORY_CRIT_PCT}%)")
elif (( mem_used_pct >= MEMORY_WARN_PCT )); then
    severity="WARN"
    issues+=("RAM at ${mem_used_pct}% (${mem_used_human}G/${mem_total_human}G, threshold: ${MEMORY_WARN_PCT}%)")
fi

# Check swap thresholds (if swap is configured)
if [[ "$total_swap" -gt 0 ]]; then
    if (( swap_used_pct >= SWAP_CRIT_PCT )); then
        severity="CRIT"
        issues+=("Swap at ${swap_used_pct}% (${swap_used_human}G/${swap_total_human}G, threshold: ${SWAP_CRIT_PCT}%)")
    elif (( swap_used_pct >= SWAP_WARN_PCT )); then
        if [[ "$severity" != "CRIT" ]]; then
            severity="WARN"
        fi
        issues+=("Swap at ${swap_used_pct}% (${swap_used_human}G/${swap_total_human}G, threshold: ${SWAP_WARN_PCT}%)")
    fi
fi

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    if [[ "$total_swap" -gt 0 ]]; then
        message="Memory healthy: RAM ${mem_used_pct}% (${mem_avail_human}G available), Swap ${swap_used_pct}%"
    else
        message="Memory healthy: RAM ${mem_used_pct}% (${mem_avail_human}G available, no swap configured)"
    fi
else
    issue_str=$(IFS=', '; echo "${issues[*]}")
    message="Memory issues: ${issue_str}"
fi

echo "${severity}|${message}"
echo "$metrics_json"

if [[ "$severity" == "CRIT" ]]; then
    exit 2
elif [[ "$severity" == "WARN" ]]; then
    exit 1
else
    exit 0
fi
