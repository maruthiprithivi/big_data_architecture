# Hybrid Architecture Quick Reference

Quick command reference for managing the hybrid Bitcoin Core + ClickHouse + Backblaze system.

## Daily Operations

### Check System Status

```bash
# All services
docker compose -f docker-compose.production.yml ps

# Bitcoin Core sync
./scripts/check-bitcoin-sync.sh

# Backfill progress
./scripts/monitor-backfill.sh

# Storage distribution
./scripts/check-storage-distribution.sh

# System health
./scripts/system-health-check.sh
```

### View Logs

```bash
# All services
docker compose -f docker-compose.production.yml logs -f

# Specific service
docker compose -f docker-compose.production.yml logs -f bitcoin-core
docker compose -f docker-compose.production.yml logs -f clickhouse
docker compose -f docker-compose.production.yml logs -f collector

# Last 100 lines
docker compose -f docker-compose.production.yml logs --tail=100 collector

# Backup logs
sudo journalctl -u clickhouse-backup.service
```

### Control Data Collection

```bash
# Start collection
curl -X POST http://localhost:8010/start

# Stop collection
curl -X POST http://localhost:8010/stop

# Check status
curl http://localhost:8010/status
```

---

## Bitcoin Core Operations

### Check Status

```bash
# Sync progress
./scripts/check-bitcoin-sync.sh

# RPC call
docker compose -f docker-compose.production.yml exec bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
    getblockchaininfo

# Block count
docker compose -f docker-compose.production.yml exec bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
    getblockcount

# Network info
docker compose -f docker-compose.production.yml exec bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
    getnetworkinfo
```

### Restart Bitcoin Core

```bash
docker compose -f docker-compose.production.yml restart bitcoin-core
```

---

## ClickHouse Operations

### Query Database

```bash
# Interactive client
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure

# Quick query
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks"

# Export to CSV
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT * FROM blockchain_data.bitcoin_blocks LIMIT 100 FORMAT CSV" > blocks.csv
```

### Common Queries

```bash
# Bitcoin blocks count
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks"

# Latest block
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT max(block_height), max(timestamp) FROM blockchain_data.bitcoin_blocks"

# Collection rate (records/second)
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT source, avg(records_collected / (collection_duration_ms / 1000)) as rate FROM blockchain_data.collection_metrics WHERE metric_time > now() - INTERVAL 1 HOUR GROUP BY source"

# Table sizes
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT table, formatReadableSize(sum(bytes)) as size FROM system.parts WHERE database = 'blockchain_data' AND active = 1 GROUP BY table"
```

### Restart ClickHouse

```bash
docker compose -f docker-compose.production.yml restart clickhouse
```

---

## Backup Operations

### Manual Backup

```bash
# Backup to Backblaze
./scripts/backup-to-backblaze.sh

# Local backup only
./scripts/backup-clickhouse.sh
```

### View Backups

```bash
# Local backups
ls -lh /var/backups/blockchain-ingestion/

# Backblaze backups
rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1

# Backup details
rclone size backblaze:typeless-crypto-data/clickhouse-backups
```

### Backup Timer

```bash
# Check timer status
sudo systemctl status clickhouse-backup.timer

# View all timers
sudo systemctl list-timers

# Run backup manually
sudo systemctl start clickhouse-backup.service

# View backup logs
sudo journalctl -u clickhouse-backup.service -n 50
```

---

## Storage Management

### Check Disk Usage

```bash
# Overall disk space
df -h /var/lib

# Bitcoin Core
du -sh /var/lib/blockchain-data/bitcoin

# ClickHouse
du -sh /var/lib/blockchain-data/clickhouse

# Storage distribution
./scripts/check-storage-distribution.sh
```

### Check Tiered Storage

```bash
# Run distribution check
./scripts/check-storage-distribution.sh

# Watch in real-time (updates every 5 minutes)
watch -n 300 ./scripts/check-storage-distribution.sh

# Manual query for disk distribution
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT disk_name, formatReadableSize(sum(bytes)) as size, count() as parts FROM system.parts WHERE database = 'blockchain_data' AND active = 1 GROUP BY disk_name"
```

---

## Troubleshooting

### Service Not Starting

```bash
# Check logs
docker compose -f docker-compose.production.yml logs bitcoin-core
docker compose -f docker-compose.production.yml logs clickhouse

# Check Docker
docker ps -a

# Restart all services
docker compose -f docker-compose.production.yml restart

# Full restart
docker compose -f docker-compose.production.yml down
docker compose -f docker-compose.production.yml up -d
```

### Bitcoin Core Not Responding

```bash
# Check if running
docker compose -f docker-compose.production.yml ps bitcoin-core

# Check logs
docker compose -f docker-compose.production.yml logs bitcoin-core

# Restart
docker compose -f docker-compose.production.yml restart bitcoin-core

# Test RPC
docker compose -f docker-compose.production.yml exec bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
    getblockchaininfo
```

### ClickHouse Connection Issues

```bash
# Test connection
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT 1"

# Check port
ss -tlnp | grep 8123

# Restart ClickHouse
docker compose -f docker-compose.production.yml restart clickhouse
```

### Collection Stuck

```bash
# Check status
curl http://localhost:8010/status

# Check logs
docker compose -f docker-compose.production.yml logs -f collector

# Restart collector
docker compose -f docker-compose.production.yml restart collector

# Stop and start
curl -X POST http://localhost:8010/stop
sleep 5
curl -X POST http://localhost:8010/start
```

### Backfill Stopped

```bash
# Check progress
./scripts/monitor-backfill.sh

# Check Bitcoin Core is responding
docker compose -f docker-compose.production.yml exec bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
    getblockchaininfo

# Check collector logs
docker compose -f docker-compose.production.yml logs -f collector

# Restart collector if needed
docker compose -f docker-compose.production.yml restart collector
curl -X POST http://localhost:8010/start
```

### Backup Failed

```bash
# Check logs
sudo journalctl -u clickhouse-backup.service -n 100

# Test rclone connection
rclone lsd backblaze:typeless-crypto-data

# Test manual backup
./scripts/backup-to-backblaze.sh

# Check disk space
df -h /var/lib
```

---

## Configuration Changes

### Update Environment Variables

```bash
# Edit .env.production
nano .env.production

# Restart services to apply changes
docker compose -f docker-compose.production.yml restart
```

### Update Bitcoin Core Config

```bash
# Edit config
nano bitcoin-core/bitcoin.conf

# Restart Bitcoin Core
docker compose -f docker-compose.production.yml restart bitcoin-core
```

### Update ClickHouse Config

```bash
# Edit storage config
nano clickhouse-config/storage.xml

# Restart ClickHouse
docker compose -f docker-compose.production.yml restart clickhouse
```

---

## Performance Monitoring

### CPU and Memory

```bash
# Real-time stats
docker stats

# Specific container
docker stats blockchain_bitcoin_core
docker stats blockchain_clickhouse_prod
docker stats blockchain_collector_prod
```

### Network

```bash
# Network traffic
docker stats --format "table {{.Name}}\t{{.NetIO}}"
```

### Disk I/O

```bash
# Install iostat if needed
sudo apt install sysstat

# Monitor disk I/O
iostat -x 1 10
```

---

## Maintenance Tasks

### Weekly

```bash
# Check system status
./scripts/system-health-check.sh

# Verify backups
rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1

# Check disk usage
df -h /var/lib

# Review logs for errors
docker compose -f docker-compose.production.yml logs --since 7d | grep -i error
```

### Monthly

```bash
# Review Backblaze costs
rclone size backblaze:typeless-crypto-data

# Analyze collection metrics
docker compose -f docker-compose.production.yml exec clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT source, count() as collections, avg(records_collected) as avg_records, avg(collection_duration_ms) as avg_duration_ms FROM blockchain_data.collection_metrics WHERE metric_time > now() - INTERVAL 30 DAY GROUP BY source"

# Update system packages (in maintenance window)
sudo apt update && sudo apt upgrade -y
```

---

## Emergency Procedures

### Stop Everything

```bash
docker compose -f docker-compose.production.yml down
```

### Restart Everything

```bash
docker compose -f docker-compose.production.yml down
docker compose -f docker-compose.production.yml up -d
```

### Restore from Backup

```bash
# List backups
rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1

# Download backup (replace BACKUP_NAME)
rclone copy backblaze:typeless-crypto-data/clickhouse-backups/BACKUP_NAME /var/lib/blockchain-data/clickhouse-restore/

# Stop ClickHouse
docker compose -f docker-compose.production.yml stop clickhouse

# Follow ClickHouse restore documentation
# (specific steps depend on backup format)

# Start ClickHouse
docker compose -f docker-compose.production.yml up -d clickhouse
```

---

## Useful Paths

```
Configuration:
  - .env.production
  - bitcoin-core/bitcoin.conf
  - clickhouse-config/storage.xml
  - docker-compose.production.yml

Data:
  - /var/lib/blockchain-data/bitcoin
  - /var/lib/blockchain-data/clickhouse
  - /var/lib/blockchain-data/collector-state

Backups:
  - /var/backups/blockchain-ingestion/
  - backblaze:typeless-crypto-data/clickhouse-backups/

Scripts:
  - scripts/check-bitcoin-sync.sh
  - scripts/monitor-backfill.sh
  - scripts/check-storage-distribution.sh
  - scripts/backup-to-backblaze.sh
  - scripts/system-health-check.sh

Logs:
  - docker compose logs
  - sudo journalctl -u clickhouse-backup.service
```

---

## Quick Aliases (Optional)

Add to `~/.bashrc` for convenience:

```bash
alias btc-sync='cd /opt/blockchain-ingestion && ./scripts/check-bitcoin-sync.sh'
alias btc-backfill='cd /opt/blockchain-ingestion && ./scripts/monitor-backfill.sh'
alias btc-storage='cd /opt/blockchain-ingestion && ./scripts/check-storage-distribution.sh'
alias btc-health='cd /opt/blockchain-ingestion && ./scripts/system-health-check.sh'
alias btc-logs='cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml logs -f'
alias btc-status='cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml ps'
```

Then: `source ~/.bashrc`

---

## Support

For detailed information:
- **HYBRID_ARCHITECTURE.md** - Complete documentation
- **HYBRID_DEPLOYMENT_CHECKLIST.md** - Deployment tracking
- **TROUBLESHOOTING.md** - Detailed troubleshooting guide
