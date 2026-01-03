#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECKS_DIR="${SCRIPT_DIR}/checks.d"
STATE_DIR="${SCRIPT_DIR}/state/check-status"

mkdir -p "${STATE_DIR}"

for check_script in "${CHECKS_DIR}"/*.sh; do
    check_name="$(basename "$check_script")"

    # Strip .sh extension if present
    check_name="${check_name%.sh}"
    
    # Run check and capture output + exit code
    output="$("$check_script" 2>&1 || true)"
    exit_code=$?

    # Split output into first line (status|message) and second line (metrics JSON)
    first_line="$(echo "$output" | head -n1)"
    second_line="$(echo "$output" | sed -n '2p')"

    status="${first_line%%|*}"
    message="${first_line#*|}"

    # Normalize status from exit code if needed
    case "$exit_code" in
        0) norm_status="OK" ;;
        1) norm_status="WARN" ;;
        2) norm_status="CRIT" ;;
        *) norm_status="CRIT" ;;
    esac

    case "$status" in
        OK|WARN|CRIT) ;; # keep
        *) status="$norm_status" ;;
    esac

    # Print console output (unchanged)
    echo "${status}: ${check_name} - ${message}"

    # Read previous JSON state
    json_file="${STATE_DIR}/${check_name}.json"
    prev_status="UNKNOWN"
    if [[ -f "$json_file" ]]; then
        prev_status="$(jq -r '.status' "$json_file" 2>/dev/null || echo "UNKNOWN")"
    fi

    # Alerting logic (unchanged)
    if [[ "$status" == "OK" ]]; then
        if [[ "$prev_status" == "WARN" || "$prev_status" == "CRIT" ]]; then
            send_alert "Recovery: ${check_name}" "${check_name} is now OK on ${NODE_NAME}: ${message}"
        fi
    else
        if [[ "$prev_status" != "$status" ]]; then
            send_alert "${status}: ${check_name}" "${check_name} status is ${status} on ${NODE_NAME}: ${message}"
        fi
    fi

    # Write JSON state file
    write_json_state "$check_name" "$status" "$message" "$second_line"

done