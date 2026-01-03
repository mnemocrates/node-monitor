#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

mounts=("/" "/sda-disk" "/nvme0n1-disk" "/nvme1n1-disk")

worst_status="OK"
worst_message="All monitored mounts healthy"
worst_usage=0

metrics_entries=()

for m in "${mounts[@]}"; do
    # Extract usage percentage (e.g., "87%")
    if ! df_output=$(df -h "$m" 2>/dev/null | awk 'NR==2 {print $5}'); then
        # Mount missing or inaccessible
        metrics_entries+=("{\"mount\": \"${m}\", \"usage_pct\": null, \"status\": \"INACCESSIBLE\"}")
        if [[ "$worst_status" != "CRIT" ]]; then
            worst_status="WARN"
            worst_message="Mount ${m} not found or not accessible"
        fi
        continue
    fi

    usage="${df_output%\%}"   # strip %
    metrics_entries+=("{\"mount\": \"${m}\", \"usage_pct\": ${usage}}")

    # Track worst usage
    if (( usage > worst_usage )); then
        worst_usage=$usage
    fi

    # Severity logic
    if (( usage > 90 )); then
        worst_status="CRIT"
        worst_message="Mount ${m} usage=${usage}% (>90%)"
    elif (( usage > 80 )) && [[ "$worst_status" != "CRIT" ]]; then
        worst_status="WARN"
        worst_message="Mount ${m} usage=${usage}% (>80%)"
    fi
done

# Build metrics JSON
metrics_json=$(printf '{"mounts":[%s],"worst_usage_pct":%d}' "$(IFS=,; echo "${metrics_entries[*]}")" "$worst_usage")

# Output line 1 (human-readable)
echo "${worst_status}|${worst_message}"

# Output line 2 (machine-readable JSON)
echo "$metrics_json"

# Exit code based on worst status
case "$worst_status" in
    OK)   exit 0 ;;
    WARN) exit 1 ;;
    CRIT) exit 2 ;;
esac
