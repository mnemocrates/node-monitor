#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Parse services to monitor
read -ra services <<< "$SERVICES_TO_MONITOR"

if [[ "${#services[@]}" -eq 0 ]]; then
    echo "OK|No services configured for monitoring"
    echo "{\"services\": {}}"
    exit 0
fi

service_states=()
down_services=()
failed_services=()
severity="OK"

for service in "${services[@]}"; do
    status="unknown"
    state="unknown"
    
    if [[ "$SERVICE_CHECK_METHOD" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
        # Check via systemd
        if systemctl is-active --quiet "${service}.service" 2>/dev/null; then
            status="running"
            state="active"
        elif systemctl is-enabled --quiet "${service}.service" 2>/dev/null; then
            # Service exists but not running
            if systemctl is-failed --quiet "${service}.service" 2>/dev/null; then
                status="failed"
                state="failed"
                failed_services+=("${service}")
                severity="CRIT"
            else
                status="stopped"
                state="inactive"
                down_services+=("${service}")
                if [[ "$severity" != "CRIT" ]]; then
                    severity="WARN"
                fi
            fi
        else
            # Service not found in systemd
            status="not_found"
            state="not_found"
        fi
    else
        # Check via process name
        if pgrep -x "$service" >/dev/null 2>&1; then
            status="running"
            state="process_found"
        else
            status="stopped"
            state="process_not_found"
            down_services+=("${service}")
            if [[ "$severity" != "CRIT" ]]; then
                severity="WARN"
            fi
        fi
    fi
    
    service_states+=("\"${service}\": {\"status\": \"${status}\", \"state\": \"${state}\"}")
done

# Build metrics JSON
metrics_json=$(printf '{"services": {%s}, "method": "%s"}' "$(IFS=,; echo "${service_states[*]}")" "$SERVICE_CHECK_METHOD")

# Build message
issues=()
if [[ "${#failed_services[@]}" -gt 0 ]]; then
    issues+=("${#failed_services[@]} service(s) failed: $(IFS=,; echo "${failed_services[*]}")")
fi
if [[ "${#down_services[@]}" -gt 0 ]]; then
    issues+=("${#down_services[@]} service(s) stopped: $(IFS=,; echo "${down_services[*]}")")
fi

if [[ "${#issues[@]}" -eq 0 ]]; then
    message="All services running (${#services[@]} monitored)"
else
    issue_str=$(IFS='; '; echo "${issues[*]}")
    message="Service issues: ${issue_str}"
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
