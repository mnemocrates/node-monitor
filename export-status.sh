#!/usr/bin/env bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

STATUS_DIR="${STATE_DIR}/check-status"
EXPORT_DIR="/usr/local/node-monitor/export"
EXPORT_FILE="${EXPORT_DIR}/status.json"

mkdir -p "${EXPORT_DIR}"

# Timestamp for the export
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Start building the merged JSON
MERGED='{
  "node": "'"${NODE_NAME}"'",
  "hostname": "'"${HOSTNAME_SHORT}"'",
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

    # Merge this check into the JSON
    MERGED="$(jq --arg k "$key" --slurpfile data "$f" \
        '.checks[$k] = $data[0]' <<< "$MERGED")"
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

