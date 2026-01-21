# Rolling History Feature

## Overview

The node-monitor system now maintains a rolling history of recent check results, providing operators with visibility into recent status changes and patterns over the last few hours.

## Configuration

Add these settings to your `config.sh`:

```bash
# Number of recent check results to retain
# Default: 24 checks (2 hours at 5-minute intervals)
HISTORY_SLOTS=24

# Include history in exported status.json
# Default: true
EXPORT_HISTORY=true
```

### Common Configurations

Based on 5-minute check intervals:

| HISTORY_SLOTS | Time Coverage | Use Case |
|---------------|---------------|----------|
| 12 | 1 hour | Minimal recent context |
| 24 | 2 hours | **Recommended default** |
| 48 | 4 hours | Extended recent view |
| 288 | 24 hours | Full day (higher storage) |

## How It Works

### Storage

For each check, the system maintains two files:

```
${STATE_DIR}/check-status/
├── 010-bitcoin-rpc.json           # Current state (unchanged)
└── 010-bitcoin-rpc.history.jsonl  # Rolling history
```

### History File Format (JSONL)

Each line is a compact JSON object:

```
{"t":"2026-01-20T12:00:00Z","s":"OK"}
{"t":"2026-01-20T11:55:00Z","s":"OK"}
{"t":"2026-01-20T11:50:00Z","s":"WARN"}
```

- `t` = timestamp (ISO 8601 UTC)
- `s` = status (OK/WARN/CRIT)

### Automatic Management

- **New entries** are appended on each check run
- **Old entries** are automatically trimmed when slots exceeded
- **Rotation** happens in-place (efficient tail operation)
- **No bloat** - fixed maximum size per check

## Exported JSON Structure

When `EXPORT_HISTORY=true`, the exported `status.json` includes:

```json
{
  "node": "my-node",
  "timestamp": "2026-01-20T12:00:00Z",
  "checks": {
    "bitcoin_rpc": {
      "status": "OK",
      "message": "Bitcoin RPC responding",
      "updated": "2026-01-20T12:00:00Z",
      "metrics": {
        "response_time_ms": 45
      },
      "history": [
        {"t": "2026-01-20T12:00:00Z", "s": "OK"},
        {"t": "2026-01-20T11:55:00Z", "s": "OK"},
        {"t": "2026-01-20T11:50:00Z", "s": "WARN"},
        {"t": "2026-01-20T11:45:00Z", "s": "OK"}
      ]
    }
  }
}
```

## Storage Impact

### Example: 24 Slots (2 hours @ 5min intervals)

- **Per history entry:** ~50 bytes
- **Per check history file:** 24 × 50 = ~1.2 KB
- **Total for 28 checks:** 28 × 1.2 KB = ~34 KB
- **Exported JSON increase:** +34 KB (from ~10 KB to ~44 KB)

### Example: 288 Slots (24 hours)

- **Per check history file:** 288 × 50 = ~14 KB
- **Total for 28 checks:** 28 × 14 KB = ~400 KB
- **Exported JSON increase:** +400 KB (still very reasonable)

## Performance Impact

**Per check run:**
- 1 additional append write (~50 bytes)
- 1 trim operation every ~24 runs (~1 KB read+write)
- **Total overhead:** ~0.1 seconds across all checks

**Network impact:**
- Export size increases by ~34 KB (24 slots) to ~400 KB (288 slots)
- Still well within reasonable web serving limits

## Use Cases

### 1. Quick Status Assessment

See at a glance if a service has been flapping:

```bash
cat ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl
```

### 2. Recent Incident Review

Identify when an issue started and how long it persisted:

```bash
# Count WARN/CRIT in last 24 checks
grep -c '"s":"CRIT"' ${STATE_DIR}/check-status/*.history.jsonl
```

### 3. Web Dashboard Visualization

Display recent status timeline in monitoring dashboards:

```
Bitcoin RPC: ✅ OK
Recent: ✅✅✅⚠️✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅✅
        └─11:50 WARN
```

### 4. Uptime Calculation

Calculate recent uptime percentage:

```bash
# Count OK vs total
awk '{ok+=$0~/OK/?1:0; total++} END {print ok/total*100"%"}' \
  ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl
```

## Maintenance

### Disabling History

Set `HISTORY_SLOTS=0` or comment out the variable in `config.sh`:

```bash
# HISTORY_SLOTS=24  # Disabled
```

Existing history files will remain but won't be updated.

### Clearing History

```bash
# Clear all history files
rm -f ${STATE_DIR}/check-status/*.history.jsonl

# Clear specific check
rm -f ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl
```

### Adjusting Retention

Simply change `HISTORY_SLOTS` in `config.sh`. On the next run, files will automatically trim to the new size.

## Privacy Note

History entries contain only timestamps and status codes - no sensitive information like URIs, hosts, or IP addresses. The same privacy protection that applies to current state also applies to historical data.

## Troubleshooting

### History not appearing in export

Check:
1. `EXPORT_HISTORY=true` in config.sh
2. History files exist: `ls ${STATE_DIR}/check-status/*.history.jsonl`
3. History files are not empty: `wc -l ${STATE_DIR}/check-status/*.history.jsonl`

### History files growing too large

Check `HISTORY_SLOTS` setting - it may be set too high. Reduce to a reasonable value (24-48 for most use cases).

### Corrupt history files

Simply delete and they will be regenerated:
```bash
rm -f ${STATE_DIR}/check-status/*.history.jsonl
```

## Technical Details

### JSONL Format Choice

We use JSON Lines (JSONL) format for history because:
- **Append-efficient** - just write a line, no array management
- **Trim-efficient** - use `tail` to keep last N lines
- **Human-readable** - easy to inspect with standard tools
- **Parse-efficient** - `jq -s` converts to array quickly

### Atomic Operations

- Appends use `>>` (atomic on POSIX systems)
- Trims use temp file + move (atomic on POSIX systems)
- No locks needed for single-writer scenario

### Backward Compatibility

- Existing checks work without modification
- History is optional (controlled by config)
- Current state files unchanged
- Export JSON structure extended, not replaced

## Future Enhancements

Potential future improvements:
- Add status transition timestamps to current state
- Include message snippets in history (configurable)
- Compressed history storage for long retention
- History aggregation/summarization in export
- Web UI timeline visualization components

## Examples

### View Recent Status Changes

```bash
# Pretty-print recent history for a check
jq '.' ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl

# Show only failures
jq 'select(.s != "OK")' ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl

# Count status distribution
jq -r '.s' ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl | sort | uniq -c
```

### Check Uptime Statistics

```bash
# Calculate uptime for specific check
total=$(wc -l < ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl)
ok=$(grep -c '"s":"OK"' ${STATE_DIR}/check-status/010-bitcoin-rpc.history.jsonl)
echo "Uptime: $(( ok * 100 / total ))% (${ok}/${total} checks OK)"
```

### Export History Summary

```bash
# Generate uptime report for all checks
for f in ${STATE_DIR}/check-status/*.history.jsonl; do
    name=$(basename "$f" .history.jsonl)
    total=$(wc -l < "$f")
    ok=$(grep -c '"s":"OK"' "$f" 2>/dev/null || echo 0)
    [[ $total -gt 0 ]] && echo "$name: $(( ok * 100 / total ))%"
done
```
