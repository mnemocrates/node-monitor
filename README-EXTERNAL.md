# External Monitoring for Bitcoin Node

This directory contains scripts for **external monitoring** of your Bitcoin node from a remote VPS. Supports both **Tor-only** and **clearnet** node configurations.

## Overview

External monitoring ensures you are alerted if your node becomes unreachable from the internet. Unlike internal checks that run on the node itself, external checks verify connectivity from outside your network.

## Connection Modes

### Tor-Only Mode (`USE_TOR=true`)
- All connections use Tor hidden services (.onion addresses)
- Prevents exposing node's clearnet IP address
- Ideal for privacy-focused deployments
- Requires Tor and torsocks on VPS

### Clearnet Mode (`USE_TOR=false`)
- Connections use standard IP addresses or domain names
- Direct connections without Tor overhead
- Suitable for nodes with public IP/domain
- Does not require Tor on VPS

## Architecture

### Tor-Only Setup
```
┌─────────────────────┐
│   Bitcoin Node      │
│   (Tor-only)        │
│                     │
│   - SSH onion       │
│   - Bitcoin onion   │
│   - Electrs onion   │
│   - LND onion       │
└─────────────────────┘
          ▲
          │ Tor Network
          │
┌─────────┴───────────┐
│    VPS Monitor      │
│                     │
│  - Tor client       │
│  - torsocks         │
│  - Check scripts    │
└─────────────────────┘
```

### Clearnet Setup
```
┌─────────────────────┐
│   Bitcoin Node      │
│  (node.example.com) │
│                     │
│   - SSH :22         │
│   - Bitcoin :8332   │
│   - Electrs :50001  │
│   - LND :8080       │
└─────────────────────┘
          ▲
          │ Internet
          │
┌─────────┴───────────┐
│    VPS Monitor      │
│                     │
│  - Check scripts    │
│  (no Tor needed)    │
└─────────────────────┘
```

## Setup on VPS

### 1. Install Requirements

**For Tor-only nodes:**
```bash
# On your VPS
apt-get update
apt-get install -y tor torsocks curl netcat jq

# Enable and start Tor
systemctl enable tor
systemctl start tor
systemctl status tor
```

**For clearnet nodes:**
```bash
# On your VPS
apt-get update
apt-get install -y curl netcat jq
# (Tor not required)
```

### 2. Deploy Monitoring Scripts

```bash
# Create monitoring directory
sudo mkdir -p /usr/local/node-monitor
cd /usr/local/node-monitor

# Copy files from this repository
# - external-config.sh.example
# - external-helpers.sh
# - run-external-checks.sh
# - external.d/*.sh
# - send-signal.sh (if using Signal)
# - send-email.sh (if using email)
# - send-ntfy.sh (if using ntfy)

# Make scripts executable
chmod +x run-external-checks.sh
chmod +x external-helpers.sh
chmod +x external.d/*.sh
```

### 3. Configure Monitoring

```bash
# Copy and edit config
cp external-config.sh.example external-config.sh
nano external-config.sh
```

**Configuration for Tor-Only Nodes:**

```bash
# Enable Tor mode
USE_TOR=true

# Your node's Tor hidden service addresses
NODE_SSH_HOST="abcdefg1234567.onion"
NODE_BITCOIN_HOST="hijklmn7891011.onion"
NODE_ELECTRS_HOST="opqrstu1213141.onion"
NODE_LND_HOST="vwxyzab1516171.onion"

# Bitcoin Core RPC credentials
NODE_BITCOIN_RPC_USER="your_rpc_user"
NODE_BITCOIN_RPC_PASS="your_rpc_password"

# LND readonly macaroon (hex format)
NODE_LND_MACAROON_HEX="0a0b0c0d..."

# Enable alerting
SIGNAL_ENABLED=true
SIGNAL_NUMBER="+1234567890"
SIGNAL_RECIPIENTS=("+10987654321")
```

**Configuration for Clearnet Nodes:**

```bash
# Disable Tor mode (use direct connections)
USE_TOR=false

# Your node's IP address or domain name
NODE_SSH_HOST="node.example.com"         # or "192.168.1.100"
NODE_BITCOIN_HOST="node.example.com"
NODE_ELECTRS_HOST="node.example.com"
NODE_LND_HOST="node.example.com"

# Bitcoin Core RPC credentials
NODE_BITCOIN_RPC_USER="your_rpc_user"
NODE_BITCOIN_RPC_PASS="your_rpc_password"

# LND readonly macaroon (hex format)
NODE_LND_MACAROON_HEX="0a0b0c0d..."

# Enable alerting
NTFY_ENABLED=true
NTFY_TOPIC="my-node-alerts"
```

**Getting your Tor hidden service addresses (Tor-only nodes):**

```bash
# SSH onion
sudo cat /var/lib/tor/ssh/hostname

# Bitcoin onion
sudo cat /var/lib/tor/bitcoin/hostname

# Electrs onion
sudo cat /var/lib/tor/electrs/hostname

# LND onion
sudo cat /var/lib/tor/lnd-rest/hostname
```

**Getting LND readonly macaroon in hex format:**

```bash
# On the node
xxd -ps -u -c 1000 ~/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon
```

### 4. Test External Checks

```bash
# Run checks manually first
sudo /usr/local/node-monitor/run-external-checks.sh
```

Expected output:
```
=========================================
Running External Node Monitoring Checks
Time: Sat Jan 11 19:00:00 UTC 2026
=========================================

OK: 900-external-ssh-connectivity - Node reachable via SSH (Tor): 1234ms
OK: 910-external-bitcoin-connectivity - Bitcoin Core reachable (Tor): 2345ms (block 931870)
OK: 920-external-electrs-connectivity - Electrs reachable (Tor): 1567ms (block 931870)
OK: 930-external-lnd-connectivity - LND reachable (Tor): 1890ms (v0.18.0, 5 peers)

=========================================
External Check Summary
=========================================
OK: 4 | WARN: 0 | CRIT: 0
=========================================
```

### 5. Schedule via Cron

```bash
# Edit crontab
sudo crontab -e

# Add line to run checks every 5 minutes
*/5 * * * * /usr/local/node-monitor/run-external-checks.sh >> /var/log/node-monitor-external.log 2>&1
```

## External Checks

| Check | Purpose | Alert Threshold |
|-------|---------|----------------|
| **900-external-ssh-connectivity** | Verify SSH hidden service is reachable | 5 min grace period |
| **910-external-bitcoin-connectivity** | Test Bitcoin Core RPC over Tor | 5 min grace period |
| **920-external-electrs-connectivity** | Test Electrs connectivity over Tor | 5 min grace period |
| **930-external-lnd-connectivity** | Test LND REST API over Tor | 5 min grace period |

## Alerting Strategy

1. **Grace Period**: 5 minutes (300 seconds) - No alert on first failure
2. **Persistent Failure**: Alert sent if failure persists beyond grace period
3. **Alert Channels**: Same as internal monitoring (Signal/Email/ntfy)

This prevents false alerts from temporary Tor circuit issues while ensuring you're notified of real outages.

## Troubleshooting

### Tor Connection Issues (Tor-only mode)

```bash
# Check if Tor is running
systemctl status tor

# Test Tor connectivity
torsocks curl -I https://check.torproject.org/

# Check Tor logs
journalctl -u tor -n 50
```

### Clearnet Connection Issues

```bash
# Test basic connectivity
ping node.example.com

# Test port reachability
nc -zv node.example.com 22

# Check DNS resolution
dig node.example.com
```

### Check Script Issues

```bash
# Run individual check with debugging
bash -x /usr/local/node-monitor/external.d/900-external-ssh-connectivity.sh

# Check state files
ls -la /var/lib/node-monitor-external/check-status/
cat /var/lib/node-monitor-external/check-status/900-external-ssh-connectivity.json

# Verify configuration
grep USE_TOR /usr/local/node-monitor/external-config.sh
grep NODE_SSH_HOST /usr/local/node-monitor/external-config.sh
```

### Service Not Reachable

**For Tor-only nodes:**
```bash
# Test manually with torsocks
torsocks nc -v your-ssh-onion.onion 22

# Verify onion address is correct
echo "NODE_SSH_HOST: ${NODE_SSH_HOST}"

# Check from the node side
# On the node:
sudo systemctl status tor
sudo cat /var/lib/tor/ssh/hostname
```

**For clearnet nodes:**
```bash
# Test connection
nc -zv node.example.com 22

# Check firewall rules
# On the node:
sudo ufw status
sudo iptables -L -n

# Verify service is listening
# On the node:
sudo netstat -tlnp | grep :22
```

## Integration with Web Dashboard

You can expose external check status on your 0kb.io website:

```bash
# Create web-accessible status file
sudo /usr/local/node-monitor/run-external-checks.sh
sudo cp /var/lib/node-monitor-external/check-status/*.json /var/www/html/node-status/
```

Add to nginx config for status endpoint:
```nginx
location /node-status/ {
    alias /var/www/html/node-status/;
    add_header Access-Control-Allow-Origin *;
}
```

## Maintenance

- **Update addresses** if you regenerate hidden services or change IPs/domains
- **Rotate credentials** periodically (RPC password, macaroons)
- **Monitor logs** for connectivity issues
- **Test after node reboots** to ensure services come up correctly
- **Switch modes** if changing from Tor-only to clearnet or vice versa (update `USE_TOR` setting)

## Files

- `external-config.sh.example` - Configuration template
- `external-helpers.sh` - Helper functions for Tor connectivity
- `run-external-checks.sh` - Main runner script
- `external.d/` - Individual check scripts
- `README.md` - This file
