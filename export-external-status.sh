#!/usr/bin/env bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/external-config.sh"

STATUS_DIR="${EXT_STATE_DIR}/check-status"
EXPORT_DIR="${EXT_STATE_DIR}/export"
EXPORT_FILE="${EXPORT_DIR}/external-status.json"

mkdir -p "${EXPORT_DIR}"

# Timestamp for the export
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Start building the merged JSON
MERGED='{
  "monitoring_type": "external",
  "timestamp": "'"${NOW}"'",
  "checks": {}
}'

# Check if status directory exists
if [[ ! -d "$STATUS_DIR" ]]; then
    echo "ERROR: Status directory not found: $STATUS_DIR" >&2
    exit 1
fi

# Iterate through all JSON files in sorted order
for f in "${STATUS_DIR}"/*.json; do
    # Skip if no files match
    [[ -e "$f" ]] || continue
    
    base="$(basename "$f" .json)"        # e.g., 910-external-bitcoin-connectivity
    
    # Normalize key: strip prefix + replace hyphens with underscores
    key="${base#*-}"                     # remove NNN-external-
    key="${key//-/_}"                    # hyphens → underscores

    # Read the check JSON
    check_data="$(cat "$f")"

    # Merge history if enabled and available
    if [[ -n "${HISTORY_SLOTS:-}" ]] && [[ "${HISTORY_SLOTS}" -gt 0 ]]; then
        history_file="${STATUS_DIR}/${base}.history.jsonl"
        
        if [[ -f "$history_file" ]]; then
            # Convert JSONL to JSON array (read all lines, wrap in array)
            history_array="$(jq -s '.' "$history_file" 2>/dev/null || echo "[]")"
            
            # Add history to the check data
            check_data="$(echo "$check_data" | jq --argjson hist "$history_array" \
                '. + {history: $hist}' 2>/dev/null || echo "$check_data")"
        fi
    fi

    # Merge check (with history) into the JSON
    MERGED="$(jq --arg k "$key" --argjson data "$check_data" \
        '.checks[$k] = $data' <<< "$MERGED")"
done

# Write final JSON
echo "$MERGED" | jq '.' > "${EXPORT_FILE}"

echo "External status exported to: ${EXPORT_FILE}"

# Export to configured destination
case "${EXT_EXPORT_METHOD:-none}" in
  scp)
    if [[ -z "${EXT_EXPORT_SCP_TARGET}" ]]; then
        echo "WARN: EXT_EXPORT_METHOD=scp but EXT_EXPORT_SCP_TARGET not configured" >&2
    else
        if [[ "${EXT_EXPORT_TRANSPORT}" == "torsocks" ]]; then
            if torsocks scp -i "${EXT_EXPORT_SCP_IDENTITY}" -q "${EXPORT_FILE}" "${EXT_EXPORT_SCP_TARGET}"; then
                echo "External status pushed via SCP over Tor to: ${EXT_EXPORT_SCP_TARGET}"
            else
                echo "ERROR: Failed to push external status via SCP over Tor" >&2
                exit 1
            fi
        else
            if scp -i "${EXT_EXPORT_SCP_IDENTITY}" -q "${EXPORT_FILE}" "${EXT_EXPORT_SCP_TARGET}"; then
                echo "External status pushed via SCP to: ${EXT_EXPORT_SCP_TARGET}"
            else
                echo "ERROR: Failed to push external status via SCP" >&2
                exit 1
            fi
        fi
    fi
    ;;
  local)
    if [[ -z "${EXT_EXPORT_LOCAL_TARGET}" ]]; then
        echo "WARN: EXT_EXPORT_METHOD=local but EXT_EXPORT_LOCAL_TARGET not configured" >&2
    else
        if cp "${EXPORT_FILE}" "${EXT_EXPORT_LOCAL_TARGET}"; then
            echo "External status copied to: ${EXT_EXPORT_LOCAL_TARGET}"
        else
            echo "ERROR: Failed to copy external status to local target" >&2
            exit 1
        fi
    fi
    ;;
  none)
    echo "Export disabled (EXT_EXPORT_METHOD=none)"
    ;;
  *)
    echo "WARN: Unknown EXT_EXPORT_METHOD: ${EXT_EXPORT_METHOD:-not set}" >&2
    ;;
esac
