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
    state_file="${STATE_DIR}/${check_name}.status"

    # Run check and capture output + exit code
    output="$("$check_script" 2>&1 || true)"
    exit_code=$?

    # Default if script misbehaves
    status="CRIT"
    message="Check ${check_name} returned invalid format or crashed: ${output}"

    if [[ "$output" == *"|"* ]]; then
        status="${output%%|*}"
        message="${output#*|}"
    fi

    echo "${status}: ${check_name} - ${message}"

    # Normalize status from exit code if needed
    # 0=OK, 1=WARN, 2=CRIT
    case "$exit_code" in
        0) norm_status="OK" ;;
        1) norm_status="WARN" ;;
        2) norm_status="CRIT" ;;
        *) norm_status="CRIT" ;;
    esac

    # Prefer explicit status text if it matches known values
    case "$status" in
        OK|WARN|CRIT) ;; # keep as is
        *) status="$norm_status" ;;
    esac

    prev_status="UNKNOWN"
    if [[ -f "$state_file" ]]; then
        prev_status="$(cat "$state_file")"
    fi

    # Decide on alerting based on previous vs current
    if [[ "$status" == "OK" ]]; then
        if [[ "$prev_status" == "WARN" || "$prev_status" == "CRIT" ]]; then
            # Recovery
            echo "OK" > "$state_file"
            send_alert "Recovery: ${check_name}" "${check_name} is now OK on btc-node-01: ${message}"
        else
            # Staying OK: just record
            echo "OK" > "$state_file"
        fi
    else
        # WARN or CRIT
        if [[ "$prev_status" != "$status" ]]; then
            # New WARN/CRIT state: alert
            echo "$status" > "$state_file"
            send_alert "${status}: ${check_name}" "${check_name} status is ${status} on btc-node-01: ${message}"
        else
            # Same WARN/CRIT as last time: no spam, just keep state
            echo "$status" > "$state_file"
        fi
    fi
done

