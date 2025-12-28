# checks.d/

This directory contains all modular health‑check scripts for `node-monitor`.

Each script is:

- **Single‑responsibility** — one check per file  
- **Ordered** — execution order is determined by the numeric prefix  
- **Consistent** — outputs `STATUS|MESSAGE` and exits with:
  - `0` = OK  
  - `1` = WARN  
  - `2` = CRIT  

Example naming:

010-bitcoin-rpc.sh
020-bitcoin-blockheight.sh
030-bitcoin-mempool.sh
...
150-heartbeat.sh


Scripts are executed lexicographically by `run-checks.sh`, ensuring predictable and reproducible ordering.

