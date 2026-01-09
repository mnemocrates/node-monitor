#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Check if temperature monitoring is enabled
if [[ "${TEMP_CHECK_ENABLED:-true}" != "true" ]]; then
    echo "OK|Temperature monitoring disabled"
    echo "{\"enabled\": false}"
    exit 0
fi

temp_readings=()
max_temp=0
max_temp_source=""
severity="OK"
issues=()

# Try multiple temperature sources

# 1. Try /sys/class/thermal (common on Linux)
if [[ -d "/sys/class/thermal" ]]; then
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -f "$zone" ]]; then
            temp_millic=$(cat "$zone" 2>/dev/null || echo 0)
            temp_c=$((temp_millic / 1000))
            
            if (( temp_c > 0 )); then
                zone_name=$(basename "$(dirname "$zone")")
                zone_type=$(cat "$(dirname "$zone")/type" 2>/dev/null || echo "unknown")
                temp_readings+=("\"${zone_name}\": {\"celsius\": ${temp_c}, \"type\": \"${zone_type}\"}")
                
                if (( temp_c > max_temp )); then
                    max_temp=$temp_c
                    max_temp_source="${zone_type}"
                fi
            fi
        fi
    done
fi

# 2. Try sensors command (if available)
if command -v sensors >/dev/null 2>&1 && [[ "${#temp_readings[@]}" -eq 0 ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Za-z0-9_-]+:.*\+([0-9]+)\..*°C ]]; then
            temp_c="${BASH_REMATCH[1]}"
            sensor_name=$(echo "$line" | cut -d: -f1 | xargs)
            temp_readings+=("\"${sensor_name}\": {\"celsius\": ${temp_c}, \"type\": \"sensors\"}")
            
            if (( temp_c > max_temp )); then
                max_temp=$temp_c
                max_temp_source="${sensor_name}"
            fi
        fi
    done < <(sensors 2>/dev/null)
fi

# 3. Try Raspberry Pi specific (if available)
if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]] && [[ "${#temp_readings[@]}" -eq 0 ]]; then
    temp_millic=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    temp_c=$((temp_millic / 1000))
    
    if (( temp_c > 0 )); then
        temp_readings+=("\"cpu\": {\"celsius\": ${temp_c}, \"type\": \"system\"}")
        max_temp=$temp_c
        max_temp_source="CPU"
    fi
fi

# If no temperature readings found
if [[ "${#temp_readings[@]}" -eq 0 ]]; then
    echo "OK|Temperature monitoring unavailable on this system"
    echo "{\"available\": false}"
    exit 0
fi

# Check thresholds
if (( max_temp >= TEMP_CRIT_CELSIUS )); then
    severity="CRIT"
    issues+=("${max_temp_source}: ${max_temp}°C (threshold: ${TEMP_CRIT_CELSIUS}°C)")
elif (( max_temp >= TEMP_WARN_CELSIUS )); then
    severity="WARN"
    issues+=("${max_temp_source}: ${max_temp}°C (threshold: ${TEMP_WARN_CELSIUS}°C)")
fi

# Build metrics JSON
metrics_json=$(printf '{"sensors": {%s}, "max_temp_celsius": %d}' "$(IFS=,; echo "${temp_readings[*]}")" "$max_temp")

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    message="Temperature healthy: ${max_temp}°C (${max_temp_source})"
else
    issue_str=$(IFS=', '; echo "${issues[*]}")
    message="Temperature issues: ${issue_str}"
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
