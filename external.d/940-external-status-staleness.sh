#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

CHECK_NAME="940-external-status-staleness"

# Check if we're testing a local file or remote URL
if [[ -n "${STATUS_JSON_LOCAL_PATH:-}" ]]; then
    # Local file mode
    if [[ ! -f "${STATUS_JSON_LOCAL_PATH}" ]]; then
        echo "CRIT|status.json file not found at ${STATUS_JSON_LOCAL_PATH}"
        echo "{}"
        write_json_state "$CHECK_NAME" "CRIT" "status.json file not found" "{}"
        exit 2
    fi
    
    # Get file modification time
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        file_mtime=$(stat -f %m "${STATUS_JSON_LOCAL_PATH}")
    else
        # Linux/Unix
        file_mtime=$(stat -c %Y "${STATUS_JSON_LOCAL_PATH}")
    fi
    
    current_time=$(date +%s)
    age_seconds=$((current_time - file_mtime))
    
    # Try to parse the file to verify it's valid JSON
    if ! jq empty "${STATUS_JSON_LOCAL_PATH}" 2>/dev/null; then
        echo "CRIT|status.json is not valid JSON"
        echo "{\"age_seconds\": ${age_seconds}}"
        write_json_state "$CHECK_NAME" "CRIT" "status.json is not valid JSON" "{\"age_seconds\": ${age_seconds}}"
        exit 2
    fi
    
    # Try to extract updated timestamp from JSON
    json_updated=$(jq -r '.updated // empty' "${STATUS_JSON_LOCAL_PATH}" 2>/dev/null || echo "")
    
    metrics_json="{\"age_seconds\": ${age_seconds}, \"source\": \"local\", \"path\": \"${STATUS_JSON_LOCAL_PATH}\"}"
    
elif [[ -n "${STATUS_JSON_URL:-}" ]]; then
    # Remote URL mode
    
    # Verify connection method is available
    if ! test_tor_connection; then
        echo "CRIT|Connection method not available (Tor required but not running)"
        echo "{}"
        exit 2
    fi
    
    # Fetch the status.json file
    attempt=0
    success=false
    response_time_ms=0
    status_content=""
    
    while (( attempt < EXT_RETRIES )); do
        attempt=$((attempt + 1))
        
        # Measure response time
        start_time=$(get_time_ms)
        
        # Try to fetch status.json
        status_content=$(smart_curl "${STATUS_JSON_URL}" 2>/dev/null || echo "")
        
        end_time=$(get_time_ms)
        response_time_ms=$((end_time - start_time))
        
        # Check if we got valid JSON
        if [[ -n "$status_content" ]] && echo "$status_content" | jq empty 2>/dev/null; then
            success=true
            break
        fi
        
        if (( attempt < EXT_RETRIES )); then
            sleep "${EXT_RETRY_DELAY}"
        fi
    done
    
    if ! $success; then
        connection_type="$([[ "${USE_TOR}" == "true" ]] && echo "Tor" || echo "direct")"
        echo "CRIT|status.json not reachable or invalid via ${connection_type} (${STATUS_JSON_URL})"
        metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"source\": \"remote\"}"
        echo "$metrics_json"
        write_json_state "$CHECK_NAME" "CRIT" "status.json not reachable" "$metrics_json"
        
        if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
            send_alert "EXTERNAL: Status File Unreachable" "status.json is not reachable via ${connection_type} (${attempt} attempts)"
        fi
        exit 2
    fi
    
    # Extract updated timestamp from JSON
    json_updated=$(echo "$status_content" | jq -r '.updated // empty' 2>/dev/null || echo "")
    
    if [[ -z "$json_updated" ]]; then
        echo "WARN|status.json does not contain 'updated' timestamp"
        metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"source\": \"remote\", \"url\": \"${STATUS_JSON_URL}\"}"
        echo "$metrics_json"
        write_json_state "$CHECK_NAME" "WARN" "Missing updated timestamp" "$metrics_json"
        exit 1
    fi
    
    # Convert ISO timestamp to epoch
    json_epoch=$(date -d "$json_updated" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$json_updated" +%s 2>/dev/null || echo 0)
    
    if [[ $json_epoch -eq 0 ]]; then
        echo "WARN|Could not parse 'updated' timestamp: ${json_updated}"
        metrics_json="{\"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"source\": \"remote\", \"url\": \"${STATUS_JSON_URL}\"}"
        echo "$metrics_json"
        write_json_state "$CHECK_NAME" "WARN" "Could not parse timestamp" "$metrics_json"
        exit 1
    fi
    
    current_time=$(date +%s)
    age_seconds=$((current_time - json_epoch))
    
    metrics_json="{\"age_seconds\": ${age_seconds}, \"response_time_ms\": ${response_time_ms}, \"attempts\": ${attempt}, \"source\": \"remote\", \"url\": \"${STATUS_JSON_URL}\"}"
    
else
    # Neither local nor remote configured
    echo "WARN|STATUS_JSON_LOCAL_PATH or STATUS_JSON_URL not configured"
    echo "{}"
    exit 1
fi

# Check staleness thresholds
if (( age_seconds > STATUS_JSON_STALENESS_CRIT )); then
    age_minutes=$((age_seconds / 60))
    threshold_minutes=$((STATUS_JSON_STALENESS_CRIT / 60))
    echo "CRIT|status.json is critically stale: ${age_minutes} minutes old (threshold: ${threshold_minutes} minutes)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "CRIT" "status.json critically stale: ${age_minutes}m" "$metrics_json"
    
    if check_failure_duration "$CHECK_NAME" "CRIT" "${ALERT_GRACE_PERIOD}"; then
        send_alert "EXTERNAL: Status File Stale" "status.json is ${age_minutes} minutes old (threshold: ${threshold_minutes} minutes)"
    fi
    exit 2
elif (( age_seconds > STATUS_JSON_STALENESS_WARN )); then
    age_minutes=$((age_seconds / 60))
    threshold_minutes=$((STATUS_JSON_STALENESS_WARN / 60))
    echo "WARN|status.json is stale: ${age_minutes} minutes old (threshold: ${threshold_minutes} minutes)"
    echo "$metrics_json"
    write_json_state "$CHECK_NAME" "WARN" "status.json stale: ${age_minutes}m" "$metrics_json"
    exit 1
fi

# All good
age_minutes=$((age_seconds / 60))
echo "OK|status.json is fresh (${age_minutes} minutes old)"
echo "$metrics_json"
write_json_state "$CHECK_NAME" "OK" "status.json is fresh (${age_minutes}m)" "$metrics_json"
exit 0
