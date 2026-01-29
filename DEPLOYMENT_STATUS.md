# Hybrid Architecture Deployment Status

**Last Updated:** 2026-01-29 01:44 CET

## Current Phase: 1 - Bitcoin Core Sync

### Phase 1 Status: IN PROGRESS

**Bitcoin Core Sync Progress:**
- Current Block: 441,537
- Total Headers: 934,147
- Progress: 12.75%
- Disk Usage: 98.85 GB
- Status: Actively syncing
- Container: Running (marked unhealthy due to healthcheck issue, but RPC works fine)

**Estimated Timeline:**
- Started: ~1 hour ago
- Current Rate: ~7,300 blocks/hour (based on first hour)
- Remaining: 492,610 blocks
- Estimated Completion: 3-7 days (accounting for increasing block sizes)

## Phase Completion Checklist

### Phase 1: Bitcoin Core Installation and Sync
- [x] Bitcoin Core configuration created
- [x] docker-compose.production.yml updated
- [x] .env.production updated with credentials
- [x] Bitcoin Core container deployed
- [x] Sync started
- [x] Monitoring scripts created
- [ ] **Sync completion (blocks == headers)** - IN PROGRESS (12.75%)
- [ ] Container health check passing (non-critical)

### Phase 2: Historical Backfill
- [x] Collector modified for RPC support
- [x] Backfill scripts created
- [ ] Bitcoin Core sync complete (prerequisite)
- [ ] Backfill started
- [ ] 800,000+ blocks collected in ClickHouse
- [ ] Estimated: 2-4 weeks after Phase 1 completes

### Phase 3: Bitcoin Core Pruning
- [x] Pruning script created
- [ ] Backfill complete (prerequisite)
- [ ] Pruning enabled
- [ ] Storage reduced to ~200 GB

### Phase 4: ClickHouse Upgrade to v26.1
- [x] Upgrade script created
- [x] Storage configuration created
- [ ] Backup created
- [ ] ClickHouse upgraded to v26.1
- [ ] Tables verified
- [ ] Estimated: 30-60 min maintenance window

### Phase 5: Backblaze Integration
- [x] rclone setup script created
- [x] Backup script created
- [x] systemd timer configuration created
- [ ] rclone installed and configured
- [ ] Initial backup to Backblaze
- [ ] Daily backup timer enabled

### Phase 6: Data Tiering
- [x] Tiering SQL script created
- [x] Storage policy configuration created
- [ ] ClickHouse v26.1 running (prerequisite)
- [ ] Tiered storage applied
- [ ] Data >30 days moved to Backblaze
- [ ] Hot storage < 200 GB

## Deployment Details

### Server Information
- **Server:** Hetzner typeless_sandbox
- **Available Space:** 1.7 TB
- **Current Usage:** 8%
- **Bitcoin Core Data:** /var/lib/blockchain-data/bitcoin
- **ClickHouse Data:** /var/lib/blockchain-data/clickhouse

### Credentials (Deployed on Server)
- **Bitcoin RPC User:** blockchain_collector
- **Bitcoin RPC Password:** jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd
- **ClickHouse Password:** BlockchainData2026!Secure
- **Backblaze Key ID:** 003c32860e160be0000000003
- **Backblaze Bucket:** typeless-crypto-data

### Git Branch
- **Branch:** hybrid-architecture (local only, NOT pushed to GitHub)
- **Strategy:** Keep separate from main branch permanently
- **Reason:** Contains sensitive credentials and configuration

## Daily Monitoring

### Quick Sync Check
```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"
```

### Full System Status
```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/system-health-check.sh"
```

### Manual RPC Query
```bash
ssh typeless_sandbox
cd /opt/blockchain-ingestion
docker compose -f docker-compose.production.yml exec -T bitcoin-core \
  bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd \
  getblockchaininfo
```

## Known Issues

### 1. Container Health Check Failing
**Status:** Non-critical
**Cause:** Healthcheck in docker-compose uses ${BITCOIN_CORE_RPC_PASSWORD} variable which doesn't interpolate in command array
**Impact:** Container shows as "unhealthy" but RPC works perfectly
**Fix:** Update docker-compose.production.yml healthcheck to use hardcoded password or alternative method
**Priority:** Low (cosmetic only)

### 2. Environment Variable Warnings
**Status:** Cosmetic
**Warnings:** BACKBLAZE_KEY_ID, BACKBLAZE_APPLICATION_KEY, BITCOIN_CORE_RPC_PASSWORD not set
**Cause:** Docker Compose checks variables before loading .env.production
**Impact:** None - variables load correctly when containers run
**Fix:** None needed (warning only)

## Documentation

### Available Guides
- [Bitcoin Core Interaction Guide](docs/bitcoin-core-guide.md) - Complete RPC command reference
- [Bitcoin Sync Status](BITCOIN_SYNC_STATUS.md) - Detailed sync monitoring info
- [Hybrid Architecture](HYBRID_ARCHITECTURE.md) - Complete 6-phase implementation guide
- [Quick Reference](QUICK_REFERENCE.md) - Daily operations commands
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions

### Scripts Deployed
- `/opt/blockchain-ingestion/scripts/check-sync.sh` - Quick sync status
- `/opt/blockchain-ingestion/scripts/system-health-check.sh` - Full system check
- `/opt/blockchain-ingestion/scripts/start-historical-backfill.sh` - Start Phase 2
- `/opt/blockchain-ingestion/scripts/enable-bitcoin-pruning.sh` - Enable pruning (Phase 3)
- `/opt/blockchain-ingestion/scripts/upgrade-clickhouse.sh` - Upgrade to v26.1 (Phase 4)

## Next Actions

### Immediate (Now)
- Monitor Bitcoin Core sync daily with: `ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"`
- Watch for sync completion (blocks == headers)

### When Phase 1 Completes (3-7 days)
1. Verify sync: `./scripts/check-bitcoin-sync.sh`
2. Start Phase 2: `./scripts/start-historical-backfill.sh`
3. Monitor backfill: `./scripts/monitor-backfill.sh`

### When Phase 2 Completes (2-4 weeks later)
1. Enable pruning: `./scripts/enable-bitcoin-pruning.sh`
2. Monitor disk space reduction

### Schedule Phase 4 Maintenance
1. Announce maintenance window to students (48 hours notice)
2. Schedule 30-60 minute downtime
3. Run: `./scripts/upgrade-clickhouse.sh`

## Timeline Summary

| Phase | Status | Start | Duration | Complete |
|-------|--------|-------|----------|----------|
| 1: Bitcoin Sync | IN PROGRESS | 2026-01-29 00:40 | 3-7 days | ~2026-02-05 |
| 2: Backfill | Not Started | TBD | 2-4 weeks | ~2026-03-05 |
| 3: Pruning | Not Started | TBD | 1-2 hours | ~2026-03-05 |
| 4: CH Upgrade | Not Started | TBD | 30-60 min | TBD |
| 5: Backblaze | Not Started | TBD | 4-8 hours | TBD |
| 6: Tiering | Not Started | TBD | 2-4 hours | ~2026-03-10 |

**Projected Completion:** Early-Mid March 2026
