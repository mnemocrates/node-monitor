# node-monitor

A modular, shell-based monitoring framework for Bitcoin, LND, Tor, Electrs, and system health.

## Features
- Modular check scripts (`checks.d/`)
- Severity-based results (OK / WARN / CRIT)
- Stateful alerting (alerts only on state changes)
- JSON-based state files for each check
- ntfy, email, and Signal notification support
- Backup monitoring (daily, watcher, offsite)
- Heartbeat notifications
- Fully POSIX-compatible
- Public-safe status export (optional)

## Architecture Overview

Each check script outputs:

1. A human-readable summary (STATUS|message)
2. Optional machine-readable JSON metrics

`run-checks.sh`:

- Executes all checks in numeric order
- Parses results
- Compares against previous state
- Sends alerts only on state transitions
- Writes a JSON state file per check
- Optionally exports a public-safe status snapshot

This design keeps check scripts simple while centralizing alerting and state management.

## Getting Started

1. Clone the repository:

`git clone https://github.com/mnemocrates/node-monitor.git`

2. Copy the example configuration:

`cp config.sh.example  config.sh`

3. Edit `config.sh` to match your environment.

4. Run the monitor:

`./run-checks.sh`

## Deployment

For production use, you can deploy node-monitor to a system directory using the provided deployment script.

### Automated Deployment

The `deploy.sh.example` script automates the installation process:

```bash
# Deploy to default location (/usr/local/node-monitor) with root:root ownership
sudo bash deploy.sh.example

# Deploy to a custom location
sudo INSTALL_DIR=/opt/monitoring bash deploy.sh.example

# Deploy with custom ownership (useful for service users)
sudo OWNER=bitcoin GROUP=bitcoin bash deploy.sh.example

# Combine both options
sudo INSTALL_DIR=/opt/monitoring OWNER=bitcoin GROUP=bitcoin bash deploy.sh.example
```

The deployment script will:
- Create the installation directory if it doesn't exist
- Copy all scripts, checks, and documentation
- Preserve existing `config.sh` (won't overwrite)
- Set appropriate permissions (755 for scripts, 644 for other files)
- Set ownership to root:root (or your specified user:group)
- Create necessary subdirectories (`checks.d/`, `state/`)

### Manual Deployment

If you prefer manual deployment:

```bash
# Create installation directory
sudo mkdir -p /usr/local/node-monitor

# Copy files
sudo cp -r checks.d/ /usr/local/node-monitor/
sudo cp *.sh /usr/local/node-monitor/
sudo cp config.sh.example /usr/local/node-monitor/

# Set permissions
sudo chmod 755 /usr/local/node-monitor/*.sh
sudo chmod 755 /usr/local/node-monitor/checks.d/*.sh
sudo chown -R root:root /usr/local/node-monitor

# Configure
sudo cp /usr/local/node-monitor/config.sh.example /usr/local/node-monitor/config.sh
sudo nano /usr/local/node-monitor/config.sh
```

### Automated Scheduling

After deployment, set up a cron job to run checks periodically:

```bash
# Edit crontab
crontab -e

# Add entry to run every 5 minutes
*/5 * * * * /usr/local/node-monitor/run-checks.sh

# Or run every 15 minutes
*/15 * * * * /usr/local/node-monitor/run-checks.sh
```

For nodecard exports (recommended: daily):

```bash
# Run once per day at 3 AM
0 3 * * * /usr/local/node-monitor/export-nodecard.sh
```


## Directory Structure
```
node-monitor/
├── checks.d/                 # Built-in health checks (000-499)
│   ├── 010-bitcoin-rpc.sh
│   ├── 020-bitcoin-sync-status.sh
│   ├── 030-bitcoin-blockheight.sh
│   ├── 040-bitcoin-block-age.sh
│   ├── 050-080 bitcoin-mempool-*.sh
│   ├── 100-150 lnd-*.sh
│   ├── 200-220 tor-*.sh
│   ├── 300-320 electrs-*.sh
│   ├── 400-440 system-*.sh
│   ├── 450-tor-clearnet-leak.sh
│   └── 460-heartbeat.sh
│
├── local.d/                  # Custom/site-specific checks (500-899)
│   └── README.md             # Documentation for writing custom checks
│
├── external.d/               # External monitoring checks (900-999)
│   ├── 900-external-ssh-connectivity.sh
│   ├── 910-external-bitcoin-connectivity.sh
│   ├── 920-external-electrs-connectivity.sh
│   └── 930-external-lnd-connectivity.sh
│
├── helpers.sh                # Shared helper functions (logging, retries, alerts)
├── run-checks.sh             # Main runner that executes checks.d/ and local.d/ in order
├── test-config.sh            # Validates config.sh and environment
│
├── config.sh.example         # Public-safe template (copy to config.sh)
├── .gitignore                # Protects secrets and runtime files
├── README.md                 # Project documentation
└── LICENSE                   # License
```

## Custom Checks (local.d/)

The `local.d/` directory allows you to add **site-specific custom checks** without interfering with upstream updates. Custom checks should use numbers **500-899** to run after built-in checks but before external monitoring checks.

### Benefits
- **Upgrade-safe**: Your custom checks won't be overwritten by git pulls
- **Clean separation**: Built-in checks (000-499) vs custom checks (500-899) vs external monitoring (900-999)
- **Standard pattern**: Follows Unix convention (conf.d, cron.d, etc.)

### Quick Start

1. Create a custom check script in `local.d/`:
   ```bash
   nano local.d/500-raid-status.sh
   ```

2. Follow the standard check format:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
   . "${SCRIPT_DIR}/config.sh"
   . "${SCRIPT_DIR}/helpers.sh"
   
   # Your check logic here
   
   echo "OK|RAID array healthy"
   echo '{"degraded_count": 0}'
   exit 0
   ```

3. Make it executable:
   ```bash
   chmod +x local.d/500-raid-status.sh
   ```

4. Test it:
   ```bash
   ./run-checks.sh
   ```

See [local.d/README.md](local.d/README.md) for complete documentation, including:
- Detailed format requirements
- Example templates
- Available helper functions
- Best practices

## External Monitoring

In addition to the internal checks that run on the node itself, node-monitor includes **external monitoring** capabilities to verify your node's reachability from outside your network. This is critical for detecting outages, power failures, or network connectivity issues.

### Key Features
- **Monitor from a remote VPS** - Verify node is reachable from the internet
- **Tor-only and clearnet modes** - Supports both privacy-focused and public nodes
- **Same alerting system** - Uses your existing Signal/email/ntfy configuration
- **Independent checks** - SSH, Bitcoin Core RPC, Electrs, and LND connectivity

### Use Cases
- **Tor-only nodes**: Verify hidden services are accessible without exposing clearnet IP
- **Clearnet nodes**: Monitor public endpoints and service availability
- **Power/network failures**: Get alerted if node becomes completely unreachable
- **Service validation**: Ensure external users can connect to your services

### Quick Start

1. **Deploy external monitoring scripts to your VPS:**
   ```bash
   # Copy files to VPS
   scp -r external-* user@vps:/usr/local/node-monitor/
   scp README-EXTERNAL.md user@vps:/usr/local/node-monitor/
   ```

2. **Configure connection mode and addresses:**
   ```bash
   # On VPS
   cd /usr/local/node-monitor
   cp external-config.sh.example external-config.sh
   nano external-config.sh
   
   # For Tor-only nodes: USE_TOR=true, use .onion addresses
   # For clearnet nodes: USE_TOR=false, use IP/domain names
   ```

3. **Schedule external checks via cron:**
   ```bash
   */5 * * * * /usr/local/node-monitor/run-external-checks.sh
   ```

For complete setup instructions, configuration examples, and troubleshooting, see **[README-EXTERNAL.md](README-EXTERNAL.md)**.

## Built-in Checks

The `checks.d/` directory contains 26+ built-in health checks covering Bitcoin Core, LND, Tor, Electrs, and system monitoring. Each check is independently configurable with its own thresholds and behavior settings.

For a **complete check-by-check reference** including what each check does, how it works, and its configuration options, see **[checks.d/README.md](checks.d/README.md)**.

Check categories:
- **010-040**: Bitcoin Core (RPC, sync, block height, block age)
- **050-080**: Bitcoin Mempool (usage, size, fees, unbroadcast transactions)
- **100-150**: LND (wallet, peers, channels, sync status)
- **200-220**: Tor (SOCKS proxy, circuit health, onion service)
- **300-320**: Electrs (connectivity, sync status, performance)
- **400-450**: System & Security (disk, memory, services, temperature, network, Tor-only enforcement)
- **460**: Heartbeat (daily/weekly summary notifications)
- **500-899**: Reserved for custom/local checks
- **900-999**: External monitoring (run from remote VPS)

## Configuration Reference

All configuration is done via `config.sh`. Copy `config.sh.example` to `config.sh` and customize for your environment.

### Core Settings

```bash
NODE_NAME="my-node"                    # Logical name (used in alerts)
HOSTNAME_SHORT="$(hostname -s)"         # Auto-detected hostname
```

### Binary Paths

```bash
BITCOIN_CLI="/usr/local/bin/bitcoin-cli"
LNCLI="/usr/local/bin/lncli"
SIGNAL_CLI="/usr/bin/signal-cli"
CURL_BIN="/usr/bin/curl"
NC_BIN="/usr/bin/nc"
JQ_BIN="/usr/bin/jq"
```

### LND Authentication

```bash
LND_TLSCERT="/home/user/.lnd/tls.cert"
LND_MACAROON="/home/user/.lnd/data/chain/bitcoin/mainnet/admin.macaroon"
```

### Notification Settings

**ntfy (recommended)**:
```bash
NTFY_ENABLED=true
NTFY_USE_TOR=true
NTFY_TOPIC="https://ntfy.sh/your-topic"
NTFY_TOKEN=""                          # Optional bearer token
```

**Email**:
```bash
EMAIL_ENABLED=false
EMAIL_TO="you@example.com"
EMAIL_FROM="you@example.com"
SMTP_SERVER="smtp.example.com"
SMTP_PORT=587
SMTP_USERNAME="you@example.com"
SMTP_PASSWORD="your-password"
```

**Signal**:
```bash
SIGNAL_ENABLED=false
SIGNAL_FROM="+15550000000"
SIGNAL_TO="+15550000000"
SIGNAL_TO_GROUP="group-id"
```

### Bitcoin Core Settings

```bash
BITCOIN_RPC_RETRIES=3                   # Retry attempts for RPC calls
BITCOIN_RPC_RETRY_DELAY=5               # Seconds between retries
BITCOIN_RPC_LATENCY_WARN=2000           # Warn if latency > 2s (ms)
BITCOIN_RPC_LATENCY_CRIT=5000           # Critical if latency > 5s (ms)
BITCOIN_RPC_FAILURE_GRACE=300           # Grace period before CRIT (seconds)

BITCOIN_VERIFICATION_PROGRESS_WARN=0.9999  # Warn if sync < 99.99%

BITCOIN_BLOCKHEIGHT_DRIFT_WARN=2        # Warn if drift vs external sources > 2 blocks
BITCOIN_BLOCKHEIGHT_DRIFT_CRIT=5        # Critical if drift > 5 blocks
BITCOIN_BLOCKHEIGHT_CHECK_RETRIES=3     # Retry attempts for external APIs
BITCOIN_BLOCKHEIGHT_SOURCES="https://blockstream.info/api/blocks/tip/height,..."
BITCOIN_BLOCKHEIGHT_USE_TOR=false       # Use Tor for external API calls

BITCOIN_BLOCK_AGE_WARN=1200             # Warn if last block > 20 min (seconds)
BITCOIN_BLOCK_AGE_CRIT=2400             # Critical if last block > 40 min (seconds)
```

### Mempool Settings

```bash
MEMPOOL_USAGE_WARN_HIGH=70              # Warn if usage > 70% of maxmempool
MEMPOOL_USAGE_CRIT_HIGH=90              # Critical if usage > 90%

MEMPOOL_SIZE_WARN_LOW=5                 # Warn if < 5 transactions
MEMPOOL_SIZE_CRIT_LOW=0                 # Critical if empty (with unbroadcast > 0)

MEMPOOL_MINFEE_MULTIPLIER_WARN=2.0      # Warn if mempoolminfee is 2x minrelaytxfee
MEMPOOL_MINFEE_MULTIPLIER_CRIT=5.0      # Critical if 5x minrelaytxfee

MEMPOOL_UNBROADCAST_WARN=10             # Warn if 10+ unbroadcast transactions
MEMPOOL_UNBROADCAST_CRIT=50             # Critical if 50+ unbroadcast
```

### LND Settings

```bash
LND_RPC_RETRIES=3                       # Retry attempts for LND RPC
LND_RPC_RETRY_DELAY=5                   # Seconds between retries

LND_PEERS_WARN=3                        # Warn if < 3 peers
LND_PEERS_CRIT=1                        # Critical if ≤ 1 peer

LND_CHANNELS_WARN=3                     # Warn if < 3 active channels
LND_CHANNELS_CRIT=1                     # Critical if ≤ 1 active channel
LND_CHANNELS_INACTIVE_WARN=2            # Warn if ≥ 2 inactive channels

LND_BLOCKHEIGHT_DRIFT_WARN=3            # Warn if LND vs Bitcoin drift > 3
LND_BLOCKHEIGHT_DRIFT_CRIT=10           # Critical if drift > 10

LND_CHAIN_SYNC_GRACE=300                # Grace period for chain sync (5 min)
LND_GRAPH_SYNC_GRACE=1800               # Grace period for graph sync (30 min)
```

### Tor Settings

```bash
TOR_SOCKS_HOST="127.0.0.1"
TOR_SOCKS_PORT=9050
TOR_CONTROL_PORT=9051

TOR_CHECK_RETRIES=3                     # Retry attempts for Tor checks
TOR_CHECK_RETRY_DELAY=10                # Seconds between retries
TOR_CHECK_TIMEOUT=30                    # Connection timeout (seconds)
TOR_FAILURE_CRIT_DURATION=900           # Only CRIT after 15 min of failures

# Tor-only mode enforcement
TOR_ONLY_CHECK_ENABLED=false            # Enable clearnet leak detection
TOR_CLEARNET_ALLOWED_PROCESSES="tor|systemd-timesyncd|chronyd|ntpd"
TOR_CLEARNET_ALLOWED_IPS=""            # Optional: allowed IPs
```

### Electrs Settings

```bash
ELECTRS_HOST="127.0.0.1"
ELECTRS_PORT=50001

ELECTRS_TIMEOUT=15                      # Connection timeout (seconds)
ELECTRS_RETRIES=3                       # Retry attempts
ELECTRS_RETRY_DELAY=5                   # Seconds between retries

ELECTRS_DRIFT_WARN=3                    # Warn if drift vs Bitcoin > 3 blocks
ELECTRS_DRIFT_CRIT=10                   # Critical if drift > 10 blocks

ELECTRS_RESPONSE_TIME_WARN=5000         # Warn if response > 5s (ms)
ELECTRS_RESPONSE_TIME_CRIT=15000        # Critical if response > 15s (ms)

ELECTRS_FAILURE_GRACE=300               # Grace period before CRIT (5 min)
```

### System Monitoring Settings

```bash
# Disk space
DISK_MOUNTS=""                          # Auto-detect if empty
DISK_WARN_PCT=80                        # Warn if usage > 80%
DISK_CRIT_PCT=90                        # Critical if usage > 90%
DISK_INODE_WARN_PCT=80                  # Warn if inode usage > 80%
DISK_INODE_CRIT_PCT=90                  # Critical if inode usage > 90%

# Memory
MEMORY_WARN_PCT=85                      # Warn if RAM usage > 85%
MEMORY_CRIT_PCT=95                      # Critical if RAM usage > 95%
SWAP_WARN_PCT=50                        # Warn if swap usage > 50%
SWAP_CRIT_PCT=80                        # Critical if swap usage > 80%

# Services
SERVICES_TO_MONITOR="bitcoind lnd electrs tor"
SERVICE_CHECK_METHOD="systemd"         # systemd or process

# Temperature
TEMP_WARN_CELSIUS=70                    # Warn if temp > 70°C
TEMP_CRIT_CELSIUS=80                    # Critical if temp > 80°C
TEMP_CHECK_ENABLED=true                 # Enable/disable check

# Network connectivity
NETWORK_CHECK_HOSTS="8.8.8.8 1.1.1.1"  # IPs to ping
NETWORK_CHECK_DNS="google.com"         # Domain for DNS test
NETWORK_CHECK_TIMEOUT=5                 # Timeout (seconds)
```

### Heartbeat Settings

```bash
HEARTBEAT_INTERVAL="daily"              # daily, weekly, or disabled
HEARTBEAT_INCLUDE_SYSTEM_STATS=true     # Include uptime/load/memory
```

### Alerting Behavior

```bash
STATE_DIR="/usr/local/node-monitor/state"
CHECKS_DIR="/usr/local/node-monitor/checks.d"

ALERT_ON_WARN=true                      # Send alerts for WARN status
ALERT_COOLDOWN_SECONDS=900              # 15 min cooldown between repeated alerts
```

### Status Export Settings

```bash
EXPORT_STATUS=true                      # Enable public status export
EXPORT_METHOD="scp"                     # scp, local, or none
EXPORT_TRANSPORT="torsocks"             # ssh or torsocks
EXPORT_SCP_TARGET="user@host:/path/to/status.json"
EXPORT_SCP_IDENTITY="${HOME}/.ssh/id_ed25519"
EXPORT_LOCAL_TARGET="/var/www/status.json"

# Only these checks appear in public export
PUBLIC_CHECKS=(
  "010-bitcoin-rpc"
  "020-bitcoin-blockheight"
  # ... add checks as needed
)
```

### Nodecard Export Settings

```bash
NODECARD_EXPORT_ENABLED=false           # Enable nodecard export
NODECARD_EXPORT_METHOD="scp"            # scp, local, or none
NODECARD_EXPORT_TRANSPORT="torsocks"    # ssh or torsocks
NODECARD_EXPORT_SCP_TARGET="user@host:/path/to/nodecard.json"
NODECARD_EXPORT_SCP_IDENTITY="${HOME}/.ssh/id_ed25519"
NODECARD_EXPORT_LOCAL_TARGET="/var/www/nodecard.json"
```

## JSON State Files

Each check produces a JSON file under:

`state/check-status/<check-name>.json`

Example:

```json
{
  "status": "OK",
  "message": "Bitcoin Core RPC reachable (latency=12ms)",
  "updated": "2026-01-03T04:11:59Z",
  "metrics": {
    "latency_ms": 12
  }
}
```

These files serve as the single source of truth for:

- Alerting
- State transitions
- Public export
- Future dashboards

## Public Status Export (Optional)

If enabled in `config.sh`, `export-status.sh` generates a sanitized JSON snapshot containing only checks listed in `PUBLIC_CHECKS`.

This allows you to publish a public-facing status page without exposing:
- Disk layout
- Hardware details
- Stratum/XMRig/mining activity
- Sensitive metrics
- Internal system state

Example public JSON:

```json
{
  "node": "my-node",
  "generated_at": "2026-01-03T04:12:00Z",
  "checks": {
    "010-bitcoin-rpc": { "status": "OK" },
    "120-tor-onion": { "status": "OK" }
  }
}
```

## Node Card Export (Optional)

The `export-nodecard.sh` script creates a cryptographically signed JSON document containing comprehensive node information. This is designed to be run on a separate schedule (typically daily) and is not automatically called by `run-checks.sh`.

### What's Included

The nodecard collects and exports:
- **Node identity**: alias, color, pubkey, structured endpoints (with type detection for Tor/clearnet/I2P)
- **Network info**: chains, network (mainnet/testnet), sync status
- **Channel statistics**: active/pending/inactive counts, total capacity, local/remote balances
- **Capabilities**: Detected features from node (AMP, MPP, KeySend, etc.)
- **Policy summary**: Aggregated fee policy statistics (median, min, max) across all channels
- **Links**: Pre-built URLs to popular Lightning explorers (Amboss, 1ML, Mempool)

### Cryptographic Signing

The entire JSON document is signed using `lncli signmessage` with your node's private key. The signature and the exact message that was signed are included in the exported JSON, allowing anyone to verify the authenticity using your node's public key.

**Verification**: Anyone can verify the nodecard by running:
```bash
lncli verifymessage <pubkey> <signature> <signed_message>
```

### Configuration

Enable and configure in `config.sh`:

```bash
NODECARD_EXPORT_ENABLED=true
NODECARD_EXPORT_METHOD="scp"           # scp, local, or none
NODECARD_EXPORT_TRANSPORT="torsocks"   # ssh or torsocks
NODECARD_EXPORT_SCP_TARGET="user@remote-host:/path/to/nodecard.json"
NODECARD_EXPORT_SCP_IDENTITY="${HOME}/.ssh/id_ed25519"
```

### Usage

Run manually or via cron (daily schedule recommended):

```bash
./export-nodecard.sh
```

Example output file (`nodecard.json`):

```json
{
  "alias": "MyLightningNode",
  "pubkey": "02abcdef...",
  "color": "#3399ff",
  "endpoints": [
    { "type": "tor", "addr": "02abcdef...@example.onion:9735", "preferred": true }
  ],
  "version": "0.17.0-beta",
  "chains": ["bitcoin"],
  "network": "mainnet",
  "sync": { "to_chain": true, "to_graph": true },
  "channels": {
    "active": 15,
    "pending": 0,
    "inactive": 1,
    "total_capacity": 50000000,
    "local_balance": 25000000,
    "remote_balance": 24500000
  },
  "capabilities": ["TLV Onion", "MPP", "AMP", "KeySend"],
  "policy_summary": {
    "channels_count": 15,
    "fee_base_msat": { "median": 0, "min": 0, "max": 1000 },
    "fee_rate_ppm": { "median": 100, "min": 0, "max": 500 },
    "time_lock_delta": { "median": 40, "min": 40, "max": 80 }
  },
  "links": {
    "amboss": "https://amboss.space/node/02abcdef...",
    "1ml": "https://1ml.com/node/02abcdef...",
    "mempool": "https://mempool.space/lightning/node/02abcdef..."
  },
  "last_updated": "2026-01-04T12:00:00Z",
  "signature": "3045022100...",
  "signed_message": "{\"alias\":\"MyLightningNode\",\"pubkey\":\"02abcdef...\",\"color\":\"#3399ff\",...}"
}
```

### Transport Options

Like `export-status.sh`, the nodecard can be exported:
- **Via SCP over Tor** (`.onion` addresses supported with torsocks)
- **Via standard SCP/SSH** 
- **To a local file** (useful for serving via web server)

## Writing New Checks

Each check script should:

1. Print `STATUS|message` on line 1
2. Print optional JSON metrics on line 2
3. Exit with code:
 - 0 → OK
 - 1 → WARN
 - 2 → CRIT

Example:

```bash
 echo "OK|Bitcoin Core RPC reachable (latency=12ms)"
 echo '{"latency_ms":12}'
 exit 0
```

`run-checks.sh` handles everything else.

## License

This project is released under the MIT License. See `LICENSE` for details.
