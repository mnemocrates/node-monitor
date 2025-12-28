#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

mounts=("/" "/sda-disk" "/nvme0n1-disk" "/nvme1n1-disk")

worst_status="OK"
worst_message="All monitored mounts healthy"

for m in "${mounts[@]}"; do
    if ! df_output=$(df -h "$m" 2>/dev/null | awk 'NR==2 {print $5}'); then
        worst_status="WARN"
        worst_message="Mount ${m} not found or not accessible"
        continue
    fi

    usage="${df_output%\%}"

    if (( usage > 90 )); then
        worst_status="CRIT"
        worst_message="Mount ${m} usage=${usage}% (>90%)"
        # CRIT is worst; no need to keep checking for severity, but continue to know others
    elif (( usage > 80 )) && [[ "$worst_status" != "CRIT" ]]; then
        worst_status="WARN"
        worst_message="Mount ${m} usage=${usage}% (>80%)"
    fi
done

echo "${worst_status}|${worst_message}"

case "$worst_status" in
    OK)   exit 0 ;;
    WARN) exit 1 ;;
    CRIT) exit 2 ;;
esac

