#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/usr/local/node-monitor/config.sh
. "${SCRIPT_DIR}/config.sh"

###############################################
# Retry helper for Tor/public checks
###############################################
retry_with_backoff() {
  local cmd="$1"
  local attempts="${2:-$RETRY_ATTEMPTS}"
  local delay="${3:-$RETRY_DELAY_SECONDS}"

  local i=1
  while (( i <= attempts )); do
    if eval "$cmd"; then
      return 0
    fi
    if (( i < attempts )); then
      sleep "${delay}"
    fi
    ((i++))
  done
  return 1
}

###############################################
# lncli wrapper (adds TLS/macaroon paths if set)
###############################################
lncli_safe() {
  local extra_args=()
  if [[ -n "${LND_TLSCERT}" ]]; then
    extra_args+=(--tlscertpath "${LND_TLSCERT}")
  fi
  if [[ -n "${LND_MACAROON}" ]]; then
    extra_args+=(--macaroonpath "${LND_MACAROON}")
  fi
  "${LNCLI}" "${extra_args[@]}" "$@"
}

###############################################
# Severity mapping
###############################################
severity_name() {
  case "$1" in
    0) echo "OK" ;;
    1) echo "WARN" ;;
    2) echo "CRIT" ;;
    *) echo "UNKNOWN" ;;
  esac
}

###############################################
# Send Alert Message
###############################################
send_alert() {
    local subject="$1"
    local message="$2"

    #
    # Signal (if configured)
    #
    if [ -n "${SIGNAL_TO_GROUP:-}" ] || [ -n "${SIGNAL_TO:-}" ]; then
        /usr/local/node-monitor/send-signal.sh "${message}" || true
    fi

    #
    # Email (if enabled)
    #
    if [ "${EMAIL_ENABLED:-false}" = "true" ]; then
        /usr/local/node-monitor/send-email.sh "${subject}" "${message}" || true
    fi

    #
    # ntfy (if enabled)
    #
    if [ "${NTFY_ENABLED:-false}" = "true" ]; then
        /usr/local/node-monitor/send-ntfy.sh "${subject}: ${message}" || true
    fi
}
