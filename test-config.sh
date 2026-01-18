#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

echo "=== Node Monitor Configuration Self-Test ==="
echo

failures=0

check() {
  local desc="$1"
  local cmd="$2"

  if eval "$cmd"; then
    printf "[OK]   %s\n" "$desc"
  else
    printf "[FAIL] %s\n" "$desc"
    failures=$((failures+1))
  fi
}

###############################################
# Binary checks
###############################################

check "bitcoin-cli exists" "[ -x \"$BITCOIN_CLI\" ]"
check "lncli exists" "[ -x \"$LNCLI\" ]"
check "signal-cli exists" "[ -x \"$SIGNAL_CLI\" ]"
check "curl exists" "[ -x \"$CURL_BIN\" ]"
check "nc exists" "[ -x \"$NC_BIN\" ]"

if [[ -n "$JQ_BIN" ]]; then
  check "jq exists" "[ -x \"$JQ_BIN\" ]"
fi

###############################################
# LND auth files (optional)
###############################################

if [[ -n "$LND_TLSCERT" ]]; then
  check "LND TLS cert readable" "[ -r \"$LND_TLSCERT\" ]"
fi

if [[ -n "$LND_MACAROON" ]]; then
  check "LND macaroon readable" "[ -r \"$LND_MACAROON\" ]"
fi

###############################################
# Bitcoin Core config file (optional)
###############################################

if [[ -n "$BITCOIN_CONF" ]]; then
  check "bitcoin.conf readable" "[ -r \"$BITCOIN_CONF\" ]"
fi

###############################################
# Directory checks
###############################################

check "state directory exists" "[ -d \"$STATE_DIR\" ]"
check "state directory writable" "[ -w \"$STATE_DIR\" ]"

check "checks.d directory exists" "[ -d \"$CHECKS_DIR\" ]"
check "checks.d directory readable" "[ -r \"$CHECKS_DIR\" ]"

###############################################
# Tor SOCKS test
###############################################

check "Tor SOCKS reachable" \
  "\"$CURL_BIN\" --socks5-hostname ${TOR_SOCKS_HOST}:${TOR_SOCKS_PORT} -s https://check.torproject.org >/dev/null 2>&1"

###############################################
# bitcoin-cli RPC test
###############################################

check "bitcoin-cli RPC works" \
  "bitcoin_cli getblockchaininfo >/dev/null 2>&1"

###############################################
# lncli test
###############################################

check "lncli getinfo works" \
  "lncli_safe getinfo >/dev/null 2>&1"

###############################################
# Signal test
###############################################

if [[ -n "${SIGNAL_TO_GROUP:-}" ]]; then
  check "signal-cli send test (group)" \
    "\"$SIGNAL_CLI\" -u \"$SIGNAL_FROM\" send -g \"$SIGNAL_TO_GROUP\" -m \"Node monitor test message\" >/dev/null 2>&1"
elif [[ -n "${SIGNAL_TO:-}" ]]; then
  check "signal-cli send test (number)" \
    "\"$SIGNAL_CLI\" -u \"$SIGNAL_FROM\" send -m \"Node monitor test message\" \"$SIGNAL_TO\" >/dev/null 2>&1"
else
  echo "[SKIP] signal-cli send test (no SIGNAL_TO or SIGNAL_TO_GROUP configured)"
fi

###############################################
# ntfy test (optional)
###############################################

if [[ "${NTFY_ENABLED:-false}" == "true" ]]; then
  check "ntfy send test" \
    "/usr/local/node-monitor/send-ntfy.sh \"Node monitor test message\" >/dev/null 2>&1"
fi

###############################################
# Email test (optional)
###############################################

if [[ "${EMAIL_ENABLED:-false}" == "true" ]]; then
  check "email send test" \
    "/usr/local/node-monitor/send-email.sh \"Node monitor test email\" \"This is a test email from btc-node-01\" >/dev/null 2>&1"
fi

###############################################
# Summary
###############################################

echo
if (( failures == 0 )); then
  echo "All configuration checks passed."
  exit 0
else
  echo "$failures configuration checks failed."
  exit 1
fi
