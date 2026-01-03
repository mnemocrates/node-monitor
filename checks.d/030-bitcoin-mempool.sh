#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

local_count="$("$BITCOIN_CLI" getmempoolinfo 2>/dev/null | jq -r '.size // 0')"
public_count="$(curl -s https://mempool.space/api/mempool 2>/dev/null | jq -r '.count // 0')"

if [[ "$local_count" -eq 0 || "$public_count" -eq 0 ]]; then
    echo "WARN|Unable to determine mempool sizes (local=${local_count}, public=${public_count})"
    echo "{\"local_count\":${local_count},\"public_count\":${public_count}}"
    exit 1
fi

# ratio = local/public (integer percent)
ratio=$(( local_count * 100 / public_count ))

if (( ratio >= 50 )); then
    echo "OK|Bitcoin mempool fullness healthy (local=${local_count}, public=${public_count}, ratio=${ratio}%)"
    echo "{\"local_count\":${local_count},\"public_count\":${public_count},\"ratio\":${ratio}}"
    exit 0
elif (( ratio >= 20 )); then
    echo "WARN|Bitcoin mempool significantly lower than public (local=${local_count}, public=${public_count}, ratio=${ratio}%)"
    echo "{\"local_count\":${local_count},\"public_count\":${public_count},\"ratio\":${ratio}}"
    exit 1
else
    echo "CRIT|Bitcoin mempool far lower than public (local=${local_count}, public=${public_count}, ratio=${ratio}%)"
    echo "{\"local_count\":${local_count},\"public_count\":${public_count},\"ratio\":${ratio}}"
    exit 2
fi

