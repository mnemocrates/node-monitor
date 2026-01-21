#!/usr/bin/env bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

STATUS_DIR="${STATE_DIR}/check-status"
EXPORT_DIR="${EXPORT_DIR:-${STATE_DIR}/export}"  # Use configured EXPORT_DIR or default
EXPORT_FILE="${EXPORT_DIR}/status.json"

mkdir -p "${EXPORT_DIR}"

# Timestamp for the export
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

###############################################
# Sanitize function to remove sensitive data
###############################################
sanitize_check_json() {
    local json="$1"
    
    # Remove URIs, onion addresses, and other sensitive location data from metrics
    # This strips .onion addresses, IP addresses, hostnames while keeping counts and status
    json=$(echo "$json" | jq '
        # Recursively walk through the object and sanitize sensitive fields
        walk(
            if type == "object" then
                # Remove uri/URI fields completely
                del(.uri, .URI, .uris, .URIs) |
                # Redact host/hostname/address fields
                if has("host") then 
                    if .host == "" or .host == null then . 
                    else .host = "[REDACTED]" 
                    end 
                else . end |
                if has("hostname") then 
                    if .hostname == "" or .hostname == null then . 
                    else .hostname = "[REDACTED]" 
                    end 
                else . end |
                if has("address") then 
                    if .address == "" or .address == null then . 
                    else .address = "[REDACTED]" 
                    end 
                else . end |
                # Remove hosts objects/arrays completely
                if has("hosts") then del(.hosts) else . end |
                # Sanitize ping results object - remove specific hosts but keep success indicators
                if has("ping") and (.ping | type == "object") then
                    .ping |= (
                        # Keep only aggregated metrics, remove per-host results
                        {success_count, total_count}
                    )
                else . end |
                # Sanitize DNS results - keep only success flag and response time
                if has("dns") and (.dns | type == "object") then
                    .dns |= (
                        # Remove the specific host being tested
                        del(.host)
                    )
                else . end
            elif type == "array" then
                # For arrays, check if they contain URI-like strings
                if all(type == "string") and length > 0 then
                    if (.[0] | test("^[a-z0-9]{16,}\\.onion|://|@.*:|^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")) then
                        # Array contains URIs/onions/IPs - replace with redacted markers
                        [range(length) | "[REDACTED]"]
                    else
                        # Keep array as-is
                        .
                    end
                else
                    # Keep array but sanitize its elements recursively
                    .
                end
            else
                .
            end
        )
    ')
    
    echo "$json"
}

# Start building the merged JSON
MERGED='{
  "node": "'"${NODE_NAME}"'",
  "timestamp": "'"${NOW}"'",
  "checks": {}
}'

# Iterate through all JSON files in sorted order
for f in "${STATUS_DIR}"/*.json; do
    base="$(basename "$f" .json)"        # e.g., 010-bitcoin-rpc
    if [[ ! " ${PUBLIC_CHECKS[*]} " =~ " ${base} " ]]; then
        continue
    fi

    # Normalize key: strip prefix + replace hyphens with underscores
    key="${base#*-}"                     # remove NNN-
    key="${key//-/_}"                    # hyphens → underscores

    # Read and sanitize the check JSON to remove sensitive data
    check_data="$(cat "$f")"
    sanitized_data="$(sanitize_check_json "$check_data")"

    # Merge history if enabled and available
    if [[ "${EXPORT_HISTORY:-true}" == "true" ]]; then
        history_file="${STATUS_DIR}/${base}.history.jsonl"
        
        if [[ -f "$history_file" ]]; then
            # Convert JSONL to JSON array (read all lines, wrap in array)
            history_array="$(jq -s '.' "$history_file" 2>/dev/null || echo "[]")"
            
            # Add history to the sanitized data
            sanitized_data="$(echo "$sanitized_data" | jq --argjson hist "$history_array" \
                '. + {history: $hist}' 2>/dev/null || echo "$sanitized_data")"
        fi
    fi

    # Merge sanitized check (with history) into the JSON
    MERGED="$(jq --arg k "$key" --argjson data "$sanitized_data" \
        '.checks[$k] = $data' <<< "$MERGED")"
done

# Write final JSON
echo "$MERGED" | jq '.' > "${EXPORT_FILE}"

# Export method

case "$EXPORT_METHOD" in
  scp)
    if [[ "$EXPORT_TRANSPORT" == "torsocks" ]]; then
      "$TORSOCKS_BIN" scp -i "${EXPORT_SCP_IDENTITY}" -q \
        "${EXPORT_FILE}" "${EXPORT_SCP_TARGET}"
    else
      scp -i "${EXPORT_SCP_IDENTITY}" -q \
        "${EXPORT_FILE}" "${EXPORT_SCP_TARGET}"
    fi
    ;;
  local)
    cp "${EXPORT_FILE}" "${EXPORT_LOCAL_TARGET}"
    ;;
esac

