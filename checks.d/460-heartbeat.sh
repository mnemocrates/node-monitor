#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Check if heartbeat is disabled
if [[ "${HEARTBEAT_INTERVAL:-daily}" == "disabled" ]]; then
    echo "OK|Heartbeat disabled"
    echo "{\"enabled\": false}"
    exit 0
fi

stamp_file="${STATE_DIR}/last-heartbeat"
current_date=$(date +%Y-%m-%d)
current_time=$(date +%H:%M:%S)

# Determine if we should send heartbeat
send_heartbeat=false

if [[ "${HEARTBEAT_INTERVAL}" == "daily" ]]; then
    if [[ ! -f "$stamp_file" ]] || [[ "$(cat "$stamp_file")" != "$current_date" ]]; then
        send_heartbeat=true
        echo "$current_date" > "$stamp_file"
    fi
elif [[ "${HEARTBEAT_INTERVAL}" == "weekly" ]]; then
    current_week=$(date +%Y-W%V)
    if [[ ! -f "$stamp_file" ]] || [[ "$(cat "$stamp_file")" != "$current_week" ]]; then
        send_heartbeat=true
        echo "$current_week" > "$stamp_file"
    fi
fi

if $send_heartbeat; then
    # Collect system stats if enabled
    system_stats=""
    if [[ "${HEARTBEAT_INCLUDE_SYSTEM_STATS:-true}" == "true" ]]; then
        uptime_info=$(uptime | sed 's/^[^,]*up //' | sed 's/, *[0-9]* user.*//')
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
        
        # Memory info (if free command available)
        if command -v free >/dev/null 2>&1; then
            mem_info=$(free -h | awk '/^Mem:/ {printf "Mem: %s/%s (%.0f%%)", $3, $2, ($3/$2)*100}')
        else
            mem_info="Memory info unavailable"
        fi
        
        system_stats="\n\nSystem Stats:\n- Uptime: ${uptime_info}\n- Load: ${load_avg}\n- ${mem_info}"
    fi
    
    # Count check statuses
    ok_count=0
    warn_count=0
    crit_count=0
    total_count=0
    
    check_summary=""
    if [[ -d "${STATE_DIR}" ]]; then
        for state_file in "${STATE_DIR}"/*.json; do
            [[ -f "$state_file" ]] || continue
            ((total_count++))
            
            status=$(jq -r '.status // "UNKNOWN"' "$state_file" 2>/dev/null)
            case "$status" in
                OK)   ((ok_count++)) ;;
                WARN) ((warn_count++)) ;;
                CRIT) ((crit_count++)) ;;
            esac
        done
        
        check_summary="\n\nCheck Summary: ${ok_count} OK, ${warn_count} WARN, ${crit_count} CRIT (${total_count} total)"
        
        # Show failing checks if any
        if (( warn_count > 0 || crit_count > 0 )); then
            check_summary+="\n\nIssues:"
            for state_file in "${STATE_DIR}"/*.json; do
                [[ -f "$state_file" ]] || continue
                status=$(jq -r '.status // "UNKNOWN"' "$state_file" 2>/dev/null)
                if [[ "$status" == "WARN" || "$status" == "CRIT" ]]; then
                    check_name=$(basename "$state_file" .json)
                    message=$(jq -r '.message // "No message"' "$state_file" 2>/dev/null)
                    check_summary+="\n- [${status}] ${check_name}: ${message}"
                fi
            done
        fi
    fi
    
    # Send heartbeat notification
    heartbeat_message="${NODE_NAME} heartbeat: Node is operational${system_stats}${check_summary}"
    send_alert "${HEARTBEAT_INTERVAL^} Heartbeat: ${NODE_NAME}" "$heartbeat_message"
    
    echo "OK|Heartbeat sent for ${current_date} ${current_time} (${ok_count}/${total_count} checks OK)"
    echo "{\"date\": \"${current_date}\", \"time\": \"${current_time}\", \"checks\": {\"ok\": ${ok_count}, \"warn\": ${warn_count}, \"crit\": ${crit_count}, \"total\": ${total_count}}}"
else
    echo "OK|Heartbeat already sent for this ${HEARTBEAT_INTERVAL} period"
    echo "{\"date\": \"${current_date}\", \"time\": \"${current_time}\"}"
fi

exit 0

