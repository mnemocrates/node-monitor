#!/usr/bin/env bash
set -euo pipefail

###############################################
# External Check Runner
# Runs monitoring checks from external VPS
# All checks are executed over Tor
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source external config
if [[ ! -f "${SCRIPT_DIR}/external-config.sh" ]]; then
    echo "ERROR: external-config.sh not found. Copy external-config.sh.example and configure it."
    exit 1
fi

. "${SCRIPT_DIR}/external-config.sh"
. "${SCRIPT_DIR}/external-helpers.sh"

# Create state directory if it doesn't exist
mkdir -p "${EXT_STATE_DIR}/check-status"

# Check if Tor is available (only required if USE_TOR=true)
if [[ "${USE_TOR}" == "true" ]]; then
    if ! test_tor_connection; then
        echo "ERROR: Tor is not available but USE_TOR=true in config."
        echo "Install: apt-get install tor torsocks"
        echo "Start: systemctl start tor"
        echo "Or set USE_TOR=false for direct connections"
        exit 1
    fi
    echo "Connection mode: Tor"
else
    echo "Connection mode: Direct (clearnet)"
fi

###############################################
# Run all external checks
###############################################

CHECKS_DIR="${SCRIPT_DIR}/external.d"
EXIT_CODE=0
RESULTS=()

echo "========================================="
echo "Running External Node Monitoring Checks"
echo "Time: $(date)"
echo "========================================="
echo

# Find and run all check scripts
for check_script in "${CHECKS_DIR}"/*.sh; do
    if [[ ! -f "$check_script" ]]; then
        continue
    fi
    
    check_name=$(basename "$check_script" .sh)
    
    # Skip if not executable
    if [[ ! -x "$check_script" ]]; then
        echo "WARN: ${check_name} is not executable, skipping"
        continue
    fi
    
    # Run the check and capture output
    check_output=$("$check_script" 2>&1 || true)
    check_exit=$?
    
    # Parse status and message
    status_line=$(echo "$check_output" | head -n 1)
    status=$(echo "$status_line" | cut -d'|' -f1)
    message=$(echo "$status_line" | cut -d'|' -f2-)
    
    # Determine color based on status
    case "$status" in
        OK)
            color='\033[0;32m'  # Green
            ;;
        WARN)
            color='\033[0;33m'  # Yellow
            EXIT_CODE=1
            ;;
        CRIT)
            color='\033[0;31m'  # Red
            EXIT_CODE=2
            ;;
        *)
            color='\033[0;37m'  # White
            ;;
    esac
    reset='\033[0m'
    
    # Print result
    printf "${color}${status}${reset}: ${check_name} - ${message}\n"
    
    # Store result for summary
    RESULTS+=("${status}|${check_name}|${message}")
done

echo
echo "========================================="
echo "External Check Summary"
echo "========================================="

# Count statuses
ok_count=0
warn_count=0
crit_count=0

for result in "${RESULTS[@]}"; do
    status=$(echo "$result" | cut -d'|' -f1)
    case "$status" in
        OK) ok_count=$((ok_count + 1)) ;;
        WARN) warn_count=$((warn_count + 1)) ;;
        CRIT) crit_count=$((crit_count + 1)) ;;
    esac
done

echo "OK: ${ok_count} | WARN: ${warn_count} | CRIT: ${crit_count}"
echo "========================================="

# Export consolidated external status JSON
if [[ -x "${SCRIPT_DIR}/export-external-status.sh" ]]; then
    "${SCRIPT_DIR}/export-external-status.sh" || \
        echo "WARN: export-external-status.sh failed (non-fatal)" >&2
else
    echo "WARN: export-external-status.sh not found or not executable" >&2
fi

exit $EXIT_CODE
