# Privacy Protection for Exported Status

## Overview

The node-monitor system protects node privacy by automatically removing sensitive location and access information from the exported `status.json` file, while preserving this information in console output and local logs for system administration purposes.

## How It Works

### Sanitization Process

**The export-status.sh script includes automatic sanitization:**

The `sanitize_check_json()` function processes each check's JSON data before export and automatically:
- **Removes** `uri`, `URI`, `uris`, `URIs` fields completely
- **Redacts** `host`, `hostname`, `address` fields to `[REDACTED]`
- **Removes** `hosts` arrays/objects
- **Sanitizes ping results** - keeps only aggregate counts (`success_count`, `total_count`), removes individual host IPs
- **Sanitizes DNS results** - removes the specific DNS host being tested
- **Detects and redacts** arrays containing `.onion` addresses, URIs, or IP addresses

The node `hostname` field is excluded from the exported JSON to prevent system identification.

### What Is Protected

The following sensitive information is **removed or redacted** from `status.json`:

1. **Tor .onion addresses** - Your Lightning node's onion addresses
2. **IP addresses** - DNS servers, ping targets, external service IPs
3. **Hostnames** - Server hostnames, service hostnames
4. **URIs** - Any connection strings or resource identifiers
5. **Node hostname** - The short hostname of your system

### What Is Preserved

The exported `status.json` includes:

- **Node name** - Your logical node name from config
- **Timestamp** - When the status was generated
- **Check status** - OK/WARN/CRIT for each check
- **Check messages** - Status messages (generic text only)
- **Aggregate metrics** - Counts, percentages, timing data
- **Non-identifying metrics** - Block heights, mempool stats, disk usage, etc.

### What Remains Available for Administration

All sensitive information **remains visible** in:

- Console output when running checks (`run-checks.sh`)
- Local JSON state files in `${STATE_DIR}/check-status/`
- Alert messages sent via Signal/email/ntfy
- System logs

This ensures administrators can still debug and monitor the system effectively.

## Examples

### Internal JSON (full details for administration):
```json
{
  "status": "OK",
  "message": "All LND onion URIs reachable",
  "metrics": {
    "uris": [
      {
        "uri": "abc123...xyz.onion:9735",
        "status": "OK",
        "attempts": 1
      }
    ],
    "fail_count": 0,
    "total_count": 2
  }
}
```

### Exported JSON (sanitized for privacy):
```json
{
  "status": "OK",
  "message": "All LND onion URIs reachable",
  "metrics": {
    "fail_count": 0,
    "total_count": 2
  }
}
```

### Network Check - Internal:
```json
{
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
    }
  }
}
```

### Network Check - Exported:
```json
{
  "metrics": {
    "dns": {
      "success": true,
      "response_time_ms": "42"
    },
    "ping": {
      "success_count": 2,
      "total_count": 2
    }
  }
}
```

## Testing

A test script is provided at `test-sanitization.sh` to validate the sanitization logic. Run it with:

```bash
bash test-sanitization.sh
```

The test verifies:
- URIs are completely removed
- Host/IP fields are redacted
- Aggregate counts are preserved
- JSON structure remains valid

## Benefits

1. **Privacy Protection** - Your node's location and access points are not exposed
2. **Operational Transparency** - You can still publicly share node health metrics
3. **Administrative Access** - Full details remain available locally for troubleshooting
4. **Flexible Sharing** - Safe to publish status.json to public monitoring dashboards

## Design Principles

- **Backward compatible** - all check scripts work without modification
- **Sanitization layer** - only affects the exported `status.json` file
- **Non-invasive** - all internal monitoring and alerting functions operate normally with full data

## Configuration

No additional configuration is required. The sanitization is automatically applied whenever `export-status.sh` runs.

To verify your exported status is sanitized, check:
```bash
cat ${STATE_DIR}/export/status.json | jq '.' | grep -i "onion\|redacted"
```

You should see `[REDACTED]` markers instead of actual addresses/hosts.
