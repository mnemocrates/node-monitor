# node-monitor

A modular, shell-based monitoring framework for Bitcoin, LND, Tor, Electrs, and system health.

## Features
- Modular check scripts (`checks.d/`)
- Severity-based results (OK / WARN / CRIT)
- Stateful alerting (alerts only on state changes)
- ntfy, email, and Signal notification support
- Backup monitoring (daily, watcher, offsite)
- Heartbeat notifications
- Fully POSIX-compatible

## Getting Started

1. Clone the repository:

`git clone https://github.com/<yourname>/node-monitor.git`

2. Copy the example configuration:

`cp config.sh.example  config.sh`

3. Edit `config.sh` to match your environment.

4. Run the monitor:

`./run-checks.sh`


## Directory Structure
<pre>
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
</pre>
