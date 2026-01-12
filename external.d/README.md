# External Monitoring Checks

This directory contains checks designed to run from an **external server** (VPS) to monitor the Bitcoin node's reachability and health from outside the local network.

## Purpose

External checks verify that the node is:
- Powered on and reachable
- Services are accessible (via Tor or clearnet)
- Services are responding correctly

## Connection Modes

### Tor-Only Mode
For privacy-focused nodes that only expose services via Tor hidden services. All checks run over Tor to prevent exposing the node's clearnet IP address.

**Set in config:** `USE_TOR=true`

### Clearnet Mode
For nodes with public IP addresses or domains. Checks connect directly without Tor overhead.

**Set in config:** `USE_TOR=false`

## Setup

1. **On the VPS (external monitoring server):**
   - For Tor-only: Install Tor: `apt-get install tor torsocks`
   - For clearnet: Install netcat and curl: `apt-get install netcat curl`
   - Ensure required services are running
   - Copy `external-config.sh.example` to `external-config.sh`
   - Configure your node's addresses and connection mode

2. **Configure addresses:**
   
   **For Tor-only nodes:**
   ```bash
   USE_TOR=true
   NODE_SSH_HOST="abcd1234....onion"
   NODE_BITCOIN_HOST="efgh5678....onion"
   NODE_ELECTRS_HOST="ijkl9012....onion"
   NODE_LND_HOST="mnop3456....onion"
   ```
   
   **For clearnet nodes:**
   ```bash
   USE_TOR=false
   NODE_SSH_HOST="node.example.com"
   NODE_BITCOIN_HOST="node.example.com"
   NODE_ELECTRS_HOST="node.example.com"
   NODE_LND_HOST="node.example.com"
   ```

3. **Run external checks:**
   ```bash
   /usr/local/node-monitor/run-external-checks.sh
   ```

4. **Schedule via cron:**
   ```
   */5 * * * * /usr/local/node-monitor/run-external-checks.sh
   ```

## Check Numbering

External checks use the 900-999 range:
- 900-909: SSH connectivity
- 910-919: Bitcoin Core connectivity
- 920-929: Electrs connectivity
- 930-939: LND connectivity
- 940-949: Status monitoring

## Available Checks

### 900-external-ssh-connectivity.sh
Verifies SSH service is reachable and responds with valid SSH banner.

### 910-external-bitcoin-connectivity.sh
Tests Bitcoin Core RPC connectivity and measures response time.

### 920-external-electrs-connectivity.sh
Tests Electrs service connectivity and protocol response.

### 930-external-lnd-connectivity.sh
Tests LND REST API connectivity and authentication.

### 940-external-status-staleness.sh
Checks if the status.json file is up-to-date. Supports both:
- **Local file mode**: Monitor a local status.json file (e.g., deployed to webserver)
- **Remote URL mode**: Fetch and check a remote status.json file via HTTP/HTTPS

Configure `STATUS_JSON_LOCAL_PATH` for local files or `STATUS_JSON_URL` for remote URLs in `external-config.sh`.

## Alerting

External checks use the same alerting mechanisms (Signal, email, ntfy) as internal checks. Configure alert settings in `external-config.sh`.
