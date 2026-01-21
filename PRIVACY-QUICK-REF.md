# Quick Reference: Privacy-Protected Status Export

## What Changed?

The exported `status.json` file now **automatically removes** all sensitive location information:
- ✓ .onion addresses removed
- ✓ IP addresses redacted  
- ✓ Hostnames redacted
- ✓ URIs removed
- ✓ Node hostname removed from export

## Where Can I Still See Full Details?

**Console Output:**
```bash
./run-checks.sh
# Shows all URIs, hosts, IPs in console for troubleshooting
```

**Local Status Files:**
```bash
cat ${STATE_DIR}/check-status/220-tor-onion.json
# Contains full unredacted data
```

**Alert Messages:**
- Signal, email, and ntfy alerts include full details

## What Gets Exported?

**Safe to share publicly:**
- Node name
- Check status (OK/WARN/CRIT)
- Generic messages
- Counts and percentages (fail_count, success_count)
- Block heights, mempool stats
- Disk/memory usage
- Response times

**Not exported:**
- Your .onion addresses
- IP addresses (yours or external)
- Hostnames
- Connection URIs

## Verify It's Working

Check your exported status:
```bash
cat ${STATE_DIR}/export/status.json | jq '.'
```

Look for `[REDACTED]` markers and verify no .onion addresses appear.

## Need the Old Behavior?

The local status files in `${STATE_DIR}/check-status/` contain complete unredacted information and can be used for detailed analysis or manual exports if needed.

## Example: Before vs After

**Console (unchanged):**
```
OK: 220-tor-onion - OK abc123...xyz.onion:9735
```

**Exported JSON (sanitized):**
```json
{
  "tor_onion": {
    "status": "OK",
    "metrics": {
      "fail_count": 0,
      "total_count": 2
    }
  }
}
```
