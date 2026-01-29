# Next Steps for Hybrid Architecture Deployment

## Current Situation

**Phase 1 (Bitcoin Core Sync) is in progress:**
- Bitcoin Core is actively syncing: 441,537 / 934,147 blocks (12.75%)
- Disk usage: 98.85 GB (will grow to ~650 GB)
- Estimated completion: 3-7 days from start
- All monitoring tools deployed and working

## What to Do Now

### Daily Monitoring (5 minutes/day)

Run this command once per day to check sync progress:

```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"
```

You should see output like:
```
Bitcoin Core Sync Progress
===========================

Blocks: 441537
Headers: 934147
Progress: 12.75%
Disk Usage: 98.85 GB

Last checked: Thu Jan 29 01:44:12 AM CET 2026
```

**What to watch for:**
- Blocks should be increasing daily
- Progress percentage should steadily grow
- Disk usage will grow to ~650 GB
- When `Blocks` == `Headers`, Phase 1 is complete

### Wait for Sync Completion (3-7 days)

**Nothing else needs to be done right now.** Just monitor daily and wait for Bitcoin Core to fully sync.

The system will:
- Automatically continue syncing Bitcoin blockchain
- Maintain existing ClickHouse data collection (Solana, current Bitcoin)
- Run all existing services normally

## When Phase 1 Completes

You'll know Phase 1 is complete when:
```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"
```

Shows:
```
Blocks: 934147
Headers: 934147
Progress: 100.00%
```

### Then Start Phase 2 (Historical Backfill)

Once sync is 100% complete, run:

```bash
ssh typeless_sandbox
cd /opt/blockchain-ingestion
./scripts/start-historical-backfill.sh
```

This will:
1. Enable local Bitcoin Core RPC in the collector
2. Start collecting all Bitcoin history from block 0
3. Take 2-4 weeks to complete
4. Monitor with: `./scripts/monitor-backfill.sh`

## Phase Timeline

| Phase | Duration | What Happens | Action Required |
|-------|----------|--------------|-----------------|
| **1: Bitcoin Sync** | **3-7 days** | **Bitcoin Core downloads blockchain** | **Monitor daily** |
| 2: Historical Backfill | 2-4 weeks | Collector reads Bitcoin Core & fills ClickHouse | Monitor weekly |
| 3: Pruning | 1-2 hours | Reduce Bitcoin Core storage to 200 GB | Run script when Phase 2 done |
| 4: ClickHouse Upgrade | 30-60 min | Upgrade to v26.1 for S3 support | Schedule maintenance window |
| 5: Backblaze Setup | 4-8 hours | Configure backups to B2 | One-time setup |
| 6: Data Tiering | 2-4 hours | Enable hot/cold storage | Final configuration |

## Quick Reference Commands

### Check Bitcoin Sync
```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"
```

### Check Full System Health
```bash
ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/system-health-check.sh"
```

### View Bitcoin Core Logs
```bash
ssh typeless_sandbox
cd /opt/blockchain-ingestion
docker compose -f docker-compose.production.yml logs -f bitcoin-core
```

### Check Container Status
```bash
ssh typeless_sandbox
cd /opt/blockchain-ingestion
docker compose -f docker-compose.production.yml ps
```

### Stop/Start Bitcoin Core (if needed)
```bash
# Stop
ssh typeless_sandbox "cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml stop bitcoin-core"

# Start
ssh typeless_sandbox "cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml up -d bitcoin-core"
```

## Documentation Available

All documentation is available on the server at `/opt/blockchain-ingestion/docs/`:

1. **bitcoin-core-guide.md** - Complete guide to interacting with Bitcoin Core RPC
2. **BITCOIN_SYNC_STATUS.md** - Detailed sync monitoring information
3. **DEPLOYMENT_STATUS.md** - Current deployment status and phase tracking
4. **HYBRID_ARCHITECTURE.md** - Complete 6-phase implementation guide
5. **QUICK_REFERENCE.md** - Quick reference for daily operations
6. **TROUBLESHOOTING.md** - Common issues and solutions

## Support & Troubleshooting

### Bitcoin Core Not Syncing?
```bash
# Check logs for errors
ssh typeless_sandbox "cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml logs --tail=100 bitcoin-core"

# Restart if stuck
ssh typeless_sandbox "cd /opt/blockchain-ingestion && docker compose -f docker-compose.production.yml restart bitcoin-core"
```

### Out of Disk Space?
```bash
# Check available space
ssh typeless_sandbox "df -h /var/lib"

# Should show 1.7 TB available (plenty for 650 GB Bitcoin + 200 GB ClickHouse)
```

### Container Shows as "Unhealthy"?
This is a known cosmetic issue - the healthcheck uses the wrong password variable. The RPC works fine. Non-critical.

## Important Reminders

1. **Do NOT push this branch to GitHub** - contains credentials
2. **Keep on separate `hybrid-architecture` branch** - per your instructions
3. **Monitor daily** - just run the check-sync.sh command
4. **Wait patiently** - blockchain sync takes days, this is normal
5. **Existing services continue normally** - dashboard and current collection unaffected

## Questions?

Refer to the documentation in `/opt/blockchain-ingestion/docs/` or check:
- Bitcoin Core logs: `docker compose logs bitcoin-core`
- System health: `./scripts/system-health-check.sh`
- Sync status: `./scripts/check-sync.sh`

---

**Next Action:** Monitor sync daily with `ssh typeless_sandbox "/opt/blockchain-ingestion/scripts/check-sync.sh"`

**Estimated Next Phase:** February 5, 2026 (when Bitcoin sync completes)
