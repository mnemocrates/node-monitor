#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

issues=()
severity="OK"
checks_passed=0
checks_total=0

# Test 1: DNS Resolution
dns_success=false
dns_time="N/A"
if [[ -n "${NETWORK_CHECK_DNS}" ]]; then
    checks_total=$((checks_total + 1))
    start_time=$(get_time_ms)
    if timeout "${NETWORK_CHECK_TIMEOUT}" host "${NETWORK_CHECK_DNS}" >/dev/null 2>&1; then
        dns_success=true
        checks_passed=$((checks_passed + 1))
        end_time=$(get_time_ms)
        dns_time=$((end_time - start_time))
    else
        issues+=("DNS resolution failed for ${NETWORK_CHECK_DNS}")
        severity="CRIT"
    fi
fi

# Test 2: ICMP Ping to configured hosts
read -ra ping_hosts <<< "$NETWORK_CHECK_HOSTS"
ping_results=()
ping_success_count=0

for host in "${ping_hosts[@]}"; do
    checks_total=$((checks_total + 1))
    if timeout "${NETWORK_CHECK_TIMEOUT}" ping -c 1 -W "${NETWORK_CHECK_TIMEOUT}" "$host" >/dev/null 2>&1; then
        ping_results+=("\"${host}\": true")
        ping_success_count=$((ping_success_count + 1))
        checks_passed=$((checks_passed + 1))
    else
        ping_results+=("\"${host}\": false")
        issues+=("Ping failed to ${host}")
    fi
done

# Severity logic: require at least one successful ping and DNS
if [[ "$dns_success" == false ]] || (( ping_success_count == 0 )); then
    severity="CRIT"
elif (( ping_success_count < ${#ping_hosts[@]} / 2 )); then
    # Less than half of pings succeeded
    severity="WARN"
elif (( ping_success_count < ${#ping_hosts[@]} )); then
    # Some pings failed, but more than half succeeded
    severity="WARN"
fi

# Test 3: Check default route
default_route_exists=false
if ip route | grep -q "^default"; then
    default_route_exists=true
fi

if [[ "$default_route_exists" == false ]]; then
    issues+=("No default route configured")
    severity="CRIT"
fi

# Build metrics JSON
metrics_json=$(printf '{"dns": {"success": %s, "host": "%s", "response_time_ms": "%s"}, "ping": {%s, "success_count": %d, "total_count": %d}, "default_route": %s, "checks_passed": %d, "checks_total": %d}' \
    "$dns_success" \
    "${NETWORK_CHECK_DNS}" \
    "$dns_time" \
    "$(IFS=,; echo "${ping_results[*]}")" \
    "$ping_success_count" \
    "${#ping_hosts[@]}" \
    "$default_route_exists" \
    "$checks_passed" \
    "$checks_total")

# Build message
if [[ "${#issues[@]}" -eq 0 ]]; then
    message="Network connectivity healthy (${checks_passed}/${checks_total} checks passed, DNS: ${dns_time}ms)"
else
    issue_str=$(IFS='; '; echo "${issues[*]}")
    message="Network connectivity issues: ${issue_str}"
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
