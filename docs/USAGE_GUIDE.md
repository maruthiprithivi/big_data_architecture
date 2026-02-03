# Usage Guide

A single reference for setting up, running, and using every feature in this repository.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Local Development Setup](#2-local-development-setup)
3. [Starting and Stopping](#3-starting-and-stopping)
4. [Dashboard](#4-dashboard)
5. [Collector API](#5-collector-api)
6. [Configuration Reference](#6-configuration-reference)
7. [Bitcoin Collection](#7-bitcoin-collection)
8. [Solana Collection](#8-solana-collection)
9. [Historical Backfill (Bitcoin)](#9-historical-backfill-bitcoin)
10. [State Persistence and Resume](#10-state-persistence-and-resume)
11. [Data Quality Validation](#11-data-quality-validation)
12. [Querying the Database](#12-querying-the-database)
13. [Production Deployment](#13-production-deployment)
14. [Hybrid Architecture (Bitcoin Full Node)](#14-hybrid-architecture-bitcoin-full-node)
15. [Backup and Storage Tiering](#15-backup-and-storage-tiering)
16. [Management Scripts](#16-management-scripts)
17. [Monitoring and Health Checks](#17-monitoring-and-health-checks)
18. [Safety Limits](#18-safety-limits)
19. [Troubleshooting](#19-troubleshooting)
20. [Limitations](#20-limitations)

---

## 1. Prerequisites

**Required:**

- Docker Desktop 20.10+ (`docker --version` and `docker compose version`)
- 10 GB free disk space
- Internet connection (for blockchain API access)

**Recommended:**

- Basic SQL knowledge (SELECT, WHERE, GROUP BY)
- Familiarity with REST APIs and JSON
- 8 GB RAM minimum, 16 GB recommended

**Supported platforms:** macOS, Windows 10/11 with WSL2, Linux.

---

## 2. Local Development Setup

```bash
# Clone the repository
git clone git@github.com:maruthiprithivi/big_data_architecture.git
cd big_data_architecture

# Copy the example environment file
cp .env.example .env
```

The defaults in `.env.example` work out of the box. No editing is required for a first run.

### Repository Layout

```
big_data_architecture/
  docker-compose.yml                 # Local development orchestration
  docker-compose.production.yml      # Production orchestration
  .env.example                       # Default configuration template
  clickhouse-init/
    01-init-schema.sql               # All table schemas
  collector/
    main.py                          # FastAPI service (start/stop/status/health)
    collectors/
      bitcoin_collector.py           # Bitcoin block and transaction collection
      solana_collector.py            # Solana slot and transaction collection
      data_validator.py              # Data quality checks (Veracity)
  dashboard/                         # Next.js real-time monitoring UI
  scripts/                           # Utility and deployment scripts
  docs/                              # Exercises, glossary, sample queries
```

---

## 3. Starting and Stopping

### Start all services

```bash
# Quick start
./scripts/start.sh

# Or manually
docker compose up --build -d
```

First run downloads Docker images (~2 GB) and may take several minutes. Subsequent starts take under a minute.

### Verify services are running

```bash
docker compose ps
```

All three services (clickhouse, collector, dashboard) should show status "Up". ClickHouse should show "(healthy)" after about 30 seconds.

### Stop all services

```bash
docker compose down
```

### Full cleanup (removes all data)

```bash
./scripts/cleanup.sh
```

This permanently deletes all collected blockchain data.

---

## 4. Dashboard

Open **http://localhost:3001** in a browser.

The dashboard shows seven metric cards:

| Card | Description |
|------|-------------|
| Total Records | Aggregate count across all blockchains |
| Data Size | Compressed storage used in ClickHouse |
| Ingestion Rate | Records per second since collection started |
| Bitcoin Blocks | Block count collected |
| Bitcoin Transactions | Transaction count collected |
| Solana Blocks | Slot count collected |
| Solana Transactions | Transaction count collected |

Use the Start/Stop buttons on the dashboard to control data collection.

---

## 5. Collector API

The FastAPI collector exposes a REST API on **http://localhost:8000**.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API version |
| `/start` | POST | Start data collection |
| `/stop` | POST | Stop data collection |
| `/status` | GET | Collection status with ingestion rate |
| `/health` | GET | Per-blockchain health metrics |

Interactive API documentation is available at **http://localhost:8000/docs** (Swagger UI).

### Examples

```bash
# Start collection
curl -X POST http://localhost:8000/start

# Check status
curl http://localhost:8000/status | jq

# Check health
curl http://localhost:8000/health | jq

# Stop collection
curl -X POST http://localhost:8000/stop
```

---

## 6. Configuration Reference

All settings are controlled through environment variables in the `.env` file.

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_HOST` | `clickhouse` | ClickHouse hostname (Docker service name) |
| `CLICKHOUSE_PORT` | `8123` | ClickHouse HTTP port |
| `CLICKHOUSE_USER` | `default` | ClickHouse username |
| `CLICKHOUSE_PASSWORD` | `clickhouse_password` | ClickHouse password. **Change in production.** |
| `CLICKHOUSE_DB` | `blockchain_data` | Database name |

### Blockchain Endpoints

| Variable | Default | Description |
|----------|---------|-------------|
| `BITCOIN_RPC_URL` | `https://blockstream.info/api` | Bitcoin API endpoint |
| `BITCOIN_ENABLED` | `true` | Enable Bitcoin collection |
| `SOLANA_RPC_URL` | `https://api.mainnet-beta.solana.com` | Solana RPC endpoint |
| `SOLANA_ENABLED` | `true` | Enable Solana collection |

### Collection Behavior

| Variable | Default | Description |
|----------|---------|-------------|
| `COLLECTION_INTERVAL_SECONDS` | `5` | Seconds between collection cycles |
| `BITCOIN_TX_LIMIT` | `100` | Max transactions per Bitcoin block (0 = unlimited) |
| `PARALLEL_BLOCK_FETCH_COUNT` | `1` | Concurrent Bitcoin blocks per cycle (increase for backfill) |

### Safety Limits

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_COLLECTION_TIME_MINUTES` | `10` | Auto-stop after this duration |
| `MAX_DATA_SIZE_GB` | `5` | Auto-stop when data exceeds this size |
| `ENABLE_TIME_LIMIT` | `true` | Set to `false` to disable time-based auto-stop (production) |

### Historical Backfill (Bitcoin only)

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_HISTORICAL_BACKFILL` | `false` | Start from a specific block instead of chain tip |
| `BITCOIN_START_BLOCK` | `-1` | Block height to start from when backfill is enabled |

### Hybrid Architecture (Bitcoin Core)

| Variable | Default | Description |
|----------|---------|-------------|
| `BITCOIN_USE_LOCAL_NODE` | `false` | Use a local Bitcoin Core node instead of public API |
| `BITCOIN_CORE_RPC_URL` | `http://bitcoin-core:8332` | Bitcoin Core RPC endpoint |
| `BITCOIN_CORE_RPC_USER` | (empty) | RPC username |
| `BITCOIN_CORE_RPC_PASSWORD` | (empty) | RPC password |
| `BITCOIN_PUBLIC_API_URL` | `https://blockstream.info/api` | Fallback public API |

---

## 7. Bitcoin Collection

The Bitcoin collector supports two data sources:

1. **Public API (default):** Blockstream Esplora REST API. No setup required. Subject to rate limits on the free tier.
2. **Local Bitcoin Core node:** Full blockchain access with no rate limits. Requires running a Bitcoin Core full node (see section 14).

When both are enabled, the collector tries the local node first and falls back to the public API.

### What is collected

- **Blocks:** height, hash, timestamp, previous hash, merkle root, difficulty, nonce, size, weight, transaction count.
- **Transactions:** hash, block height, size, weight, fee (satoshis), input count, output count.

### Rate limit handling

The collector detects HTTP 429 responses from the Blockstream API and backs off automatically with exponential delays. During rate limiting, parallel fetching is disabled and collection switches to sequential mode.

---

## 8. Solana Collection

The Solana collector uses JSON-RPC to collect slot data from the Solana mainnet.

### What is collected

- **Blocks (slots):** slot number, block height, hash, timestamp, parent slot, previous hash, transaction count.
- **Transactions:** signature, slot, block hash, fee (lamports), status (success/failed).

### Important characteristics

- Solana produces slots every ~400ms, so data volume is much higher than Bitcoin.
- Not every slot has a block (skipped slots are normal).
- Transactions are limited to 50 per slot for performance.
- **No historical backfill.** Solana public RPC nodes typically retain only the last ~2 days of data. Collection starts from the current slot forward.

---

## 9. Historical Backfill (Bitcoin)

Bitcoin supports collecting historical blocks starting from any height.

### Enable backfill

In `.env`:

```
ENABLE_HISTORICAL_BACKFILL=true
BITCOIN_START_BLOCK=0
PARALLEL_BLOCK_FETCH_COUNT=10
```

- `BITCOIN_START_BLOCK=0` starts from the genesis block. Set to any block height.
- `PARALLEL_BLOCK_FETCH_COUNT` controls how many blocks are fetched concurrently per cycle. Higher values catch up faster but may hit API rate limits. Values of 10-25 work well with the Blockstream API.

### How parallel fetching works

When `PARALLEL_BLOCK_FETCH_COUNT > 1` and the collector is behind the chain tip, it fetches multiple blocks concurrently using `asyncio.gather`. If any block in a batch fails, the collector only advances its position to the last contiguous successful block. Failed blocks are retried in the next cycle.

Example: if blocks 101-110 are fetched and 105 fails, the position advances to 104 only. The next cycle starts from 105.

### Disable backfill (default behavior)

When `ENABLE_HISTORICAL_BACKFILL=false` (the default), the collector starts from the current chain tip and collects new blocks as they are mined.

---

## 10. State Persistence and Resume

Both collectors save their current position to a ClickHouse table (`collector_positions`) after each successful batch. When the collector service restarts, it resumes from the saved position.

### How it works

1. On startup, the collector queries `collector_positions` for the last saved position.
2. If a saved position exists, collection resumes from that point.
3. If no saved position exists, the collector falls back to environment variable configuration (backfill settings or chain tip).
4. After each successful block/batch, the position is updated in ClickHouse.

### Inspect saved positions

```bash
docker compose exec clickhouse clickhouse-client --query \
  "SELECT * FROM blockchain_data.collector_positions FINAL FORMAT Pretty"
```

### Reset position

To restart collection from scratch, delete the saved position:

```bash
docker compose exec clickhouse clickhouse-client --query \
  "ALTER TABLE blockchain_data.collector_positions DELETE WHERE collector = 'bitcoin'"
```

Replace `'bitcoin'` with `'solana'` to reset the Solana position.

---

## 11. Data Quality Validation

Every block and transaction passes through the `DataValidator` class before insertion. This implements the Veracity dimension of the 5Vs framework.

### Checks performed

| Dimension | What is checked |
|-----------|-----------------|
| Completeness | Required fields are present and non-null |
| Accuracy | Values are within expected ranges |
| Consistency | Related fields agree (e.g., block_height <= slot for Solana) |
| Timeliness | Timestamps are reasonable (not in the future, not too old) |
| Validity | Hash formats are correct |

### Quality results

Validation results are logged and stored in the `data_quality` table:

```sql
SELECT detected_at, source, record_type, record_id, quality_level, issues
FROM data_quality
ORDER BY detected_at DESC
LIMIT 20;
```

Data with quality issues is still inserted (with warnings logged) rather than silently dropped, so no data is lost.

---

## 12. Querying the Database

### Connect to ClickHouse

```bash
# Interactive CLI
docker compose exec clickhouse clickhouse-client --password clickhouse_password

# One-off query
docker compose exec clickhouse clickhouse-client --query "SELECT count() FROM bitcoin_blocks"

# HTTP interface
curl -u default:clickhouse_password "http://localhost:8123/?query=SELECT+count()+FROM+bitcoin_blocks"
```

### Python client

```python
import clickhouse_connect

client = clickhouse_connect.get_client(
    host='localhost', port=8123,
    username='default', password='clickhouse_password',
    database='blockchain_data'
)
result = client.query("SELECT count() FROM bitcoin_blocks")
print(result.result_rows)
```

### Useful queries

**Latest Bitcoin blocks:**
```sql
SELECT block_height, timestamp, difficulty, transaction_count
FROM bitcoin_blocks
ORDER BY block_height DESC
LIMIT 10;
```

**Bitcoin fee statistics:**
```sql
SELECT
    min(fee) AS min_fee,
    max(fee) AS max_fee,
    avg(fee) AS avg_fee,
    median(fee) AS median_fee
FROM bitcoin_transactions;
```

**Solana success rate:**
```sql
SELECT
    status,
    count() AS count,
    round(count() * 100.0 / sum(count()) OVER (), 2) AS percentage
FROM solana_transactions
GROUP BY status;
```

**Cross-chain transaction count:**
```sql
SELECT 'Bitcoin' AS chain, count() AS total FROM bitcoin_transactions
UNION ALL
SELECT 'Solana' AS chain, count() AS total FROM solana_transactions;
```

**Storage compression:**
```sql
SELECT
    table,
    formatReadableSize(sum(bytes)) AS uncompressed,
    formatReadableSize(sum(bytes_on_disk)) AS compressed,
    round(100 - (sum(bytes_on_disk) / sum(bytes) * 100), 2) AS saved_pct
FROM system.parts
WHERE database = 'blockchain_data' AND active = 1
GROUP BY table;
```

**Collection progress (saved positions):**
```sql
SELECT * FROM collector_positions FINAL FORMAT Pretty;
```

**Collection metrics (last hour):**
```sql
SELECT
    source,
    max(metric_time) AS last_collect,
    sum(records_collected) AS records,
    sum(error_count) AS errors,
    round(avg(collection_duration_ms), 0) AS avg_ms
FROM collection_metrics
WHERE metric_time > now() - INTERVAL 1 HOUR
GROUP BY source;
```

For more queries, see `docs/SAMPLE_QUERIES.md`.

---

## 13. Production Deployment

Production deployment targets a remote server using `docker-compose.production.yml`.

### Key differences from development

| Setting | Development | Production |
|---------|-------------|------------|
| Time limit | 10 minutes | Disabled |
| Data limit | 5 GB | 100+ GB |
| Restart policy | Manual | `unless-stopped` |
| Data persistence | Docker volumes | Host volumes (`/var/lib/blockchain-data/`) |
| Collector API port | 8000 | 8010 |
| Parallel fetch | 1 | 10 |
| Transaction limit | 100 | 0 (unlimited) |

### Deploy to a remote server

```bash
# Configure production environment
cp .env.example .env
# Edit .env with production passwords and settings

# Deploy via script (expects SSH host "typeless_sandbox" in ~/.ssh/config)
./scripts/deploy-to-hetzner.sh
```

The deployment script:
- Detects available ClickHouse ports automatically
- Creates data directories on the host
- Builds and starts all services
- Configures automatic restart on reboot

### Manual production deployment

```bash
# Sync code to server
rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '.next' \
  --exclude 'data' --exclude '__pycache__' --exclude '.env' \
  ./ user@server:/opt/blockchain-ingestion/

# On the server
cd /opt/blockchain-ingestion
docker compose -f docker-compose.production.yml up -d --build
```

### Rebuild a single service

```bash
docker compose -f docker-compose.production.yml up -d --build collector
```

See `DEPLOYMENT.md` for the full production guide.

---

## 14. Hybrid Architecture (Bitcoin Full Node)

For complete historical data access without API rate limits, run a local Bitcoin Core full node alongside the collector.

### Setup

```bash
# Install Bitcoin Core on the server
./scripts/install-bitcoin-core.sh

# Monitor sync progress
./scripts/check-bitcoin-sync.sh
```

Bitcoin Core initial sync downloads and validates the entire blockchain (~500 GB). This takes days to weeks depending on hardware and network speed.

### Enable in the collector

In `.env`:

```
BITCOIN_USE_LOCAL_NODE=true
BITCOIN_CORE_RPC_URL=http://bitcoin-core:8332
BITCOIN_CORE_RPC_USER=blockchain_collector
BITCOIN_CORE_RPC_PASSWORD=your_rpc_password
```

The collector tries the local node first. If it fails (node syncing, maintenance), it falls back to the public Blockstream API automatically.

### Enable disk pruning

Once the initial sync is complete, pruning reduces storage from ~500 GB to ~10 GB while keeping the collector functional:

```bash
./scripts/enable-bitcoin-pruning.sh
```

### Production compose

The `docker-compose.production.yml` file includes a `bitcoin-core` service definition. It persists data to `/var/lib/blockchain-data/bitcoin` on the host.

---

## 15. Backup and Storage Tiering

### Backups

```bash
# Manual backup
./scripts/backup-clickhouse.sh

# Backup to Backblaze B2
./scripts/backup-to-backblaze.sh
```

Backblaze integration requires configuring rclone:

```bash
./scripts/setup-rclone.sh
```

### S3 storage tiering

ClickHouse can be configured to move cold data to S3-compatible storage (Backblaze B2). The `clickhouse-config/storage.xml` file defines hot/cold tiers. The `clickhouse-init/02-enable-tiering.sql` script sets up the tiering policies.

```bash
# Check storage distribution
./scripts/check-storage-distribution.sh
```

---

## 16. Management Scripts

All scripts are in the `scripts/` directory.

### Development

| Script | Purpose |
|--------|---------|
| `start.sh` | Start all services (`docker compose up --build -d`) |
| `cleanup.sh` | Remove all containers, volumes, and data |

### Production management

| Script | Purpose |
|--------|---------|
| `manage.sh start` | Start all Docker services |
| `manage.sh stop` | Stop all Docker services |
| `manage.sh restart` | Restart all Docker services |
| `manage.sh status` | Show service status |
| `manage.sh logs [service]` | Show logs |
| `manage.sh start-collection` | Start data collection via API |
| `manage.sh stop-collection` | Stop data collection via API |
| `manage.sh health` | Run health check |
| `manage.sh stats` | Show collection statistics |

### Deployment

| Script | Purpose |
|--------|---------|
| `deploy-to-hetzner.sh` | Full deployment to remote server |
| `update.sh` | Zero-downtime update on remote server |
| `detect-ports.sh` | Find available ClickHouse ports |

### Bitcoin Core

| Script | Purpose |
|--------|---------|
| `install-bitcoin-core.sh` | Install Bitcoin Core on server |
| `check-bitcoin-sync.sh` | Monitor blockchain sync progress |
| `start-historical-backfill.sh` | Start collecting from genesis block |
| `monitor-backfill.sh` | Track backfill progress |
| `enable-bitcoin-pruning.sh` | Enable disk pruning after sync |

### Monitoring and backup

| Script | Purpose |
|--------|---------|
| `health-check.sh` | Comprehensive health check |
| `system-health-check.sh` | Full system validation |
| `monitor-and-alert.sh` | Check health and send alerts |
| `monitor-data-growth.sh` | Track data volume growth |
| `backup-clickhouse.sh` | Create ClickHouse backup |
| `backup-to-backblaze.sh` | Backup to Backblaze B2 |
| `setup-rclone.sh` | Configure Backblaze integration |
| `check-storage-distribution.sh` | Show hot/cold storage split |

---

## 17. Monitoring and Health Checks

### Health endpoint

```bash
curl http://localhost:8000/health | jq
```

Returns per-blockchain metrics:
- `healthy` / `degraded` / `unhealthy` status
- Last collection timestamp and seconds since last collect
- Records collected in the last 5 minutes
- Error count and average collection duration

### Collection metrics in ClickHouse

```sql
SELECT
    source,
    max(metric_time) AS last_collect,
    sum(records_collected) AS records,
    sum(error_count) AS errors,
    round(avg(collection_duration_ms), 0) AS avg_ms
FROM collection_metrics
WHERE metric_time > now() - INTERVAL 5 MINUTE
GROUP BY source;
```

### Automated monitoring (production)

```bash
# Install daily health check cron job
./scripts/setup-sync-cron.sh

# Manual health check
./scripts/system-health-check.sh
```

---

## 18. Safety Limits

Safety limits prevent runaway collection in development and teaching environments.

- **Time limit:** Collection auto-stops after `MAX_COLLECTION_TIME_MINUTES` (default: 10).
- **Size limit:** Collection auto-stops when data exceeds `MAX_DATA_SIZE_GB` (default: 5 GB).

### Disable for production

In `.env`:

```
ENABLE_TIME_LIMIT=false
MAX_COLLECTION_TIME_MINUTES=525600
MAX_DATA_SIZE_GB=500
```

Limits are checked at the start of each collection cycle. When a limit is reached, collection stops gracefully and the state is updated in the `collection_state` table.

---

## 19. Troubleshooting

### Services fail to start

```bash
docker compose logs clickhouse
docker compose logs collector
docker compose logs dashboard
```

### Collector not collecting data

1. Verify collection is started: `curl http://localhost:8000/status`
2. Check health: `curl http://localhost:8000/health | jq`
3. Check logs for rate limits: `docker logs blockchain-collector 2>&1 | grep -i "rate\|429"`
4. Increase `COLLECTION_INTERVAL_SECONDS` if rate limited

### No data in dashboard

1. Confirm collection is running (check dashboard or `/status` endpoint)
2. Verify data exists: `docker compose exec clickhouse clickhouse-client --query "SELECT count() FROM bitcoin_blocks"`
3. Check dashboard container: `docker compose logs dashboard`

### ClickHouse connection errors

ClickHouse may take up to 30 seconds to become healthy on first start. The collector waits for the `service_healthy` condition before starting.

```bash
docker compose restart collector
```

### Rate limit errors (Bitcoin)

The collector handles rate limits automatically with exponential backoff. If persistent:
- Increase `COLLECTION_INTERVAL_SECONDS` to 10-30
- Reduce `PARALLEL_BLOCK_FETCH_COUNT` to 1
- Consider using a local Bitcoin Core node

### Reset everything

```bash
./scripts/cleanup.sh
docker compose up --build -d
```

---

## 20. Limitations

- **Public RPC limits:** Free Blockstream and Solana endpoints have rate limits and may be temporarily unavailable.
- **Solana no backfill:** Solana collection starts from the current slot only. Public nodes retain approximately 2 days of history.
- **Bitcoin transaction sampling:** Limited to `BITCOIN_TX_LIMIT` transactions per block (default 100, set to 0 for unlimited).
- **Solana transaction sampling:** Limited to 50 transactions per slot.
- **Ethereum disabled:** Ethereum collection code exists but is disabled. It requires a paid API key from Infura or Alchemy.
- **Single instance:** The collector is designed to run as a single instance. Running multiple instances against the same ClickHouse database may cause duplicate data.

---

## Further Reading

- `docs/EXERCISES.md` -- Nine progressive hands-on exercises
- `docs/GLOSSARY.md` -- Blockchain and data engineering terminology
- `docs/SAMPLE_QUERIES.md` -- ClickHouse SQL query patterns
- `docs/TROUBLESHOOTING.md` -- Extended troubleshooting guide
- `DEPLOYMENT.md` -- Full production deployment guide
- `HYBRID_ARCHITECTURE.md` -- Bitcoin Core full node setup
