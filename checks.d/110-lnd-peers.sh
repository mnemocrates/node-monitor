#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

if [[ -z "$info_json" ]]; then
    echo "CRIT|Unable to query LND for peer information"
    echo "{}"
    exit 2
fi

peers=$(echo "$info_json" | jq -r '.num_peers // 0')

# Get detailed peer info for inbound/outbound breakdown
peer_list=$(lncli_safe listpeers 2>/dev/null || echo "{}")
inbound=$(echo "$peer_list" | jq '[.peers[] | select(.inbound == true)] | length')
outbound=$(echo "$peer_list" | jq '[.peers[] | select(.inbound == false)] | length')

metrics_json="{\"peers\": ${peers}, \"inbound\": ${inbound}, \"outbound\": ${outbound}}"

if (( peers == 0 )); then
    echo "CRIT|LND has no peers"
    echo "$metrics_json"
    exit 2
elif (( peers <= LND_PEERS_CRIT )); then
    echo "CRIT|LND peers critically low: ${peers} (threshold: ${LND_PEERS_CRIT})"
    echo "$metrics_json"
    exit 2
elif (( peers < LND_PEERS_WARN )); then
    echo "WARN|LND peers low: ${peers} (threshold: ${LND_PEERS_WARN}, inbound: ${inbound}, outbound: ${outbound})"
    echo "$metrics_json"
    exit 1
else
    echo "OK|LND peers healthy: ${peers} (inbound: ${inbound}, outbound: ${outbound})"
    echo "$metrics_json"
    exit 0
fi

