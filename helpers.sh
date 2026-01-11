#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/usr/local/node-monitor/config.sh
. "${SCRIPT_DIR}/config.sh"

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
# Retry helper for Tor/public checks
###############################################
retry_with_backoff() {
  local cmd="$1"
  local attempts="${2:-$RETRY_ATTEMPTS}"
  local delay="${3:-$RETRY_DELAY_SECONDS}"

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
# lncli wrapper (adds TLS/macaroon paths if set)
###############################################
lncli_safe() {
  local extra_args=()
  if [[ -n "${LND_TLSCERT}" ]]; then
    extra_args+=(--tlscertpath "${LND_TLSCERT}")
  fi
  if [[ -n "${LND_MACAROON}" ]]; then
    extra_args+=(--macaroonpath "${LND_MACAROON}")
  fi
  "${LNCLI}" "${extra_args[@]}" "$@"
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
        /usr/local/node-monitor/send-signal.sh "${message}" || true
    fi

    #
    # Email (if enabled)
    #
    if [ "${EMAIL_ENABLED:-false}" = "true" ]; then
        /usr/local/node-monitor/send-email.sh "${subject}" "${message}" || true
    fi

    #
    # ntfy (if enabled)
    #
    if [ "${NTFY_ENABLED:-false}" = "true" ]; then
        /usr/local/node-monitor/send-ntfy.sh "${subject}: ${message}" || true
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

    local state_dir="${STATE_DIR}/check-status"
    mkdir -p "$state_dir"
    local json_file="${state_dir}/${check_name}.json"

    # Build JSON:
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
}

###############################################
# Cached Bitcoin RPC: getmempoolinfo
###############################################
# Cache getmempoolinfo results to avoid repeated RPC calls
# within a single run-checks.sh execution (30 second TTL)
get_mempool_info_cached() {
    local cache_file="${STATE_DIR:-/tmp}/mempool-info-cache.json"
    local cache_ttl=30  # seconds
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(date -r "$cache_file" +%s 2>/dev/null || echo 0) ))
        
        if [[ "$cache_age" -lt "$cache_ttl" ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Cache miss or expired - fetch fresh data
    local mempool_info
    if mempool_info=$("${BITCOIN_CLI}" getmempoolinfo 2>/dev/null); then
        echo "$mempool_info" > "$cache_file"
        echo "$mempool_info"
        return 0
    else
        return 1
    fi
}

###############################################
# Cached Electrs RPC: blockchain.headers.subscribe
###############################################
# Cache electrs query results to avoid repeated connections
# within a single run-checks.sh execution (30 second TTL)
# Returns: JSON response with height, response_time_ms, server_version, success
get_electrs_info_cached() {
    local cache_file="${STATE_DIR:-/tmp}/electrs-info-cache.json"
    local cache_ttl=30  # seconds
    
    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(date -r "$cache_file" +%s 2>/dev/null || echo 0) ))
        
        if [[ "$cache_age" -lt "$cache_ttl" ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Cache miss or expired - fetch fresh data
    local attempt=0
    local success=false
    local electrs_json=""
    local response_time_ms=0
    local server_version=""
    local height=0
    
    # Use defaults if variables are not set
    local retries="${ELECTRS_RETRIES:-3}"
    local timeout="${ELECTRS_TIMEOUT:-15}"
    local retry_delay="${ELECTRS_RETRY_DELAY:-5}"
    local host="${ELECTRS_HOST:-127.0.0.1}"
    local port="${ELECTRS_PORT:-50001}"
    
    while (( attempt < retries )); do
        ((attempt++))
        
        # Measure response time
        local start_time=$(get_time_ms)  # milliseconds
        
        # Query electrs using blockchain.headers.subscribe
        electrs_json=$(printf '{"jsonrpc":"2.0","id":1,"method":"blockchain.headers.subscribe","params":[]}\n' \
            | timeout "${timeout}" nc -w "${timeout}" "${host}" "${port}" 2>/dev/null || echo "")
        
        local end_time=$(get_time_ms)
        response_time_ms=$((end_time - start_time))
        
        # Check if we got a valid response
        if [[ -n "$electrs_json" ]] && echo "$electrs_json" | jq -e '.result' >/dev/null 2>&1; then
            success=true
            height=$(echo "$electrs_json" | jq -r '.result.height // 0')
            
            # Try to get server version for additional info (sanitize output)
            local version_raw
            version_raw=$(printf '{"jsonrpc":"2.0","id":2,"method":"server.version","params":["node-monitor","1.4"]}\n' \
                | timeout 5 nc -w 5 "${host}" "${port}" 2>/dev/null \
                | jq -r '.result[0] // ""' 2>/dev/null \
                | tr -d '\n\r')
            server_version="${version_raw:-unknown}"
            
            break
        fi
        
        # If not last attempt, wait before retry
        if (( attempt < retries )); then
            sleep "${retry_delay}"
        fi
    done
    
    # Build cache JSON using jq to properly escape all strings
    local cache_json
    cache_json=$(jq -n \
        --argjson success "$success" \
        --argjson height "$height" \
        --argjson response_time_ms "$response_time_ms" \
        --arg server_version "$server_version" \
        --argjson attempts "$attempt" \
        '{success: $success, height: $height, response_time_ms: $response_time_ms, server_version: $server_version, attempts: $attempts}')
    
    # Only cache successful responses
    if $success; then
        echo "$cache_json" > "$cache_file"
    fi
    
    echo "$cache_json"
    
    if $success; then
        return 0
    else
        return 1
    fi
}

###############################################
# Check failure duration for persistent alerts
###############################################
# Returns 0 if failure has persisted beyond threshold, 1 otherwise
# Usage: check_failure_duration <check_name> <current_status> <threshold_seconds>
check_failure_duration() {
    local check_name="$1"
    local current_status="$2"  # WARN or CRIT
    local threshold="${3:-900}"  # default 15 minutes
    
    # Strip .sh extension if present
    check_name="${check_name%.sh}"
    
    local state_file="${STATE_DIR}/check-status/${check_name}.json"
    local now=$(date +%s)
    
    # If state file doesn't exist, this is first failure
    if [[ ! -f "$state_file" ]]; then
        return 1  # Not persisted yet
    fi
    
    # Read previous status and timestamp
    local prev_status=$(jq -r '.status // "OK"' "$state_file" 2>/dev/null)
    local prev_updated=$(jq -r '.updated // ""' "$state_file" 2>/dev/null)
    
    # If previous status was OK, this is first failure
    if [[ "$prev_status" == "OK" ]]; then
        return 1  # Not persisted yet
    fi
    
    # If no timestamp, treat as new failure
    if [[ -z "$prev_updated" ]]; then
        return 1
    fi
    
    # Convert ISO timestamp to epoch
    local prev_epoch
    prev_epoch=$(date -d "$prev_updated" +%s 2>/dev/null || echo 0)
    
    # Calculate duration
    local duration=$((now - prev_epoch))
    
    # Return 0 if duration exceeds threshold (persistent failure)
    if [[ $duration -ge $threshold ]]; then
        return 0
    else
        return 1
    fi
}

