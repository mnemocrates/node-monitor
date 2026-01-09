#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

info_json="$(lncli_safe getinfo 2>/dev/null || echo "")"

if [[ -z "$info_json" ]]; then
    echo "CRIT|Unable to query LND for channel information"
    echo "{}"
    exit 2
fi

active=$(echo "$info_json" | jq -r '.num_active_channels // 0')
inactive=$(echo "$info_json" | jq -r '.num_inactive_channels // 0')
pending=$(echo "$info_json" | jq -r '.num_pending_channels // 0')
total=$((active + inactive))

metrics_json="{\"active\": ${active}, \"inactive\": ${inactive}, \"pending\": ${pending}, \"total\": ${total}}"

issues=()
severity="OK"

# Check active channel count
if (( active == 0 && total > 0 )); then
    issues+=("all ${total} channels inactive")
    severity="CRIT"
elif (( active == 0 )); then
    issues+=("no channels")
    severity="CRIT"
elif (( active <= LND_CHANNELS_CRIT )); then
    issues+=("only ${active} active channel(s)")
    severity="CRIT"
elif (( active < LND_CHANNELS_WARN )); then
    if [[ "$severity" != "CRIT" ]]; then
        severity="WARN"
    fi
    issues+=("${active} active channels (below threshold: ${LND_CHANNELS_WARN})")
fi

# Check for excessive inactive channels
if (( inactive >= LND_CHANNELS_INACTIVE_WARN )); then
    if [[ "$severity" != "CRIT" ]]; then
        severity="WARN"
    fi
    issues+=("${inactive} inactive channels (peers offline)")
fi

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    message="LND channels healthy: ${active} active, ${inactive} inactive, ${pending} pending"
else
    issue_str=$(IFS=', '; echo "${issues[*]}")
    message="LND channel issues: ${issue_str}"
fi

echo "${severity}|${message}"
echo "$metrics_json"

if [[ "$severity" == "CRIT" ]]; then
    exit 2
elif [[ "$severity" == "WARN" ]]; then
    exit 1
else
    exit 0
fi

