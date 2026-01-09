#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Auto-detect mount points if not configured
if [[ -z "${DISK_MOUNTS}" ]]; then
    # Get all mounted filesystems (excluding pseudo/temporary filesystems)
    mapfile -t mounts < <(df -h --output=target --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs 2>/dev/null | tail -n +2)
else
    # Use configured mount points
    read -ra mounts <<< "$DISK_MOUNTS"
fi

worst_status="OK"
worst_usage=0
issues=()
metrics_entries=()

for m in "${mounts[@]}"; do
    # Get disk usage
    if ! df_output=$(df -h "$m" 2>/dev/null | awk 'NR==2 {print $5,$4,$2}'); then
        # Mount missing or inaccessible
        metrics_entries+=("\"${m}\": {\"accessible\": false}")
        issues+=("mount ${m} inaccessible")
        if [[ "$worst_status" != "CRIT" ]]; then
            worst_status="WARN"
        fi
        continue
    fi
    
    read -r usage_str avail_str total_str <<< "$df_output"
    usage="${usage_str%\%}"   # strip %
    
    # Get inode usage if supported
    inode_usage="N/A"
    if df_inodes=$(df -i "$m" 2>/dev/null | awk 'NR==2 {print $5}'); then
        inode_usage="${df_inodes%\%}"
    fi
    
    # Track worst usage
    if (( usage > worst_usage )); then
        worst_usage=$usage
    fi
    
    # Check disk space thresholds
    if (( usage >= DISK_CRIT_PCT )); then
        worst_status="CRIT"
        issues+=("${m}: ${usage}% full (${avail_str} available)")
    elif (( usage >= DISK_WARN_PCT )); then
        if [[ "$worst_status" != "CRIT" ]]; then
            worst_status="WARN"
        fi
        issues+=("${m}: ${usage}% full (${avail_str} available)")
    fi
    
    # Check inode thresholds if available
    if [[ "$inode_usage" != "N/A" ]]; then
        if (( inode_usage >= DISK_INODE_CRIT_PCT )); then
            worst_status="CRIT"
            issues+=("${m}: ${inode_usage}% inodes used")
        elif (( inode_usage >= DISK_INODE_WARN_PCT )); then
            if [[ "$worst_status" != "CRIT" ]]; then
                worst_status="WARN"
            fi
            issues+=("${m}: ${inode_usage}% inodes used")
        fi
    fi
    
    # Build metrics entry
    if [[ "$inode_usage" != "N/A" ]]; then
        metrics_entries+=("\"${m}\": {\"usage_pct\": ${usage}, \"available\": \"${avail_str}\", \"total\": \"${total_str}\", \"inode_usage_pct\": ${inode_usage}}")
    else
        metrics_entries+=("\"${m}\": {\"usage_pct\": ${usage}, \"available\": \"${avail_str}\", \"total\": \"${total_str}\"}")
    fi
done

# Build metrics JSON
metrics_json=$(printf '{"mounts": {%s}, "worst_usage_pct": %d}' "$(IFS=,; echo "${metrics_entries[*]}")" "$worst_usage")

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    message="All disk mounts healthy (worst: ${worst_usage}%)"
else
    issue_str=$(IFS='; '; echo "${issues[*]}")
    message="Disk space issues: ${issue_str}"
fi

echo "${worst_status}|${message}"
echo "$metrics_json"

case "$worst_status" in
    OK)   exit 0 ;;
    WARN) exit 1 ;;
    CRIT) exit 2 ;;
esac
