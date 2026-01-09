#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

CHECKS_DIR="${SCRIPT_DIR}/checks.d"
LOCAL_CHECKS_DIR="${SCRIPT_DIR}/local.d"
CHECK_STATUS_DIR="${STATE_DIR}/check-status"

mkdir -p "${CHECK_STATUS_DIR}"

# Collect all check scripts from both directories and sort them numerically
all_checks=()
if [[ -d "${CHECKS_DIR}" ]]; then
    while IFS= read -r -d $'\0' check; do
        all_checks+=("$check")
    done < <(find "${CHECKS_DIR}" -maxdepth 1 -name "*.sh" -type f -print0 2>/dev/null)
fi

if [[ -d "${LOCAL_CHECKS_DIR}" ]]; then
    while IFS= read -r -d $'\0' check; do
        all_checks+=("$check")
    done < <(find "${LOCAL_CHECKS_DIR}" -maxdepth 1 -name "*.sh" -type f -print0 2>/dev/null)
fi

# Sort checks numerically by filename
IFS=$'\n' sorted_checks=($(sort -t/ -k2 -V <<<"${all_checks[*]}"))
unset IFS

for check_script in "${sorted_checks[@]}"; do
    check_name="$(basename "$check_script")"

    # Strip .sh extension if present
    check_name="${check_name%.sh}"
    
    # Run check and capture output + exit code
    # Temporarily disable exit-on-error to capture actual exit code
    set +e
    output="$("$check_script" 2>&1)"
    exit_code=$?
    set -e

    # Split output into first line (status|message) and second line (metrics JSON)
    # Use printf instead of echo to avoid issues with strings starting with -
    first_line="$(printf '%s\n' "$output" | head -n1 | tr -d '\r')"
    second_line="$(printf '%s\n' "$output" | sed -n '2p' | tr -d '\r')"

    status="${first_line%%|*}"
    message="${first_line#*|}"
    
    # Debug: log raw output for troubleshooting (temporary)
    if [[ -z "$message" ]] && [[ "$status" != "OK" ]]; then
        echo "DEBUG: check=$check_name, first_line='$first_line', output_length=${#output}" >&2
    fi

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
    json_file="${CHECK_STATUS_DIR}/${check_name}.json"
    prev_status="UNKNOWN"
    if [[ -f "$json_file" ]]; then
        prev_status="$(jq -r '.status' "$json_file" 2>/dev/null || echo "UNKNOWN")"
    fi

    # Alerting logic (unchanged)
    if [[ "$status" == "OK" ]]; then
        if [[ "$prev_status" == "WARN" || "$prev_status" == "CRIT" ]]; then
            send_alert "Recovery: ${check_name}" "${check_name} is now OK on ${NODE_NAME}: ${message}" >/dev/null 2>&1
        fi
    else
        if [[ "$prev_status" != "$status" ]]; then
            send_alert "${status}: ${check_name}" "${check_name} status is ${status} on ${NODE_NAME}: ${message}" >/dev/null 2>&1
        fi
    fi

    # Write JSON state file
    write_json_state "$check_name" "$status" "$message" "$second_line"

done

# Export public status snapshot (optional)
if [[ "${EXPORT_STATUS}" == "true" ]]; then
    if [[ -x "${SCRIPT_DIR}/export-status.sh" ]]; then
        "${SCRIPT_DIR}/export-status.sh" || \
            echo "WARN: export-status.sh failed (non-fatal)" >&2
    else
        echo "WARN: export-status.sh not found or not executable" >&2
    fi
fi