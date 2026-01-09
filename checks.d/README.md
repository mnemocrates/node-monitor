# checks.d/

This directory contains all modular health‑check scripts for `node-monitor`.

Each script is:

- **Single‑responsibility** — one check per file  
- **Ordered** — execution order is determined by the numeric prefix  
- **Consistent** — outputs `STATUS|MESSAGE` and exits with:
  - `0` = OK  
  - `1` = WARN  
  - `2` = CRIT  

Scripts are executed lexicographically by `run-checks.sh`, ensuring predictable and reproducible ordering.

## Check Index

- [Bitcoin Core (010-040)](#bitcoin-core-checks)
- [Bitcoin Mempool (050-080)](#bitcoin-mempool-checks)
- [LND (100-150)](#lnd-checks)
- [Tor (200-220)](#tor-checks)
- [Electrs (300-320)](#electrs-checks)
- [System & Security (400-450)](#system-and-security-checks)
- [Heartbeat (460)](#heartbeat-check)

---

## Bitcoin Core Checks

### 010-bitcoin-rpc.sh

**Purpose**: Verify Bitcoin Core RPC connectivity and performance

**How it works**:
- Attempts `bitcoin-cli getblockchaininfo` with retry logic
- Measures RPC latency in milliseconds
- Uses duration-based alerting (persistent failures only)

**Status conditions**:
- **OK**: RPC reachable, latency acceptable
- **WARN**: High latency (above `BITCOIN_RPC_LATENCY_WARN`)
- **CRIT**: RPC unreachable after retries OR extreme latency OR persistent failure beyond grace period

**Configuration**:
```bash
BITCOIN_CLI="/usr/local/bin/bitcoin-cli"
BITCOIN_RPC_RETRIES=3                    # Retry attempts
BITCOIN_RPC_RETRY_DELAY=5                # Seconds between retries
BITCOIN_RPC_LATENCY_WARN=2000            # Warn threshold (ms)
BITCOIN_RPC_LATENCY_CRIT=5000            # Critical threshold (ms)
BITCOIN_RPC_FAILURE_GRACE=300            # Grace period (seconds)
```

**Metrics**:
```json
{"latency_ms": 12, "retries_needed": 0}
```

---

### 020-bitcoin-sync-status.sh

**Purpose**: Monitor Bitcoin Core blockchain sync status

**How it works**:
- Checks `initialblockdownload` flag
- Verifies `verificationprogress` percentage
- Compares `headers` vs `blocks` count

**Status conditions**:
- **OK**: Fully synced, verification complete
- **WARN**: Verification progress below threshold OR headers/blocks mismatch
- **CRIT**: Initial Block Download (IBD) still in progress

**Configuration**:
```bash
BITCOIN_VERIFICATION_PROGRESS_WARN=0.9999  # 99.99% minimum
```

**Metrics**:
```json
{
  "verification_progress": 1.0,
  "blocks": 820000,
  "headers": 820000,
  "ibd": false
}
```

---

### 030-bitcoin-blockheight.sh

**Purpose**: Compare local block height against external sources

**How it works**:
- Queries local Bitcoin Core for block height
- Fetches height from external APIs (blockstream.info, mempool.space)
- Calculates drift (local minus external)
- Supports both clearnet and Tor for API calls

**Status conditions**:
- **OK**: Drift within acceptable range (±1 block normal due to timing)
- **WARN**: Drift exceeds `BITCOIN_BLOCKHEIGHT_DRIFT_WARN`
- **CRIT**: Drift exceeds `BITCOIN_BLOCKHEIGHT_DRIFT_CRIT` OR all external sources failed

**Configuration**:
```bash
BITCOIN_BLOCKHEIGHT_DRIFT_WARN=2         # Warn if drift > 2 blocks
BITCOIN_BLOCKHEIGHT_DRIFT_CRIT=5         # Critical if drift > 5 blocks
BITCOIN_BLOCKHEIGHT_CHECK_RETRIES=3      # Retry attempts for APIs
BITCOIN_BLOCKHEIGHT_SOURCES="https://blockstream.info/api/blocks/tip/height,https://mempool.space/api/blocks/tip/height"
BITCOIN_BLOCKHEIGHT_USE_TOR=false        # Use Tor for API calls
```

**Metrics**:
```json
{
  "local_height": 820000,
  "external_height": 820001,
  "drift": -1
}
```

---

### 040-bitcoin-block-age.sh

**Purpose**: Detect stale blocks (no new blocks received recently)

**How it works**:
- Gets timestamp of latest block via `getblockchaininfo`
- Calculates age in seconds
- Alerts if block is too old (potential network issue or stuck sync)

**Status conditions**:
- **OK**: Latest block age is reasonable (< 20 minutes)
- **WARN**: Block age exceeds `BITCOIN_BLOCK_AGE_WARN` (20 minutes)
- **CRIT**: Block age exceeds `BITCOIN_BLOCK_AGE_CRIT` (40 minutes)

**Configuration**:
```bash
BITCOIN_BLOCK_AGE_WARN=1200              # 20 minutes (seconds)
BITCOIN_BLOCK_AGE_CRIT=2400              # 40 minutes (seconds)
```

**Metrics**:
```json
{
  "block_age_seconds": 480,
  "block_height": 820000,
  "block_time": 1704672000
}
```

---

## Bitcoin Mempool Checks

These checks use shared caching (`get_mempool_info_cached()`) to avoid multiple RPC calls during a single run.

### 050-bitcoin-mempool-usage.sh

**Purpose**: Monitor mempool memory usage as percentage of maximum

**How it works**:
- Calls `getmempoolinfo` to get current usage and max
- Calculates percentage: `(usage / maxmempool) * 100`
- High usage indicates backlog or memory pressure

**Status conditions**:
- **OK**: Usage below `MEMPOOL_USAGE_WARN_HIGH`
- **WARN**: Usage exceeds warn threshold
- **CRIT**: Usage exceeds `MEMPOOL_USAGE_CRIT_HIGH`

**Configuration**:
```bash
MEMPOOL_USAGE_WARN_HIGH=70               # Warn at 70%
MEMPOOL_USAGE_CRIT_HIGH=90               # Critical at 90%
```

**Metrics**:
```json
{
  "usage_bytes": 268435456,
  "max_bytes": 536870912,
  "usage_percent": 50.0
}
```

---

### 060-bitcoin-mempool-size.sh

**Purpose**: Monitor transaction count in mempool

**How it works**:
- Checks `size` field from `getmempoolinfo`
- Unusually low counts may indicate network issues or stuck node

**Status conditions**:
- **OK**: Healthy transaction count (> 5)
- **WARN**: Very few transactions (< 5)
- **CRIT**: Empty mempool (0 transactions) while unbroadcast > 0

**Configuration**:
```bash
MEMPOOL_SIZE_WARN_LOW=5                  # Warn if < 5 txs
MEMPOOL_SIZE_CRIT_LOW=0                  # Critical if 0 txs
```

**Metrics**:
```json
{
  "size": 12543,
  "unbroadcast_count": 2
}
```

---

### 070-bitcoin-mempool-minfee.sh

**Purpose**: Detect elevated mempool minimum fee (backlog indicator)

**How it works**:
- Compares `mempoolminfee` vs `minrelaytxfee`
- Calculates multiplier: `mempoolminfee / minrelaytxfee`
- High multiplier indicates sustained high demand

**Status conditions**:
- **OK**: Minfee at or near minrelaytxfee (multiplier < 2.0)
- **WARN**: Minfee elevated (multiplier >= `MEMPOOL_MINFEE_MULTIPLIER_WARN`)
- **CRIT**: Minfee extremely elevated (>= `MEMPOOL_MINFEE_MULTIPLIER_CRIT`)

**Configuration**:
```bash
MEMPOOL_MINFEE_MULTIPLIER_WARN=2.0       # Warn if 2x baseline
MEMPOOL_MINFEE_MULTIPLIER_CRIT=5.0       # Critical if 5x baseline
```

**Metrics**:
```json
{
  "mempoolminfee": 0.00002000,
  "minrelaytxfee": 0.00001000,
  "multiplier": 2.0
}
```

---

### 080-bitcoin-mempool-unbroadcast.sh

**Purpose**: Detect transactions stuck in local mempool (not broadcast)

**How it works**:
- Checks `unbroadcastcount` from `getmempoolinfo`
- High count suggests network connectivity issues or mempool.dat problems

**Status conditions**:
- **OK**: Few or no unbroadcast transactions (< 10)
- **WARN**: Moderate count (>= `MEMPOOL_UNBROADCAST_WARN`)
- **CRIT**: High count (>= `MEMPOOL_UNBROADCAST_CRIT`)

**Configuration**:
```bash
MEMPOOL_UNBROADCAST_WARN=10              # Warn at 10
MEMPOOL_UNBROADCAST_CRIT=50              # Critical at 50
```

**Metrics**:
```json
{
  "unbroadcast_count": 3
}
```

---

## LND Checks

### 100-lnd-wallet.sh

**Purpose**: Verify LND wallet/RPC connectivity

**How it works**:
- Attempts `lncli getinfo` with retry logic
- Uses `lncli_safe` helper for TLS/macaroon authentication

**Status conditions**:
- **OK**: LND RPC reachable
- **WARN**: Slow response or partial connectivity
- **CRIT**: Unreachable after retries

**Configuration**:
```bash
LNCLI="/usr/local/bin/lncli"
LND_TLSCERT="/path/to/tls.cert"
LND_MACAROON="/path/to/admin.macaroon"
LND_RPC_RETRIES=3
LND_RPC_RETRY_DELAY=5
```

**Metrics**:
```json
{
  "connected": true,
  "retries_needed": 0
}
```

---

### 110-lnd-peers.sh

**Purpose**: Monitor Lightning Network peer connections

**How it works**:
- Queries `lncli listpeers`
- Separates inbound vs outbound peers
- Alerts if peer count drops too low

**Status conditions**:
- **OK**: Healthy peer count (>= `LND_PEERS_WARN`)
- **WARN**: Low peer count (< `LND_PEERS_WARN`)
- **CRIT**: Very few or no peers (<= `LND_PEERS_CRIT`)

**Configuration**:
```bash
LND_PEERS_WARN=3                         # Warn if < 3 peers
LND_PEERS_CRIT=1                         # Critical if <= 1 peer
```

**Metrics**:
```json
{
  "total_peers": 8,
  "inbound_peers": 3,
  "outbound_peers": 5
}
```

---

### 120-lnd-channels.sh

**Purpose**: Monitor Lightning channel status

**How it works**:
- Queries `lncli listchannels` for active/inactive/pending channels
- Tracks channel counts by state
- Alerts on low active count or high inactive count

**Status conditions**:
- **OK**: Healthy active channels, few/no inactive
- **WARN**: Low active count OR high inactive count
- **CRIT**: Very few active channels or critical inactive count

**Configuration**:
```bash
LND_CHANNELS_WARN=3                      # Warn if < 3 active
LND_CHANNELS_CRIT=1                      # Critical if <= 1 active
LND_CHANNELS_INACTIVE_WARN=2             # Warn if >= 2 inactive
```

**Metrics**:
```json
{
  "active": 12,
  "inactive": 0,
  "pending_open": 0,
  "pending_close": 0,
  "total_capacity": 50000000
}
```

---

### 130-lnd-blockheight.sh

**Purpose**: Compare LND block height vs Bitcoin Core

**How it works**:
- Gets LND block height from `getinfo`
- Gets Bitcoin Core height from `getblockchaininfo`
- Calculates drift
- Negative drift (LND behind) is problematic

**Status conditions**:
- **OK**: Heights match or within tolerance
- **WARN**: Drift exceeds `LND_BLOCKHEIGHT_DRIFT_WARN`
- **CRIT**: Drift exceeds `LND_BLOCKHEIGHT_DRIFT_CRIT`

**Configuration**:
```bash
LND_BLOCKHEIGHT_DRIFT_WARN=3             # Warn if drift > 3
LND_BLOCKHEIGHT_DRIFT_CRIT=10            # Critical if drift > 10
```

**Metrics**:
```json
{
  "lnd_height": 820000,
  "bitcoin_height": 820000,
  "drift": 0
}
```

---

### 140-lnd-chain-sync.sh

**Purpose**: Monitor LND blockchain sync status

**How it works**:
- Checks `synced_to_chain` flag from `getinfo`
- Uses grace period to avoid alerts during restarts
- Tracks failure duration via state files

**Status conditions**:
- **OK**: `synced_to_chain` is true
- **WARN**: Not synced, but within grace period
- **CRIT**: Not synced beyond grace period

**Configuration**:
```bash
LND_CHAIN_SYNC_GRACE=300                 # 5 minute grace period
```

**Metrics**:
```json
{
  "synced_to_chain": true,
  "block_height": 820000
}
```

---

### 150-lnd-graph-sync.sh

**Purpose**: Monitor Lightning graph sync status

**How it works**:
- Checks `synced_to_graph` flag from `getinfo`
- Uses longer grace period (graph sync is slower)
- Tracks failure duration

**Status conditions**:
- **OK**: `synced_to_graph` is true
- **WARN**: Not synced, but within grace period
- **CRIT**: Not synced beyond grace period

**Configuration**:
```bash
LND_GRAPH_SYNC_GRACE=1800                # 30 minute grace period
```

**Metrics**:
```json
{
  "synced_to_graph": true,
  "num_channels": 65000
}
```

---

## Tor Checks

All Tor checks include retry logic and duration-based alerting to handle transient circuit failures.

### 200-tor-socks.sh

**Purpose**: Verify Tor SOCKS5 proxy is reachable

**How it works**:
- Tests connection to Tor SOCKS port with netcat
- Retries on failure
- Uses duration-based CRIT (only if down > 15 min)

**Status conditions**:
- **OK**: SOCKS proxy reachable
- **WARN**: Temporarily unreachable, retrying
- **CRIT**: Unreachable beyond `TOR_FAILURE_CRIT_DURATION`

**Configuration**:
```bash
TOR_SOCKS_HOST="127.0.0.1"
TOR_SOCKS_PORT=9050
TOR_CHECK_RETRIES=3
TOR_CHECK_RETRY_DELAY=10
TOR_CHECK_TIMEOUT=30
TOR_FAILURE_CRIT_DURATION=900            # 15 minutes
```

**Metrics**:
```json
{
  "socks_reachable": true,
  "retries_needed": 0
}
```

---

### 210-tor-circuit.sh

**Purpose**: Verify Tor can build circuits for connections

**How it works**:
- Makes HTTP request to check.torproject.org via Tor
- Verifies response indicates Tor is working
- Retries with exponential backoff

**Status conditions**:
- **OK**: Circuit built successfully, Tor confirmed working
- **WARN**: Circuit failure, but within grace period
- **CRIT**: Persistent circuit failures beyond duration threshold

**Configuration**:
```bash
TOR_CHECK_RETRIES=3
TOR_CHECK_RETRY_DELAY=10
TOR_CHECK_TIMEOUT=30
TOR_FAILURE_CRIT_DURATION=900
```

**Metrics**:
```json
{
  "circuit_working": true,
  "response_time_ms": 3421
}
```

---

### 220-tor-onion.sh

**Purpose**: Verify LND .onion address is accessible via Tor

**How it works**:
- Extracts LND .onion address from `getinfo`
- Attempts connection via Tor SOCKS proxy
- Tests actual reachability (not just internal config)

**Status conditions**:
- **OK**: .onion address is reachable
- **WARN**: Temporarily unreachable, retrying
- **CRIT**: Persistently unreachable beyond duration threshold

**Configuration**:
```bash
TOR_CHECK_RETRIES=3
TOR_CHECK_RETRY_DELAY=10
TOR_CHECK_TIMEOUT=30
TOR_FAILURE_CRIT_DURATION=900
```

**Metrics**:
```json
{
  "onion_reachable": true,
  "onion_address": "abcdef123456.onion:9735"
}
```

---

## Electrs Checks

These checks use shared caching (`get_electrs_info_cached()`) for efficiency.

### 300-electrs-connectivity.sh

**Purpose**: Verify Electrs Electrum server is reachable

**How it works**:
- Connects to Electrs via netcat
- Sends `server.version` JSON-RPC request
- Validates response

**Status conditions**:
- **OK**: Electrs reachable, responds to queries
- **WARN**: Slow response or intermittent issues
- **CRIT**: Unreachable or not responding

**Configuration**:
```bash
ELECTRS_HOST="127.0.0.1"
ELECTRS_PORT=50001
ELECTRS_TIMEOUT=15
ELECTRS_RETRIES=3
ELECTRS_RETRY_DELAY=5
```

**Metrics**:
```json
{
  "connected": true,
  "version": "ElectrumX 1.16.0"
}
```

---

### 310-electrs-sync.sh

**Purpose**: Compare Electrs block height vs Bitcoin Core

**How it works**:
- Gets Electrs height via `blockchain.headers.subscribe`
- Compares against Bitcoin Core height
- Calculates drift

**Status conditions**:
- **OK**: Heights match or within tolerance
- **WARN**: Drift exceeds `ELECTRS_DRIFT_WARN`
- **CRIT**: Drift exceeds `ELECTRS_DRIFT_CRIT` OR persistent failure

**Configuration**:
```bash
ELECTRS_DRIFT_WARN=3
ELECTRS_DRIFT_CRIT=10
ELECTRS_FAILURE_GRACE=300                # 5 minute grace
```

**Metrics**:
```json
{
  "electrs_height": 820000,
  "bitcoin_height": 820000,
  "drift": 0
}
```

---

### 320-electrs-performance.sh

**Purpose**: Monitor Electrs response time

**How it works**:
- Measures time to complete `server.version` query
- Slow responses indicate resource contention or indexing load

**Status conditions**:
- **OK**: Response time below `ELECTRS_RESPONSE_TIME_WARN`
- **WARN**: Response time exceeds warn threshold
- **CRIT**: Response time exceeds `ELECTRS_RESPONSE_TIME_CRIT`

**Configuration**:
```bash
ELECTRS_RESPONSE_TIME_WARN=5000          # 5 seconds (ms)
ELECTRS_RESPONSE_TIME_CRIT=15000         # 15 seconds (ms)
```

**Metrics**:
```json
{
  "response_time_ms": 234
}
```

---

## System and Security Checks

### 400-disk-space.sh

**Purpose**: Monitor filesystem disk space and inode usage

**How it works**:
- Auto-detects mounted filesystems (or uses configured list)
- Checks both disk space % and inode % for each mount
- Alerts per-filesystem basis

**Status conditions**:
- **OK**: All filesystems below thresholds
- **WARN**: Any filesystem exceeds warn threshold
- **CRIT**: Any filesystem exceeds critical threshold

**Configuration**:
```bash
DISK_MOUNTS=""                           # Empty = auto-detect all
# Or specify: DISK_MOUNTS="/ /mnt/data"
DISK_WARN_PCT=80
DISK_CRIT_PCT=90
DISK_INODE_WARN_PCT=80
DISK_INODE_CRIT_PCT=90
```

**Metrics**:
```json
{
  "filesystems": [
    {
      "mount": "/",
      "usage_percent": 45,
      "inode_usage_percent": 12
    }
  ]
}
```

---

### 410-memory-usage.sh

**Purpose**: Monitor RAM and swap usage

**How it works**:
- Parses `/proc/meminfo` for RAM and swap statistics
- Calculates usage percentages
- Separate thresholds for RAM vs swap

**Status conditions**:
- **OK**: Both RAM and swap below thresholds
- **WARN**: RAM or swap exceeds warn threshold
- **CRIT**: RAM or swap exceeds critical threshold

**Configuration**:
```bash
MEMORY_WARN_PCT=85
MEMORY_CRIT_PCT=95
SWAP_WARN_PCT=50
SWAP_CRIT_PCT=80
```

**Metrics**:
```json
{
  "memory_total_kb": 8388608,
  "memory_used_kb": 6291456,
  "memory_percent": 75.0,
  "swap_total_kb": 4194304,
  "swap_used_kb": 1048576,
  "swap_percent": 25.0
}
```

---

### 420-service-status.sh

**Purpose**: Monitor status of critical system services

**How it works**:
- Checks service status via systemd (`systemctl`) or process lookup
- Verifies each service in `SERVICES_TO_MONITOR` is running
- Prefers systemd if available (more reliable)

**Status conditions**:
- **OK**: All configured services running
- **WARN**: One or more services not running (non-critical)
- **CRIT**: Critical service(s) down (e.g., bitcoind, lnd)

**Configuration**:
```bash
SERVICES_TO_MONITOR="bitcoind lnd electrs tor"
SERVICE_CHECK_METHOD="systemd"           # systemd or process
```

**Metrics**:
```json
{
  "services": [
    {"name": "bitcoind", "status": "running"},
    {"name": "lnd", "status": "running"},
    {"name": "electrs", "status": "running"},
    {"name": "tor", "status": "running"}
  ]
}
```

---

### 430-temperature.sh

**Purpose**: Monitor system temperature

**How it works**:
- Reads from multiple sources: `/sys/class/thermal/`, `sensors`, `vcgencmd` (RPi)
- Uses highest detected temperature
- Can be disabled via `TEMP_CHECK_ENABLED`

**Status conditions**:
- **OK**: Temperature below `TEMP_WARN_CELSIUS`
- **WARN**: Temperature exceeds warn threshold
- **CRIT**: Temperature exceeds `TEMP_CRIT_CELSIUS`

**Configuration**:
```bash
TEMP_WARN_CELSIUS=70
TEMP_CRIT_CELSIUS=80
TEMP_CHECK_ENABLED=true
```

**Metrics**:
```json
{
  "temperature_celsius": 58,
  "source": "thermal_zone0"
}
```

---

### 440-network-connectivity.sh

**Purpose**: Verify basic network connectivity (ping, DNS, routing)

**How it works**:
- Pings multiple hosts to verify connectivity
- Tests DNS resolution
- Checks default route exists

**Status conditions**:
- **OK**: All network tests pass
- **WARN**: Partial connectivity (some tests fail)
- **CRIT**: No connectivity (all tests fail)

**Configuration**:
```bash
NETWORK_CHECK_HOSTS="8.8.8.8 1.1.1.1"    # Space-separated IPs
NETWORK_CHECK_DNS="google.com"
NETWORK_CHECK_TIMEOUT=5
```

**Metrics**:
```json
{
  "ping_success": true,
  "dns_success": true,
  "route_exists": true
}
```

---

### 450-tor-clearnet-leak.sh

**Purpose**: Detect clearnet connections in Tor-only mode (security check)

**How it works**:
- Uses `ss -tunp` or `netstat -tunp` to list connections with process info
- Filters out allowed connections (localhost, RFC1918, Tor SOCKS/control, whitelisted processes)
- Tracks state to alert only on NEW clearnet leaks
- **Requires root privileges** to see process information

**Status conditions**:
- **WARN**: Not running as root (cannot verify)
- **CRIT**: NEW clearnet leak detected
- **WARN**: Known clearnet leak (no new ones)
- **OK**: No clearnet leaks detected

**Configuration**:
```bash
TOR_ONLY_CHECK_ENABLED=false             # Must enable explicitly
TOR_SOCKS_PORT=9050
TOR_CONTROL_PORT=9051
TOR_CLEARNET_ALLOWED_PROCESSES="tor|systemd-timesyncd|chronyd|ntpd"
TOR_CLEARNET_ALLOWED_IPS=""              # Optional whitelist
```

**Metrics**:
```json
{
  "status": "clean",
  "total_leaks": 0,
  "new_leaks": 0,
  "connections": []
}
```

**Note**: This check only runs if `TOR_ONLY_CHECK_ENABLED=true`. It gracefully degrades with a WARN if not running as root.

---

## Heartbeat Check

### 460-heartbeat.sh

**Purpose**: Daily/weekly summary notification with system stats

**How it works**:
- Checks last notification timestamp
- Sends summary based on `HEARTBEAT_INTERVAL` (daily/weekly)
- Includes: total checks, OK/WARN/CRIT counts, system uptime/load/memory
- Lists any currently failing checks

**Status conditions**:
- Always exits **OK** (heartbeat is informational, not a health check)

**Configuration**:
```bash
HEARTBEAT_INTERVAL="daily"               # daily, weekly, or disabled
HEARTBEAT_INCLUDE_SYSTEM_STATS=true
```

**Metrics**:
```json
{
  "interval": "daily",
  "total_checks": 26,
  "ok_count": 24,
  "warn_count": 1,
  "crit_count": 1,
  "uptime_seconds": 1234567,
  "load_1m": 0.45
}
```

---

## Writing Custom Checks

For site-specific checks, use the `local.d/` directory. See [../local.d/README.md](../local.d/README.md) for details.

All checks should follow this format:
1. Source `config.sh` and `helpers.sh`
2. Perform health check logic
3. Output `STATUS|message` on line 1
4. Output JSON metrics on line 2 (optional)
5. Exit with appropriate code (0=OK, 1=WARN, 2=CRIT)

Available helper functions:
- `lncli_safe` - LND commands with TLS/macaroon
- `send_alert` - Send notifications
- `write_json_state` - Write state file
- `check_failure_duration` - Duration-based alerting
- `get_mempool_info_cached` - Cached mempool info
- `get_electrs_info_cached` - Cached Electrs info

