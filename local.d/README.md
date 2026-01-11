# Custom Check Scripts (local.d)

This directory is for **site-specific custom checks** that are not part of the main node-monitor repository.

## Purpose

- Add custom monitoring checks specific to your environment
- Keep local modifications separate from upstream updates
- Safely pull updates from git without merge conflicts

## Usage

### Naming Convention

Custom checks should use numbers **500-899** to run after built-in checks:

**Note:** The 900-999 range is reserved for external monitoring checks.

```
500-custom-backup.sh
510-raid-status.sh
520-ups-battery.sh
...
```

Use increments of 10 to leave room for future additions between checks.

### Check Script Format

Follow the same format as built-in checks:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

# Your check logic here

# Output format:
# Line 1: STATUS|human-readable message
# Line 2: JSON metrics (optional)
echo "OK|My custom check passed"
echo '{"metric": "value"}'

# Exit codes:
# 0 = OK
# 1 = WARN
# 2 = CRIT
exit 0
```

### Example: Backup Check

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${SCRIPT_DIR}/config.sh"
. "${SCRIPT_DIR}/helpers.sh"

BACKUP_DIR="/mnt/backups"
BACKUP_MAX_AGE=86400  # 24 hours in seconds

latest_backup=$(find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime -1 2>/dev/null | head -1)

if [[ -z "$latest_backup" ]]; then
    echo "CRIT|No backup found in last 24 hours"
    echo "{\"backup_found\": false}"
    exit 2
fi

backup_age=$(( $(date +%s) - $(stat -c %Y "$latest_backup") ))
backup_size=$(stat -c %s "$latest_backup")

echo "OK|Latest backup $(basename "$latest_backup") is ${backup_age}s old"
echo "{\"backup_age_seconds\": ${backup_age}, \"backup_size_bytes\": ${backup_size}}"
exit 0
```

## Git Integration

The `local.d/` directory is configured in `.gitignore` to:
- Keep this README tracked (so you know the directory exists)
- Ignore all `.sh` scripts (your custom checks stay local)
- Allow safe git pulls without overwriting your custom checks

## Available Helpers

Your custom checks can use functions from `helpers.sh`:

- `lncli_safe` - LND commands with automatic TLS/macaroon paths
- `send_alert` - Send notifications via configured channels
- `write_json_state` - Write check state to JSON file
- `check_failure_duration` - Check if failure persisted beyond threshold
- `get_mempool_info_cached` - Cached Bitcoin mempool info
- `get_electrs_info_cached` - Cached Electrs info

## Number Ranges by Category

**Built-in checks (000-499):**
- 010-080: Bitcoin Core
- 100-150: LND
- 200-220: Tor
- 300-320: Electrs
- 400-450: System

**Custom checks (500-899):**
- 500-599: Recommended for general custom checks
- 600-899: Available for additional custom checks

**External monitoring (900-999):**
- 900-999: Reserved for external monitoring checks (run from remote VPS)

## State Files

Custom checks automatically create state files in:
```
state/check-status/<check-name>.json
```

These track status changes for alerting and are used by the heartbeat summary.
