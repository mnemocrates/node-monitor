#!/usr/bin/env bash
set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/helpers.sh"

EXPORT_DIR="/usr/local/node-monitor/export"
NODECARD_FILE="${EXPORT_DIR}/nodecard.json"
NODECARD_UNSIGNED="${EXPORT_DIR}/nodecard_unsigned.json"

mkdir -p "${EXPORT_DIR}"

# Timestamp for the export
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Collecting node information..."

# Get node info
NODE_INFO=$(lncli_safe getinfo 2>/dev/null || echo "{}")

# Get node alias, color, and URIs
ALIAS=$(echo "$NODE_INFO" | jq -r '.alias // "unknown"')
COLOR=$(echo "$NODE_INFO" | jq -r '.color // "#000000"')
PUBKEY=$(echo "$NODE_INFO" | jq -r '.identity_pubkey // ""')
URIS=$(echo "$NODE_INFO" | jq -c '.uris // []')
VERSION=$(echo "$NODE_INFO" | jq -r '.version // "unknown"')

# Get chain and network info
CHAINS=$(echo "$NODE_INFO" | jq -c '.chains // []' | jq '[.[].chain] // ["bitcoin"]')
NETWORK=$(echo "$NODE_INFO" | jq -r '.chains[0].network // "mainnet"')

# Get sync status
SYNC_TO_CHAIN=$(echo "$NODE_INFO" | jq -r '.synced_to_chain // false')
SYNC_TO_GRAPH=$(echo "$NODE_INFO" | jq -r '.synced_to_graph // false')

# Get capabilities from features
FEATURES=$(echo "$NODE_INFO" | jq -c '.features // {}')
CAPABILITIES=$(echo "$FEATURES" | jq -r '[
  (if (."9"  or ."8")  then "TLV Onion" else empty end),
  (if (."15" or ."14") then "Payment Metadata" else empty end),
  (if (."17" or ."16") then "MPP" else empty end),
  (if (."31" or ."30") then "AMP" else empty end),
  (if (."55" or ."54") then "KeySend" else empty end),
  (if (."45" or ."44") then "Explicit Channel Type" else empty end),
  (if (."1"  or ."0")  then "Data Loss Protection" else empty end)
] | unique')

# Get channel count and capacity
NUM_ACTIVE_CHANNELS=$(echo "$NODE_INFO" | jq -r '.num_active_channels // 0')
NUM_PENDING_CHANNELS=$(echo "$NODE_INFO" | jq -r '.num_pending_channels // 0')
NUM_INACTIVE_CHANNELS=$(echo "$NODE_INFO" | jq -r '.num_inactive_channels // 0')

# Get detailed channel information
CHANNELS_INFO=$(lncli_safe listchannels 2>/dev/null || echo '{"channels":[]}')
TOTAL_LOCAL_BALANCE=$(echo "$CHANNELS_INFO" | jq '[.channels[].local_balance // 0] | add // 0')
TOTAL_REMOTE_BALANCE=$(echo "$CHANNELS_INFO" | jq '[.channels[].remote_balance // 0] | add // 0')
TOTAL_CAPACITY=$(echo "$CHANNELS_INFO" | jq '[.channels[].capacity // 0] | add // 0')

# Get fee policies and calculate aggregates
FEE_REPORT=$(lncli_safe feereport 2>/dev/null || echo '{"channel_fees":[]}')

# Calculate policy summary aggregates
POLICY_SUMMARY=$(echo "$FEE_REPORT" | jq '{
  channels_count: (.channel_fees | length),
  fee_base_msat: {
    median: ((.channel_fees | map(.base_fee_msat // 0) | sort | if length > 0 then .[length / 2 | floor] else 0 end) // 0),
    min: ((.channel_fees | map(.base_fee_msat // 0) | min) // 0),
    max: ((.channel_fees | map(.base_fee_msat // 0) | max) // 0)
  },
  fee_rate_ppm: {
    median: ((.channel_fees | map(.fee_rate // 0) | sort | if length > 0 then .[length / 2 | floor] else 0 end) // 0),
    min: ((.channel_fees | map(.fee_rate // 0) | min) // 0),
    max: ((.channel_fees | map(.fee_rate // 0) | max) // 0)
  },
  time_lock_delta: {
    median: ((.channel_fees | map(.time_lock_delta // 40) | sort | if length > 0 then .[length / 2 | floor] else 40 end) // 40),
    min: ((.channel_fees | map(.time_lock_delta // 40) | min) // 40),
    max: ((.channel_fees | map(.time_lock_delta // 40) | max) // 40)
  }
}')

# Build structured endpoints from URIs
ENDPOINTS=$(echo "$URIS" | jq '[.[] | {
  type: (if (. | contains(".onion")) then "tor" 
        elif (. | contains(".i2p")) then "i2p" 
        else "clearnet" end),
  addr: .,
  preferred: true
}]')

# If no endpoints, create empty array
if [[ "$ENDPOINTS" == "null" ]] || [[ "$ENDPOINTS" == "[]" ]]; then
  ENDPOINTS="[]"
fi

# Build the unsigned nodecard JSON
UNSIGNED_DATA=$(jq -n \
  --arg alias "$ALIAS" \
  --arg pubkey "$PUBKEY" \
  --arg color "$COLOR" \
  --argjson endpoints "$ENDPOINTS" \
  --arg version "$VERSION" \
  --argjson chains "$CHAINS" \
  --arg network "$NETWORK" \
  --argjson sync_chain "$SYNC_TO_CHAIN" \
  --argjson sync_graph "$SYNC_TO_GRAPH" \
  --argjson capabilities "$CAPABILITIES" \
  --argjson num_active "$NUM_ACTIVE_CHANNELS" \
  --argjson num_pending "$NUM_PENDING_CHANNELS" \
  --argjson num_inactive "$NUM_INACTIVE_CHANNELS" \
  --argjson local_balance "$TOTAL_LOCAL_BALANCE" \
  --argjson remote_balance "$TOTAL_REMOTE_BALANCE" \
  --argjson capacity "$TOTAL_CAPACITY" \
  --argjson policy_summary "$POLICY_SUMMARY" \
  --arg last_updated "$NOW" \
  '{
    "alias": $alias,
    "pubkey": $pubkey,
    "color": $color,
    "endpoints": $endpoints,
    "version": $version,
    "chains": $chains,
    "network": $network,
    "sync": {
      "to_chain": $sync_chain,
      "to_graph": $sync_graph
    },
    "channels": {
      "active": $num_active,
      "pending": $num_pending,
      "inactive": $num_inactive,
      "total_capacity": $capacity,
      "local_balance": $local_balance,
      "remote_balance": $remote_balance
    },
    "capabilities": $capabilities,
    "policy_summary": $policy_summary,
    "links": {
      "amboss": "https://amboss.space/node/\($pubkey)",
      "lightningnetwork+":"https://lightningnetwork.plus/nodes/\($pubkey)",
      "lnrouter":"https://lnrouter.app/node/\($pubkey)",
      "mempool": "https://mempool.space/lightning/node/\($pubkey)"      
    },
    "last_updated": $last_updated
  }')

# Write unsigned data to temporary file
echo "$UNSIGNED_DATA" | jq '.' > "${NODECARD_UNSIGNED}"

# Sign the JSON data
echo "Signing nodecard with node key..."
# Create compact JSON message to sign (this exact string is what gets signed)
SIGNED_MESSAGE=$(echo "$UNSIGNED_DATA" | jq -c '.')
SIGNATURE=$(lncli_safe signmessage "$SIGNED_MESSAGE" 2>/dev/null | jq -r '.signature // ""')

if [[ -z "$SIGNATURE" ]]; then
  echo "Error: Failed to sign nodecard" >&2
  exit 1
fi

# Create the final signed nodecard with both signature and signed_message
SIGNED_NODECARD=$(echo "$UNSIGNED_DATA" | jq --arg sig "$SIGNATURE" --arg msg "$SIGNED_MESSAGE" '. + {signature: $sig, signed_message: $msg}')

# Write final signed nodecard
echo "$SIGNED_NODECARD" | jq '.' > "${NODECARD_FILE}"

echo "Nodecard created and signed: ${NODECARD_FILE}"

# Export nodecard using configured method
if [[ "${NODECARD_EXPORT_ENABLED:-false}" != "true" ]]; then
  echo "Nodecard export is disabled. Set NODECARD_EXPORT_ENABLED=true in config.sh to enable."
  exit 0
fi

case "${NODECARD_EXPORT_METHOD:-scp}" in
  scp)
    echo "Exporting nodecard via SCP..."
    if [[ "${NODECARD_EXPORT_TRANSPORT:-ssh}" == "torsocks" ]]; then
      "$TORSOCKS_BIN" scp -i "${NODECARD_EXPORT_SCP_IDENTITY}" -q \
        "${NODECARD_FILE}" "${NODECARD_EXPORT_SCP_TARGET}"
    else
      scp -i "${NODECARD_EXPORT_SCP_IDENTITY}" -q \
        "${NODECARD_FILE}" "${NODECARD_EXPORT_SCP_TARGET}"
    fi
    echo "Nodecard exported to ${NODECARD_EXPORT_SCP_TARGET}"
    ;;
  local)
    echo "Copying nodecard to local destination..."
    cp "${NODECARD_FILE}" "${NODECARD_EXPORT_LOCAL_TARGET}"
    echo "Nodecard copied to ${NODECARD_EXPORT_LOCAL_TARGET}"
    ;;
  none)
    echo "Nodecard export method is 'none'. Skipping upload."
    ;;
  *)
    echo "Unknown nodecard export method: ${NODECARD_EXPORT_METHOD:-scp}" >&2
    exit 1
    ;;
esac

echo "Nodecard export completed successfully."
