# Hybrid Bitcoin Core + ClickHouse + Backblaze Architecture

This document describes the hybrid architecture implementation that transforms the blockchain data collection system from public API-based to a self-hosted architecture with Bitcoin Core, ClickHouse tiered storage, and Backblaze backups.

## Architecture Overview

- **Bitcoin Core**: Full node (initially 650 GB, pruned to 200 GB)
- **ClickHouse v26.1**: With tiered storage (200 GB hot local + Backblaze cold)
- **Automated Daily Backups**: To Backblaze with 30-day retention
- **Complete Historical Data**: In ClickHouse for analysis

**Timeline**: 4-6 weeks
**Peak Storage**: ~850 GB (650 GB Bitcoin + 200 GB ClickHouse)
**Available Space**: 1.8 TB on Hetzner (sufficient)

## Implementation Phases

### Phase 1: Bitcoin Core Installation and Sync (7-14 days)

Install and sync Bitcoin Core full node.

**Steps:**

1. Install Bitcoin Core:
   ```bash
   ./scripts/install-bitcoin-core.sh
   ```

2. Monitor sync progress daily:
   ```bash
   ./scripts/check-bitcoin-sync.sh
   ```

3. View logs if needed:
   ```bash
   docker compose -f docker-compose.production.yml logs -f bitcoin-core
   ```

**Expected Duration**: 7-14 days depending on network and hardware

**Disk Usage**: Will grow to ~650 GB

**Impact**: None - existing collection continues normally via public API

---

### Phase 2: Historical Backfill (2-4 weeks)

Collect all historical Bitcoin blocks from genesis using the local node.

**Prerequisites**: Bitcoin Core sync complete (blocks == headers)

**Steps:**

1. Verify Bitcoin Core is synced:
   ```bash
   ./scripts/check-bitcoin-sync.sh
   ```

2. Start historical backfill:
   ```bash
   ./scripts/start-historical-backfill.sh
   ```

3. Monitor backfill progress:
   ```bash
   ./scripts/monitor-backfill.sh
   ```

   Or watch continuously:
   ```bash
   watch -n 300 ./scripts/monitor-backfill.sh  # Updates every 5 minutes
   ```

4. View collector logs:
   ```bash
   docker compose -f docker-compose.production.yml logs -f collector
   ```

**Configuration:**
- Uses local Bitcoin Core RPC
- Parallel fetching: 50 blocks at once
- Starts from block 0 (genesis)
- No transaction limit (collects all transactions)

**Expected Duration**: 2-4 weeks to collect 880,000+ blocks

**Storage Impact**: ClickHouse data will grow to ~200 GB

---

### Phase 3: Bitcoin Core Pruning (1-2 hours)

Enable pruning to reduce Bitcoin Core disk usage from 650 GB to 200 GB.

**Prerequisites**: Historical backfill complete

**Steps:**

1. Verify backfill is complete:
   ```bash
   ./scripts/monitor-backfill.sh
   ```

2. Enable pruning:
   ```bash
   ./scripts/enable-bitcoin-pruning.sh
   ```

3. Monitor disk usage reduction:
   ```bash
   watch -n 300 'du -sh /var/lib/blockchain-data/bitcoin'
   ```

**Impact**: Reduces Bitcoin Core disk usage by ~70% over a few hours

---

### Phase 4: ClickHouse Upgrade to v26.1 (30-60 minutes)

Upgrade ClickHouse to v26.1 to enable tiered storage with S3.

**Prerequisites**:
- Historical backfill complete
- Announce maintenance window to students (48 hours advance notice)

**Steps:**

1. Schedule maintenance window (announce to students)

2. Run upgrade script:
   ```bash
   ./scripts/upgrade-clickhouse.sh
   ```

   The script will:
   - Stop data collection
   - Create pre-upgrade backup
   - Upgrade ClickHouse to v26.1
   - Verify data integrity
   - Provide rollback instructions if needed

3. Verify upgrade:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT version()"
   ```

4. Resume collection:
   ```bash
   curl -X POST http://localhost:8010/start
   ```

**Downtime**: 15-30 minutes

**Rollback** (if needed):
```bash
docker compose -f docker-compose.production.yml stop clickhouse
mv docker-compose.production.yml.bak docker-compose.production.yml
docker compose -f docker-compose.production.yml up -d clickhouse
curl -X POST http://localhost:8010/start
```

---

### Phase 5: Backblaze Integration (4-8 hours)

Set up automated daily backups to Backblaze B2.

**Steps:**

1. Install and configure rclone:
   ```bash
   ./scripts/setup-rclone.sh
   ```

2. Test backup manually:
   ```bash
   ./scripts/backup-to-backblaze.sh
   ```

3. Install automated daily backups:
   ```bash
   sudo ./scripts/install-backup-timer.sh
   ```

4. Verify timer is enabled:
   ```bash
   sudo systemctl status clickhouse-backup.timer
   sudo systemctl list-timers
   ```

**Backup Schedule**:
- Runs daily at 2:00 AM
- Full backup on Sundays
- Incremental backups on other days
- 30-day retention (automatically deletes old backups)

**Manual Backup**:
```bash
sudo systemctl start clickhouse-backup.service
```

**View Backup Logs**:
```bash
sudo journalctl -u clickhouse-backup.service
```

**Cost**: ~$1.50-2.00/month for Backblaze B2

---

### Phase 6: Data Tiering (2-4 hours)

Enable tiered storage to automatically move data older than 30 days to Backblaze.

**Prerequisites**: ClickHouse v26.1 running

**Steps:**

1. Apply tiered storage policy:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --queries-file=/docker-entrypoint-initdb.d/02-enable-tiering.sql
   ```

2. Monitor data movement:
   ```bash
   ./scripts/check-storage-distribution.sh
   ```

   Or watch continuously:
   ```bash
   watch -n 300 ./scripts/check-storage-distribution.sh  # Every 5 minutes
   ```

**How It Works**:
- Data newer than 30 days stays on local SSD (hot tier)
- Data older than 30 days moves to Backblaze (cold tier)
- ClickHouse runs TTL operations every 15 minutes
- Queries transparently access both hot and cold data

**Expected Result**:
- Hot local storage: ~200 GB (last 30 days)
- Cold Backblaze storage: Rest of historical data
- Queries work across both tiers seamlessly

---

## Configuration Files

### Bitcoin Core
- **Config**: `bitcoin-core/bitcoin.conf`
- **Data**: `/var/lib/blockchain-data/bitcoin`
- **RPC Port**: 8332
- **P2P Port**: 8333

### ClickHouse
- **Config**: `clickhouse-config/storage.xml`
- **Data**: `/var/lib/blockchain-data/clickhouse`
- **HTTP Port**: 8125
- **Native Port**: 9002

### Environment Variables
All configuration in `.env.production`:
- `BITCOIN_CORE_RPC_URL`: Bitcoin Core RPC endpoint
- `BITCOIN_CORE_RPC_USER`: RPC username
- `BITCOIN_CORE_RPC_PASSWORD`: RPC password
- `BITCOIN_USE_LOCAL_NODE`: Enable/disable local node usage
- `BACKBLAZE_KEY_ID`: Backblaze B2 key ID
- `BACKBLAZE_APPLICATION_KEY`: Backblaze B2 application key
- `BACKBLAZE_BUCKET`: Backblaze B2 bucket name

---

## Monitoring and Maintenance

### Daily Monitoring

Check Bitcoin Core sync:
```bash
./scripts/check-bitcoin-sync.sh
```

Check backfill progress:
```bash
./scripts/monitor-backfill.sh
```

Check storage distribution:
```bash
./scripts/check-storage-distribution.sh
```

### Weekly Monitoring

Verify backups:
```bash
rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1
```

Check disk usage:
```bash
df -h /var/lib/blockchain-data/
```

### Logs

View all service logs:
```bash
docker compose -f docker-compose.production.yml logs -f
```

View specific service logs:
```bash
docker compose -f docker-compose.production.yml logs -f bitcoin-core
docker compose -f docker-compose.production.yml logs -f clickhouse
docker compose -f docker-compose.production.yml logs -f collector
```

View backup logs:
```bash
sudo journalctl -u clickhouse-backup.service
```

---

## Verification

### Post-Migration Tests

1. All services running:
   ```bash
   docker compose -f docker-compose.production.yml ps
   ```

2. Bitcoin Core status:
   ```bash
   docker compose -f docker-compose.production.yml exec bitcoin-core \
       bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=SECURE_PASSWORD_HERE \
       getblockchaininfo
   ```

3. ClickHouse version:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT version()"
   ```

4. Data completeness:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="
       SELECT 'bitcoin_blocks' as table, count() FROM blockchain_data.bitcoin_blocks
       UNION ALL
       SELECT 'bitcoin_transactions', count() FROM blockchain_data.bitcoin_transactions
       "
   ```

5. Storage distribution:
   ```bash
   ./scripts/check-storage-distribution.sh
   ```

6. Backups:
   ```bash
   rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1
   ```

7. Backup timer:
   ```bash
   sudo systemctl status clickhouse-backup.timer
   ```

8. Dashboard:
   ```bash
   curl http://localhost:3001/api/data/overview
   ```

---

## Troubleshooting

### Bitcoin Core

**Issue**: Sync is slow
- Check network connectivity
- Verify sufficient disk space
- Increase `dbcache` in bitcoin.conf

**Issue**: RPC connection refused
- Verify Bitcoin Core is running
- Check RPC credentials in .env.production
- Verify docker network connectivity

### ClickHouse

**Issue**: Upgrade failed
- Check logs: `docker compose -f docker-compose.production.yml logs clickhouse`
- Rollback to previous version (see Phase 4)
- Restore from backup

**Issue**: Queries are slow
- Check storage distribution: `./scripts/check-storage-distribution.sh`
- Verify hot data is on local disk
- Check Backblaze connectivity

### Backfill

**Issue**: Backfill stopped
- Check collector logs: `docker compose -f docker-compose.production.yml logs collector`
- Verify Bitcoin Core is responsive
- Restart collector if needed

**Issue**: Rate limited
- Backfill will automatically slow down
- Check logs for rate limit messages
- Reduce `PARALLEL_BLOCK_FETCH_COUNT` if needed

### Backups

**Issue**: Backup failed
- Check rclone configuration: `rclone lsd backblaze:typeless-crypto-data`
- Verify Backblaze credentials in .env.production
- Check disk space for local backups
- View logs: `sudo journalctl -u clickhouse-backup.service`

---

## Cost Analysis

### Backblaze B2 (Monthly)
- Storage: 200 GB × $0.006/GB = $1.20
- Downloads: ~10 GB × $0.01/GB = $0.10
- **Total: ~$1.50-2.00/month**

### Hetzner Storage
- Included in existing server cost
- Using 850 GB of 1.8 TB available (47%)

---

## Benefits

1. **Complete Historical Data**: All Bitcoin blocks from genesis in ClickHouse
2. **Cost Effective**: ~$2/month for unlimited historical data
3. **No Rate Limits**: Local Bitcoin Core node
4. **High Availability**: Dual-source collector (local node + public API fallback)
5. **Disaster Recovery**: Daily backups with 30-day retention
6. **Scalable Storage**: Hot/cold tiering keeps local storage lean
7. **Zero Trust**: Self-hosted, no dependency on third-party APIs

---

## Files Created

### Scripts
- `scripts/install-bitcoin-core.sh` - Install Bitcoin Core
- `scripts/check-bitcoin-sync.sh` - Monitor Bitcoin Core sync
- `scripts/start-historical-backfill.sh` - Start historical backfill
- `scripts/monitor-backfill.sh` - Monitor backfill progress
- `scripts/enable-bitcoin-pruning.sh` - Enable Bitcoin Core pruning
- `scripts/upgrade-clickhouse.sh` - Upgrade ClickHouse to v26.1
- `scripts/setup-rclone.sh` - Setup rclone for Backblaze
- `scripts/backup-to-backblaze.sh` - Backup ClickHouse to Backblaze
- `scripts/install-backup-timer.sh` - Install systemd backup timer
- `scripts/check-storage-distribution.sh` - Monitor storage distribution

### Configuration
- `bitcoin-core/bitcoin.conf` - Bitcoin Core configuration
- `clickhouse-config/storage.xml` - ClickHouse S3 tiering configuration
- `clickhouse-init/02-enable-tiering.sql` - SQL to enable tiered storage
- `scripts/clickhouse-backup.service` - Systemd service for backups
- `scripts/clickhouse-backup.timer` - Systemd timer for daily backups

### Modified Files
- `docker-compose.production.yml` - Added Bitcoin Core service, updated ClickHouse
- `.env.production` - Added Bitcoin and Backblaze credentials
- `collector/collectors/bitcoin_collector.py` - Added RPC support with fallback

---

## Support

For issues or questions:
1. Check logs first (see Monitoring section)
2. Review troubleshooting guide
3. Check Bitcoin Core/ClickHouse documentation
4. Contact system administrator

## References

- [Bitcoin Core Documentation](https://bitcoin.org/en/bitcoin-core/)
- [ClickHouse S3 Storage](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-s3)
- [Backblaze B2 Documentation](https://www.backblaze.com/b2/docs/)
- [rclone Documentation](https://rclone.org/docs/)
