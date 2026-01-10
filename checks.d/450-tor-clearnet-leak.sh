#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Skip if Tor-only check is disabled
if [[ "${TOR_ONLY_CHECK_ENABLED:-false}" != "true" ]]; then
    echo "OK|Tor-only clearnet leak check disabled"
    echo '{"enabled": false}'
    exit 0
fi

# Check if running with sufficient privileges
if [[ $EUID -ne 0 ]] && ! ss -tunp &>/dev/null; then
    echo "WARN|Insufficient privileges to check for clearnet leaks (requires root)"
    echo '{"has_privileges": false, "recommendation": "Run node-monitor as root or configure sudo"}'
    exit 1
fi

# State file for tracking known connections
STATE_FILE="${SCRIPT_DIR}/state/tor-clearnet-leak.json"
mkdir -p "$(dirname "$STATE_FILE")"

# Get current connections
get_clearnet_connections() {
    local output
    
    # Try ss first (modern), fall back to netstat
    if command -v ss &>/dev/null; then
        output=$(ss -tunp 2>/dev/null || true)
    elif command -v netstat &>/dev/null; then
        output=$(netstat -tunp 2>/dev/null || true)
    else
        echo "CRIT|Neither ss nor netstat available"
        echo '{"error": "no_network_tools"}'
        exit 2
    fi
    
    # Parse connections
    echo "$output" | awk '
        /^(tcp|udp)/ && /ESTAB|ESTABLISHED/ {
            # Extract destination IP:port
            if ($5 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) {
                dest = $5
            } else if ($6 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) {
                dest = $6
            } else {
                next
            }
            
            # Extract process info (varies by tool)
            process = ""
            for (i=1; i<=NF; i++) {
                if ($i ~ /users:\(\(/ || $i ~ /^[0-9]+\//) {
                    process = $i
                    break
                }
            }
            
            if (dest != "") {
                print dest "|" process
            }
        }
    '
}

# Filter out allowed connections
filter_clearnet() {
    local socks_port="${TOR_SOCKS_PORT:-9050}"
    local control_port="${TOR_CONTROL_PORT:-9051}"
    local allowed_processes="${TOR_CLEARNET_ALLOWED_PROCESSES:-tor|systemd-timesyncd|chronyd|ntpd}"
    local allowed_ips="${TOR_CLEARNET_ALLOWED_IPS:-}"
    
    while IFS='|' read -r dest process; do
        # Extract IP and port
        local ip="${dest%:*}"
        local port="${dest##*:}"
        
        # Skip localhost
        if [[ "$ip" =~ ^127\. ]] || [[ "$ip" == "::1" ]] || [[ "$ip" == "localhost" ]]; then
            continue
        fi
        
        # Skip RFC1918 private addresses
        if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$ip" =~ ^192\.168\. ]]; then
            continue
        fi
        
        # Skip link-local
        if [[ "$ip" =~ ^169\.254\. ]] || [[ "$ip" =~ ^fe80: ]]; then
            continue
        fi
        
        # Skip Tor SOCKS/Control ports (outbound to these means we're using Tor)
        if [[ "$port" == "$socks_port" ]] || [[ "$port" == "$control_port" ]]; then
            continue
        fi
        
        # Extract process name from users:((process,pid,fd)) or pid/process format
        local process_name=""
        if [[ "$process" =~ users:\(\(([^,]+) ]]; then
            process_name="${BASH_REMATCH[1]}"
        elif [[ "$process" =~ ([^/]+)$ ]]; then
            process_name="${BASH_REMATCH[1]}"
        fi
        
        # Skip allowed processes
        if [[ -n "$process_name" ]] && [[ "$process_name" =~ ^($allowed_processes)$ ]]; then
            continue
        fi
        
        # Skip allowed IPs
        if [[ -n "$allowed_ips" ]] && [[ "$ip" =~ ^($allowed_ips)$ ]]; then
            continue
        fi
        
        # This is a clearnet leak
        echo "${dest}|${process_name}"
    done
}

# Get current clearnet connections
current_leaks=$(get_clearnet_connections | filter_clearnet | sort -u)

# Load previous state
previous_leaks=""
if [[ -f "$STATE_FILE" ]]; then
    previous_leaks=$(jq -r '.known_leaks[]? // empty' "$STATE_FILE" 2>/dev/null | sort -u || true)
fi

# Find NEW leaks (not seen before)
new_leaks=$(comm -13 <(echo "$previous_leaks") <(echo "$current_leaks") | grep -v '^$' || true)

# Count leaks
leak_count=$(echo "$current_leaks" | grep -v '^$' | wc -l || echo 0)
new_leak_count=$(echo "$new_leaks" | grep -v '^$' | wc -l || echo 0)

# Build metrics
leak_list="[]"
if [[ -n "$current_leaks" ]]; then
    leak_list=$(echo "$current_leaks" | grep -v '^$' | while IFS='|' read -r dest proc; do
        echo "{\"destination\": \"$dest\", \"process\": \"${proc:-unknown}\"}"
    done | jq -s '.')
fi

# Determine status
if [[ $new_leak_count -gt 0 ]]; then
    # NEW clearnet leak detected
    leak_details=$(echo "$new_leaks" | grep -v '^$' | while IFS='|' read -r dest proc; do
        echo "${proc:-unknown} → $dest"
    done | paste -sd ', ' -)
    
    echo "CRIT|NEW clearnet leak: ${leak_details} (${new_leak_count} new, ${leak_count} total)"
    echo "{\"status\": \"leak\", \"total_leaks\": $leak_count, \"new_leaks\": $new_leak_count, \"connections\": $leak_list}"
    
    # Update state with current leaks
    jq -n --argjson leaks "$leak_list" '{
        known_leaks: ($leaks | map(.destination + "|" + .process)),
        last_updated: now | todate
    }' > "$STATE_FILE"
    
    exit 2
elif [[ $leak_count -gt 0 ]]; then
    # Known leaks, but no new ones
    leak_summary=$(echo "$current_leaks" | grep -v '^$' | while IFS='|' read -r dest proc; do
        echo "${proc:-unknown} → $dest"
    done | head -3 | paste -sd ', ' -)
    
    more_text=""
    if [[ $leak_count -gt 3 ]]; then
        more_text=" and $((leak_count - 3)) more"
    fi
    
    echo "WARN|Clearnet leak ongoing: ${leak_summary}${more_text} (${leak_count} known)"
    echo "{\"status\": \"known_leak\", \"total_leaks\": $leak_count, \"new_leaks\": 0, \"connections\": $leak_list}"
    exit 1
else
    # No leaks detected
    echo "OK|No clearnet leaks detected (Tor-only mode enforced)"
    echo "{\"status\": \"clean\", \"total_leaks\": 0, \"new_leaks\": 0, \"connections\": []}"
    
    # Clear state since there are no leaks
    echo '{"known_leaks": [], "last_updated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$STATE_FILE"
    
    exit 0
fi
