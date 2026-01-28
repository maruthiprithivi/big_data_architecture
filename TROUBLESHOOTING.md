# Troubleshooting Guide - Hybrid Architecture

Common issues and solutions for the hybrid Bitcoin Core + ClickHouse + Backblaze architecture.

## Quick Diagnostics

Run the system health check first:
```bash
./scripts/system-health-check.sh
```

This will identify most common issues automatically.

---

## Bitcoin Core Issues

### Issue: Bitcoin Core Won't Start

**Symptoms:**
- Container exits immediately
- `docker compose ps` shows bitcoin-core as "Exited"

**Solutions:**

1. Check logs:
   ```bash
   docker compose -f docker-compose.production.yml logs bitcoin-core
   ```

2. Verify configuration:
   ```bash
   cat bitcoin-core/bitcoin.conf
   ```
   - Ensure `rpcpassword` is set
   - Check for syntax errors

3. Check disk space:
   ```bash
   df -h /var/lib/blockchain-data/bitcoin
   ```
   - Need at least 650 GB for full sync
   - Or 200 GB if pruning enabled

4. Restart:
   ```bash
   docker compose -f docker-compose.production.yml restart bitcoin-core
   ```

---

### Issue: Bitcoin Core Sync is Slow

**Symptoms:**
- Sync progress < 1% per day
- Headers increasing but blocks not

**Solutions:**

1. Check network connectivity:
   ```bash
   docker compose -f docker-compose.production.yml exec bitcoin-core \
       bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
       getnetworkinfo
   ```
   - Look for `connections`: Should be > 0

2. Increase dbcache (requires restart):
   - Edit `bitcoin-core/bitcoin.conf`
   - Increase `dbcache=4096` to `dbcache=8192`
   - Restart Bitcoin Core

3. Check disk I/O:
   ```bash
   iostat -x 1 10
   ```
   - If %util consistently >90%, disk is bottleneck
   - Consider upgrading to faster storage

4. Wait - initial sync is slow:
   - First 50%: ~3-5 days
   - Next 40%: ~2-4 days
   - Final 10%: ~2-3 days
   - Total: 7-14 days typical

---

### Issue: Bitcoin Core RPC Not Responding

**Symptoms:**
- `bitcoin-cli` commands fail
- Collector can't connect
- "Connection refused" errors

**Solutions:**

1. Verify Bitcoin Core is running:
   ```bash
   docker compose -f docker-compose.production.yml ps bitcoin-core
   ```

2. Test RPC internally:
   ```bash
   docker compose -f docker-compose.production.yml exec bitcoin-core \
       bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
       getblockchaininfo
   ```

3. Check RPC credentials:
   - `.env.production`: `BITCOIN_CORE_RPC_PASSWORD`
   - `bitcoin-core/bitcoin.conf`: `rpcpassword`
   - Must match exactly

4. Check network configuration:
   - Ensure `rpcbind=0.0.0.0` in bitcoin.conf
   - Ensure `rpcallowip=172.16.0.0/12` in bitcoin.conf

5. Restart Bitcoin Core:
   ```bash
   docker compose -f docker-compose.production.yml restart bitcoin-core
   ```

---

## ClickHouse Issues

### Issue: ClickHouse Won't Start After Upgrade

**Symptoms:**
- ClickHouse container exits
- "Migration failed" in logs
- Cannot connect to database

**Solutions:**

1. Check logs:
   ```bash
   docker compose -f docker-compose.production.yml logs clickhouse
   ```

2. Rollback to previous version:
   ```bash
   docker compose -f docker-compose.production.yml stop clickhouse
   mv docker-compose.production.yml.bak docker-compose.production.yml
   docker compose -f docker-compose.production.yml up -d clickhouse
   ```

3. Restore from backup:
   ```bash
   # List backups
   ls -lh /var/backups/blockchain-ingestion/

   # Follow ClickHouse restore procedure
   # (see ClickHouse documentation)
   ```

4. Check disk space:
   ```bash
   df -h /var/lib/blockchain-data/clickhouse
   ```

---

### Issue: ClickHouse Queries Are Slow

**Symptoms:**
- Queries taking > 10 seconds
- Dashboard loading slow
- High CPU usage

**Solutions:**

1. Check storage distribution:
   ```bash
   ./scripts/check-storage-distribution.sh
   ```
   - Recent data should be on local disk (hot)
   - Old data can be on Backblaze (cold)

2. Verify tiered storage is working:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT disk_name, count() FROM system.parts WHERE database = 'blockchain_data' AND active = 1 GROUP BY disk_name"
   ```

3. Check for large queries:
   - Avoid SELECT * on large tables
   - Add LIMIT clauses
   - Use WHERE clauses to filter data

4. Restart ClickHouse:
   ```bash
   docker compose -f docker-compose.production.yml restart clickhouse
   ```

---

### Issue: S3/Backblaze Connection Fails

**Symptoms:**
- "Cannot connect to S3" errors
- TTL moves failing
- Data not archiving to cold storage

**Solutions:**

1. Test Backblaze connection:
   ```bash
   rclone lsd backblaze:typeless-crypto-data
   ```

2. Verify credentials:
   - Check `.env.production`:
     - `BACKBLAZE_KEY_ID`
     - `BACKBLAZE_APPLICATION_KEY`
     - `BACKBLAZE_BUCKET`

3. Test from ClickHouse:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT * FROM system.disks"
   ```
   - Should show `backblaze_s3` disk

4. Check network:
   - Ensure server can reach s3.us-west-004.backblazeb2.com
   - Check firewall rules

5. Restart ClickHouse to reload credentials:
   ```bash
   docker compose -f docker-compose.production.yml restart clickhouse
   ```

---

## Data Collection Issues

### Issue: Historical Backfill Stopped

**Symptoms:**
- Block count not increasing
- `monitor-backfill.sh` shows no progress
- Collector running but not collecting

**Solutions:**

1. Check collector logs:
   ```bash
   docker compose -f docker-compose.production.yml logs -f collector
   ```
   - Look for errors or rate limiting

2. Verify Bitcoin Core is responding:
   ```bash
   docker compose -f docker-compose.production.yml exec bitcoin-core \
       bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=PASSWORD \
       getblockchaininfo
   ```

3. Check collection status:
   ```bash
   curl http://localhost:8010/status
   ```

4. Restart collector:
   ```bash
   docker compose -f docker-compose.production.yml restart collector
   curl -X POST http://localhost:8010/start
   ```

5. Check configuration:
   - `.env.production`: `BITCOIN_USE_LOCAL_NODE=true`
   - `.env.production`: `ENABLE_HISTORICAL_BACKFILL=true`

---

### Issue: Rate Limited by Public API

**Symptoms:**
- "Rate limited" messages in logs
- Collection pausing frequently
- "HTTP 429" errors

**Solutions:**

1. This is normal during fallback to public API
   - Collector will automatically slow down
   - Wait for rate limit to expire (usually 1-5 minutes)

2. Ensure local node is being used:
   - Check `.env.production`: `BITCOIN_USE_LOCAL_NODE=true`
   - Verify Bitcoin Core is synced and responsive

3. Reduce parallel fetching:
   - Edit `.env.production`:
   - Change `PARALLEL_BLOCK_FETCH_COUNT=50` to `=10`
   - Restart collector

---

### Issue: Collector Out of Memory

**Symptoms:**
- Collector container restarting
- "OOM killed" in logs
- Parallel fetching failing

**Solutions:**

1. Reduce parallel fetching:
   - Edit `.env.production`:
   - Change `PARALLEL_BLOCK_FETCH_COUNT=50` to `=10`
   - Restart collector

2. Increase Docker memory:
   - Docker Desktop → Settings → Resources
   - Increase memory to 8 GB or more

3. Restart collector:
   ```bash
   docker compose -f docker-compose.production.yml restart collector
   ```

---

## Backup Issues

### Issue: Backup to Backblaze Fails

**Symptoms:**
- Backup script errors
- No backups in Backblaze
- systemd timer failing

**Solutions:**

1. Check logs:
   ```bash
   sudo journalctl -u clickhouse-backup.service -n 100
   ```

2. Test rclone connection:
   ```bash
   rclone lsd backblaze:typeless-crypto-data
   ```

3. Test manual backup:
   ```bash
   ./scripts/backup-to-backblaze.sh
   ```

4. Check disk space:
   ```bash
   df -h /var/lib
   ```
   - Need space for local backup before upload

5. Verify credentials:
   - Check `.env.production` for Backblaze credentials
   - Verify rclone configuration: `cat ~/.config/rclone/rclone.conf`

6. Check network:
   - Test connection to Backblaze:
     ```bash
     curl -I https://s3.us-west-004.backblazeb2.com
     ```

---

### Issue: Backup Timer Not Running

**Symptoms:**
- No backups being created
- `systemctl status clickhouse-backup.timer` shows inactive

**Solutions:**

1. Check timer status:
   ```bash
   sudo systemctl status clickhouse-backup.timer
   ```

2. Enable and start timer:
   ```bash
   sudo systemctl enable clickhouse-backup.timer
   sudo systemctl start clickhouse-backup.timer
   ```

3. Verify timer is scheduled:
   ```bash
   sudo systemctl list-timers | grep clickhouse
   ```

4. Run manual backup to test:
   ```bash
   sudo systemctl start clickhouse-backup.service
   sudo journalctl -u clickhouse-backup.service -f
   ```

---

## Storage Issues

### Issue: Disk Full

**Symptoms:**
- Services failing
- "No space left on device" errors
- Collection stopping

**Solutions:**

1. Check disk usage:
   ```bash
   df -h /var/lib
   ./scripts/check-storage-distribution.sh
   ```

2. Clean up old backups:
   ```bash
   # Local backups
   ls -lt /var/backups/blockchain-ingestion/
   sudo rm -rf /var/backups/blockchain-ingestion/OLDEST_BACKUP
   ```

3. Enable Bitcoin Core pruning:
   ```bash
   ./scripts/enable-bitcoin-pruning.sh
   ```
   - Reduces Bitcoin Core from 650 GB to 200 GB

4. Force TTL to move data to cold storage:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="OPTIMIZE TABLE blockchain_data.bitcoin_blocks FINAL"
   ```

5. Clean up Docker:
   ```bash
   docker system prune -a
   ```

---

### Issue: Data Not Moving to Cold Storage

**Symptoms:**
- All data still on local disk
- `check-storage-distribution.sh` shows 100% on default disk
- Hot storage growing beyond 200 GB

**Solutions:**

1. Verify tiered storage is applied:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT table, storage_policy FROM system.tables WHERE database = 'blockchain_data'"
   ```
   - Should show `tiered_storage`

2. Check TTL rules:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SHOW CREATE TABLE blockchain_data.bitcoin_blocks"
   ```
   - Should include `TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold'`

3. Wait - TTL runs every 15 minutes:
   - Monitor with: `watch -n 300 ./scripts/check-storage-distribution.sh`

4. Force TTL execution:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="OPTIMIZE TABLE blockchain_data.bitcoin_blocks FINAL"
   ```

5. Verify Backblaze connectivity:
   ```bash
   docker compose -f docker-compose.production.yml exec clickhouse \
       clickhouse-client --password=BlockchainData2026!Secure \
       --query="SELECT * FROM system.disks WHERE name = 'backblaze_s3'"
   ```

---

## Dashboard Issues

### Issue: Dashboard Not Loading

**Symptoms:**
- Blank page
- "Connection refused" errors
- 502/503 errors

**Solutions:**

1. Check if dashboard is running:
   ```bash
   docker compose -f docker-compose.production.yml ps dashboard
   ```

2. Check logs:
   ```bash
   docker compose -f docker-compose.production.yml logs dashboard
   ```

3. Test API endpoint:
   ```bash
   curl http://localhost:3001/api/data/overview
   ```

4. Restart dashboard:
   ```bash
   docker compose -f docker-compose.production.yml restart dashboard
   ```

5. Check ClickHouse connectivity:
   - Dashboard needs to connect to ClickHouse
   - Verify CLICKHOUSE_HOST in docker-compose.yml

---

## Performance Issues

### Issue: High CPU Usage

**Symptoms:**
- Server slow
- `docker stats` shows >80% CPU
- Queries timing out

**Solutions:**

1. Identify culprit:
   ```bash
   docker stats --no-stream
   ```

2. If Bitcoin Core:
   - Normal during sync (verify with `./scripts/check-bitcoin-sync.sh`)
   - Reduce `dbcache` if needed

3. If ClickHouse:
   - Check for long-running queries:
     ```bash
     docker compose -f docker-compose.production.yml exec clickhouse \
         clickhouse-client --password=BlockchainData2026!Secure \
         --query="SELECT query_id, query, elapsed FROM system.processes"
     ```
   - Kill if needed:
     ```bash
     docker compose -f docker-compose.production.yml exec clickhouse \
         clickhouse-client --password=BlockchainData2026!Secure \
         --query="KILL QUERY WHERE query_id = 'QUERY_ID'"
     ```

4. If Collector:
   - Reduce parallel fetching (see "Collector Out of Memory")

---

## Getting Help

If issues persist:

1. Gather diagnostic information:
   ```bash
   ./scripts/system-health-check.sh > health-report.txt
   docker compose -f docker-compose.production.yml logs > docker-logs.txt
   ```

2. Check documentation:
   - HYBRID_ARCHITECTURE.md - Complete architecture guide
   - QUICK_REFERENCE.md - Common commands
   - IMPLEMENTATION_COMPLETE.md - Implementation details

3. Review phase-specific guides in HYBRID_ARCHITECTURE.md

4. Check Docker logs for specific error messages

---

## Emergency Procedures

### Complete System Restart

```bash
# Stop everything
docker compose -f docker-compose.production.yml down

# Wait 30 seconds
sleep 30

# Start everything
docker compose -f docker-compose.production.yml up -d

# Verify
./scripts/system-health-check.sh
```

### Restore from Backup

```bash
# Stop ClickHouse
docker compose -f docker-compose.production.yml stop clickhouse

# List available backups
ls -lh /var/backups/blockchain-ingestion/
rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1

# Restore (follow ClickHouse documentation for your backup format)
# ...

# Start ClickHouse
docker compose -f docker-compose.production.yml up -d clickhouse
```

### Reset Everything (Last Resort)

⚠️ **WARNING**: This deletes all data!

```bash
# Stop services
docker compose -f docker-compose.production.yml down -v

# Remove data
sudo rm -rf /var/lib/blockchain-data/*

# Start fresh
docker compose -f docker-compose.production.yml up -d
```

---

## Prevention

### Regular Maintenance

Weekly:
- Run health check: `./scripts/system-health-check.sh`
- Check disk usage: `df -h /var/lib`
- Review logs for errors
- Verify backups exist

Monthly:
- Review Backblaze costs
- Update system packages
- Review and optimize queries
- Clean up old Docker images: `docker system prune -a`
