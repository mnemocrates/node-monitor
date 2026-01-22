#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/usr/local/node-monitor/external-config.sh
. "${SCRIPT_DIR}/external-config.sh"

###############################################
# Get current time in milliseconds (portable)
###############################################
get_time_ms() {
    # Try to get milliseconds directly (Linux with GNU date)
    local ms
    ms=$(date +%s%3N 2>/dev/null)
    
    # Check if %N is supported (if not, output will contain literal 'N')
    if [[ "$ms" =~ N ]]; then
        # Fallback for systems without nanosecond support (macOS, BSD)
        local seconds
        seconds=$(date +%s)
        echo $((seconds * 1000))
    else
        echo "$ms"
    fi
}

###############################################
# Retry helper for external checks
###############################################
retry_with_backoff() {
  local cmd="$1"
  local attempts="${2:-$EXT_RETRIES}"
  local delay="${3:-$EXT_RETRY_DELAY}"

  local i=1
  while (( i <= attempts )); do
    if eval "$cmd"; then
      return 0
    fi
    if (( i < attempts )); then
      sleep "${delay}"
    fi
    ((i++))
  done
  return 1
}

###############################################
# Severity mapping
###############################################
severity_name() {
  case "$1" in
    0) echo "OK" ;;
    1) echo "WARN" ;;
    2) echo "CRIT" ;;
    *) echo "UNKNOWN" ;;
  esac
}

###############################################
# Send Alert Message
###############################################
send_alert() {
    local subject="$1"
    local message="$2"

    #
    # Signal (if enabled)
    #
    if [ "${SIGNAL_ENABLED:-false}" = "true" ]; then
        "${SCRIPT_DIR}/send-signal.sh" "${message}" || true
    fi

    #
    # Email (if enabled)
    #
    if [ "${EMAIL_ENABLED:-false}" = "true" ]; then
        "${SCRIPT_DIR}/send-email.sh" "${subject}" "${message}" || true
    fi

    #
    # ntfy (if enabled)
    #
    if [ "${NTFY_ENABLED:-false}" = "true" ]; then
        "${SCRIPT_DIR}/send-ntfy.sh" "${subject}: ${message}" || true
    fi
}

###############################################
# Helper function to write JSON state files
###############################################
write_json_state() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    local metrics_json="$4"   # may be empty

    # Strip .sh extension if present
    check_name="${check_name%.sh}"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local state_dir="${EXT_STATE_DIR}/check-status"
    mkdir -p "$state_dir"
    local json_file="${state_dir}/${check_name}.json"

    # Build current state JSON
    {
        echo "{"
        echo "  \"status\": \"${status}\","
        echo "  \"message\": \"${message}\","
        echo "  \"updated\": \"${timestamp}\""
        if [[ -n "$metrics_json" ]]; then
            echo "  ,\"metrics\": ${metrics_json}"
        fi
        echo "}"
    } > "$json_file"

    # Append to rolling history (if HISTORY_SLOTS is configured)
    if [[ -n "${HISTORY_SLOTS:-}" ]] && [[ "${HISTORY_SLOTS}" -gt 0 ]]; then
        local history_file="${state_dir}/${check_name}.history.jsonl"
        
        # Append new entry (compact JSONL format)
        echo "{\"t\":\"${timestamp}\",\"s\":\"${status}\"}" >> "$history_file"
        
        # Trim to last N slots if exceeded
        if [[ -f "$history_file" ]]; then
            local line_count
            line_count=$(wc -l < "$history_file" 2>/dev/null || echo 0)
            
            if (( line_count > HISTORY_SLOTS )); then
                # Keep only the last HISTORY_SLOTS lines
                tail -n "${HISTORY_SLOTS}" "$history_file" > "${history_file}.tmp" 2>/dev/null
                mv "${history_file}.tmp" "$history_file" 2>/dev/null || rm -f "${history_file}.tmp"
            fi
        fi
    fi
}

###############################################
# Check failure duration for persistent alerts
###############################################
check_failure_duration() {
    local check_name="$1"
    local current_status="$2"
    local threshold="${3:-$ALERT_PERSISTENCE_THRESHOLD}"
    
    check_name="${check_name%.sh}"
    
    local state_file="${EXT_STATE_DIR}/check-status/${check_name}.json"
    local now=$(date +%s)
    
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    local prev_status=$(jq -r '.status // "OK"' "$state_file" 2>/dev/null)
    local prev_updated=$(jq -r '.updated // ""' "$state_file" 2>/dev/null)
    
    if [[ "$prev_status" == "OK" ]]; then
        return 1
    fi
    
    if [[ -z "$prev_updated" ]]; then
        return 1
    fi
    
    local prev_epoch
    prev_epoch=$(date -d "$prev_updated" +%s 2>/dev/null || echo 0)
    
    local duration=$((now - prev_epoch))
    
    if [[ $duration -ge $threshold ]]; then
        return 0
    else
        return 1
    fi
}

###############################################
# Tor/Clearnet connectivity helpers
###############################################

# Test if we can connect via Tor (only if USE_TOR=true)
test_tor_connection() {
    # If not using Tor, skip this check
    if [[ "${USE_TOR}" != "true" ]]; then
        return 0
    fi
    
    if ! command -v torsocks >/dev/null 2>&1; then
        echo "ERROR: torsocks not installed (required when USE_TOR=true)" >&2
        return 1
    fi
    
    if ! pgrep -x tor >/dev/null; then
        echo "ERROR: Tor is not running (required when USE_TOR=true)" >&2
        return 1
    fi
    
    return 0
}

# Connect to service via nc with optional Tor
# Usage: smart_nc <host> <port> <timeout>
smart_nc() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    
    if [[ "${USE_TOR}" == "true" ]]; then
        torsocks timeout "${timeout}" nc -w "${timeout}" "${host}" "${port}" 2>/dev/null
    else
        timeout "${timeout}" nc -w "${timeout}" "${host}" "${port}" 2>/dev/null
    fi
}

# HTTP request with optional Tor
# Usage: smart_curl <url> [additional curl args...]
smart_curl() {
    local url="$1"
    shift
    
    if [[ "${USE_TOR}" == "true" ]]; then
        torsocks curl -s --connect-timeout "${EXT_TIMEOUT}" "$@" "${url}"
    else
        curl -s --connect-timeout "${EXT_TIMEOUT}" "$@" "${url}"
    fi
}

# Deprecated aliases for backward compatibility
tor_nc() { smart_nc "$@"; }
tor_curl() { smart_curl "$@"; }
