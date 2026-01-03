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


## Directory Structure
```
node-monitor/
├── checks.d/                 # Modular health checks (010-, 020-, 030-...)
│   ├── 010-bitcoin-rpc.sh
│   ├── 020-bitcoin-blockheight.sh
│   ├── 030-bitcoin-mempool.sh
│   ├── 040-lnd-wallet.sh
│   ├── 050-lnd-peers.sh
│   ├── 060-lnd-channels.sh
│   ├── 070-lnd-blockheight.sh
│   ├── 080-lnd-chain-sync.sh
│   ├── 090-lnd-graph-sync.sh
│   ├── 100-tor-socks.sh
│   ├── 110-tor-circuit.sh
│   ├── 120-tor-onion.sh
│   ├── 130-electrs-sync.sh
│   ├── 140-disk-space.sh
│   └── 150-heartbeat.sh
│
├── helpers.sh                # Shared helper functions (logging, retries, alerts)
├── run-checks.sh             # Main runner that executes checks.d/ in order
├── test-config.sh            # Validates config.sh and environment
│
├── config.sh.example         # Public-safe template (copy to config.sh)
├── .gitignore                # Protects secrets and runtime files
├── README.md                 # Project documentation
└── LICENSE                   # License

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
- XMRig/mining activity
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

`run-checks.sh` handles everything else.

## License

This project is released under the MIT License. See `LICENSE` for details.