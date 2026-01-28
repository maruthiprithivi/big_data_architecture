# Hybrid Architecture Deployment Checklist

Use this checklist to track deployment progress of the hybrid Bitcoin Core + ClickHouse + Backblaze architecture. Check off items as you complete them.

## Pre-Deployment Preparation

### Security Configuration
- [ ] Set secure Bitcoin RPC password in `bitcoin-core/bitcoin.conf`
- [ ] Update Bitcoin RPC password in `.env.production` (match bitcoin.conf)
- [ ] Verify Backblaze credentials in `.env.production`
- [ ] Review all environment variables for sensitive data
- [ ] Ensure `.gitignore` excludes all credential files

### System Requirements
- [ ] Verify Hetzner server has 850+ GB free disk space: `df -h /var/lib`
- [ ] Verify current ClickHouse backup exists: `ls -lh /var/backups/blockchain-ingestion/`
- [ ] Verify Docker is running: `docker ps`
- [ ] Verify current services are healthy: `docker compose -f docker-compose.production.yml ps`

### Student Communication
- [ ] Announce Phase 1 deployment (no downtime expected)
- [ ] Schedule Phase 4 maintenance window (48 hours advance notice)
- [ ] Prepare status update template for progress reports

---

## Phase 1: Bitcoin Core Installation

**Target Date**: _______________
**Expected Duration**: 30 minutes setup + 7-14 days sync

### Installation (Day 1)
- [ ] Pull latest code: `git pull`
- [ ] Review configuration: `cat bitcoin-core/bitcoin.conf`
- [ ] Run installation: `./scripts/install-bitcoin-core.sh`
- [ ] Verify running: `docker compose -f docker-compose.production.yml ps bitcoin-core`
- [ ] Check initial sync: `./scripts/check-bitcoin-sync.sh`

### Daily Monitoring
- [ ] Day 2-14: Run `./scripts/check-bitcoin-sync.sh` daily
- [ ] Day 7: Check disk usage (should be growing to ~650 GB)
- [ ] Day 14: Verify if sync complete

### Phase 1 Completion
- [ ] Bitcoin Core fully synced (blocks == headers)
- [ ] Disk usage ~650 GB
- [ ] RPC connectivity confirmed
- [ ] Existing collection working normally

**Completed**: _______________

---

## Phase 2: Historical Backfill

**Target Date**: _______________
**Expected Duration**: 2-4 weeks

### Preparation
- [ ] Verify Bitcoin Core 100% synced
- [ ] Check ClickHouse space: `df -h /var/lib/blockchain-data/clickhouse`
- [ ] Review current blocks: `./scripts/monitor-backfill.sh`

### Start Backfill
- [ ] Run: `./scripts/start-historical-backfill.sh`
- [ ] Verify started: `docker compose -f docker-compose.production.yml logs -f collector`
- [ ] Check progress after 1 hour
- [ ] Verify parallel fetching in logs

### Weekly Monitoring
- [ ] Week 1: Progress check, no errors
- [ ] Week 2: Progress + disk usage
- [ ] Week 3: Progress + completion estimate
- [ ] Week 4: Final progress check

### Phase 2 Completion
- [ ] Bitcoin blocks >= 800,000
- [ ] No errors in last 24h
- [ ] Collection rate stable
- [ ] ClickHouse ~200 GB

**Completed**: _______________

---

## Phase 3: Bitcoin Core Pruning

**Target Date**: _______________
**Expected Duration**: 1-2 hours

### Execution
- [ ] Verify backfill 100% complete
- [ ] Backup: `./scripts/backup-clickhouse.sh`
- [ ] Run: `./scripts/enable-bitcoin-pruning.sh`
- [ ] Monitor: `watch -n 300 'du -sh /var/lib/blockchain-data/bitcoin'`

### Phase 3 Completion
- [ ] Disk usage ~200 GB (down from 650 GB)
- [ ] Bitcoin Core responsive
- [ ] Collection continues normally

**Completed**: _______________

---

## Phase 4: ClickHouse Upgrade

**Scheduled**: _______________
**Expected Duration**: 30-60 minutes (15-30 min downtime)

### Pre-Maintenance
- [ ] Announce 48 hours prior
- [ ] Backup: `./scripts/backup-clickhouse.sh`
- [ ] Record table counts

### Upgrade
- [ ] Run: `./scripts/upgrade-clickhouse.sh`
- [ ] Monitor progress
- [ ] Verify version: `docker compose -f docker-compose.production.yml exec clickhouse clickhouse-client --password=PASSWORD --query="SELECT version()"`
- [ ] Resume: `curl -X POST http://localhost:8010/start`

### Post-Maintenance
- [ ] Announce complete
- [ ] Monitor 1 hour
- [ ] Verify queries work

### Phase 4 Completion
- [ ] ClickHouse version 26.1.x
- [ ] All tables accessible
- [ ] Table counts match
- [ ] Collection resumed

**Completed**: _______________

---

## Phase 5: Backblaze Integration

**Target Date**: _______________
**Expected Duration**: 4-8 hours

### Setup
- [ ] Install rclone: `./scripts/setup-rclone.sh`
- [ ] Verify: `rclone lsd backblaze:typeless-crypto-data`

### First Backup
- [ ] Test: `./scripts/backup-to-backblaze.sh`
- [ ] Monitor upload
- [ ] Verify in Backblaze: `rclone lsf backblaze:typeless-crypto-data/clickhouse-backups --max-depth 1`

### Automation
- [ ] Install timer: `sudo ./scripts/install-backup-timer.sh`
- [ ] Verify: `sudo systemctl status clickhouse-backup.timer`
- [ ] Check schedule: `sudo systemctl list-timers`

### Phase 5 Completion
- [ ] Backup uploaded successfully
- [ ] systemd timer enabled
- [ ] Logs clean

**Completed**: _______________

---

## Phase 6: Data Tiering

**Target Date**: _______________
**Expected Duration**: 2-4 hours setup

### Enable Tiering
- [ ] Review: `cat clickhouse-config/storage.xml`
- [ ] Apply: `docker compose -f docker-compose.production.yml exec clickhouse clickhouse-client --password=PASSWORD --queries-file=/docker-entrypoint-initdb.d/02-enable-tiering.sql`
- [ ] Verify: `./scripts/check-storage-distribution.sh`

### Monitor Movement
- [ ] Check after 30 minutes
- [ ] Check after 2 hours
- [ ] Check after 24 hours

### Phase 6 Completion
- [ ] Policy applied to all tables
- [ ] TTL rules active
- [ ] Queries work correctly
- [ ] Hot storage <200 GB

**Completed**: _______________

---

## Final Verification

- [ ] Health check: `./scripts/system-health-check.sh`
- [ ] All services healthy
- [ ] Bitcoin Core synced and pruned
- [ ] ClickHouse 26.1.x
- [ ] Historical data complete (880k+ blocks)
- [ ] Tiered storage active
- [ ] Daily backups scheduled
- [ ] Dashboard functional

---

## Deployment Summary

| Phase | Target Date | Actual Date | Status | Notes |
|-------|-------------|-------------|--------|-------|
| Phase 1: Bitcoin Core | | | [ ] | |
| Phase 2: Backfill | | | [ ] | |
| Phase 3: Pruning | | | [ ] | |
| Phase 4: ClickHouse | | | [ ] | |
| Phase 5: Backblaze | | | [ ] | |
| Phase 6: Tiering | | | [ ] | |

**Deployment Started**: _______________
**Deployment Completed**: _______________
**Deployed By**: _______________
**Verified By**: _______________
