#!/usr/bin/env bash
# Test script to verify that sensitive data is properly sanitized in exports

set -euo pipefail

echo "Testing sanitization function..."

# Sample check JSON with sensitive data
test_json_tor='{
  "status": "OK",
  "message": "All LND onion URIs reachable",
  "updated": "2026-01-20T12:00:00Z",
  "metrics": {
    "uris": [
      {
        "uri": "abc123def456...xyz789.onion:9735",
        "status": "OK",
        "attempts": 1
      },
      {
        "uri": "test987fedcba...qwerty321.onion:9735",
        "status": "OK",
        "attempts": 1
      }
    ],
    "fail_count": 0,
    "total_count": 2
  }
}'

test_json_network='{
  "status": "OK",
  "message": "Network connectivity OK",
  "updated": "2026-01-20T12:00:00Z",
  "metrics": {
    "dns": {
      "success": true,
      "host": "8.8.8.8",
      "response_time_ms": "42"
    },
    "ping": {
      "1.1.1.1": true,
      "8.8.8.8": true,
      "success_count": 2,
      "total_count": 2
    },
    "default_route": true,
    "checks_passed": 3,
    "checks_total": 3
  }
}'

# Define the sanitization function (same as in export-status.sh)
sanitize_check_json() {
    local json="$1"
    
    json=$(echo "$json" | jq '
        walk(
            if type == "object" then
                del(.uri, .URI, .uris, .URIs) |
                if has("host") then 
                    if .host == "" or .host == null then . 
                    else .host = "[REDACTED]" 
                    end 
                else . end |
                if has("hostname") then 
                    if .hostname == "" or .hostname == null then . 
                    else .hostname = "[REDACTED]" 
                    end 
                else . end |
                if has("address") then 
                    if .address == "" or .address == null then . 
                    else .address = "[REDACTED]" 
                    end 
                else . end |
                if has("hosts") then del(.hosts) else . end |
                if has("ping") and (.ping | type == "object") then
                    .ping |= (
                        {success_count, total_count}
                    )
                else . end |
                if has("dns") and (.dns | type == "object") then
                    .dns |= (
                        del(.host)
                    )
                else . end
            elif type == "array" then
                if all(type == "string") and length > 0 then
                    if (.[0] | test("^[a-z0-9]{16,}\\.onion|://|@.*:|^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}")) then
                        [range(length) | "[REDACTED]"]
                    else
                        .
                    end
                else
                    .
                end
            else
                .
            end
        )
    ')
    
    echo "$json"
}

echo ""
echo "=== Test 1: Tor Onion Check ==="
echo "Before sanitization:"
echo "$test_json_tor" | jq '.metrics.uris'
echo ""
sanitized_tor=$(sanitize_check_json "$test_json_tor")
echo "After sanitization:"
echo "$sanitized_tor" | jq '.metrics.uris // "REMOVED"'
echo ""

# Verify URIs are removed
if echo "$sanitized_tor" | jq -e '.metrics.uris' >/dev/null 2>&1; then
    echo "❌ FAILED: URIs should be removed but are still present"
else
    echo "✓ PASSED: URIs successfully removed from metrics"
fi

# Verify counts are preserved
fail_count=$(echo "$sanitized_tor" | jq -r '.metrics.fail_count')
total_count=$(echo "$sanitized_tor" | jq -r '.metrics.total_count')
if [[ "$fail_count" == "0" && "$total_count" == "2" ]]; then
    echo "✓ PASSED: Counts preserved (fail_count=$fail_count, total_count=$total_count)"
else
    echo "❌ FAILED: Counts not preserved correctly"
fi

echo ""
echo "=== Test 2: Network Connectivity Check ==="
echo "Before sanitization:"
echo "$test_json_network" | jq '.metrics | {dns: .dns.host, ping: .ping}'
echo ""
sanitized_network=$(sanitize_check_json "$test_json_network")
echo "After sanitization:"
echo "$sanitized_network" | jq '.metrics | {dns, ping}'
echo ""

# Verify DNS host is removed
if echo "$sanitized_network" | jq -e '.metrics.dns.host' >/dev/null 2>&1; then
    echo "❌ FAILED: DNS host should be removed but is still present"
else
    echo "✓ PASSED: DNS host successfully removed"
fi

# Verify ping hosts are removed but counts remain
if echo "$sanitized_network" | jq -e '.metrics.ping | has("1.1.1.1")' >/dev/null 2>&1; then
    echo "❌ FAILED: Ping host IPs should be removed but are still present"
else
    echo "✓ PASSED: Ping host IPs successfully removed"
fi

ping_success=$(echo "$sanitized_network" | jq -r '.metrics.ping.success_count')
ping_total=$(echo "$sanitized_network" | jq -r '.metrics.ping.total_count')
if [[ "$ping_success" == "2" && "$ping_total" == "2" ]]; then
    echo "✓ PASSED: Ping counts preserved (success_count=$ping_success, total_count=$ping_total)"
else
    echo "❌ FAILED: Ping counts not preserved correctly"
fi

echo ""
echo "=== Test 3: Full Sanitized JSON Structure ==="
echo "Tor check sanitized:"
echo "$sanitized_tor" | jq '.'
echo ""
echo "Network check sanitized:"
echo "$sanitized_network" | jq '.'
echo ""

echo "=== Testing Complete ==="
