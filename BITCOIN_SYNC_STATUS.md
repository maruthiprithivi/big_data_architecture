# Bitcoin Core Sync Status

## Current Status (Last Updated: 2026-01-29)

### Sync Progress
- **Current Block:** 438,573
- **Total Headers:** 934,147
- **Progress:** 12.36%
- **Remaining:** 495,574 blocks
- **Sync Status:** Active, in initial block download

### Disk Usage
- **Current Size:** 96 GB (103,153,347,259 bytes)
- **Expected Final:** ~650 GB (before pruning)
- **Available Space:** 1.7 TB

### Timeline Estimate
Based on current progress (438,573 blocks in ~1 hour):
- **Sync Rate:** ~7,300 blocks/hour
- **Estimated Completion:** 68 hours (~3 days) at current rate
- **Actual Timeline:** 7-14 days (accounting for network variability and increasing block sizes)

## Monitoring

### Check Sync Status
```bash
ssh typeless_sandbox
cd /opt/blockchain-ingestion
./scripts/daily-status-check.sh
```

Or directly query Bitcoin Core:
```bash
docker compose -f docker-compose.production.yml exec -T bitcoin-core \
  bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd \
  getblockchaininfo
```

### What to Monitor
1. **Sync Progress:** `blocks` vs `headers` - when equal, sync is complete
2. **Disk Usage:** Should grow to ~650 GB
3. **Verification Progress:** Should approach 1.0 (currently 0.123)
4. **Container Health:** Should be "healthy" once healthcheck is fixed

## Next Steps

### Phase 1 Completion Criteria
- [ ] Bitcoin Core fully synced (blocks == headers)
- [ ] Verification progress = 1.0
- [ ] No warnings in logs
- [ ] Healthcheck passing (currently failing due to password mismatch in healthcheck command)

### After Sync Completes
1. Verify sync completion:
   ```bash
   ./scripts/check-bitcoin-sync.sh
   ```

2. Start Phase 2 (Historical Backfill):
   ```bash
   ./scripts/start-historical-backfill.sh
   ```

## Known Issues

### Container Marked as Unhealthy
**Status:** Non-critical - Bitcoin Core is syncing normally

**Cause:** Healthcheck command in docker-compose.production.yml uses `${BITCOIN_CORE_RPC_PASSWORD}` variable which doesn't get interpolated correctly in the healthcheck command array.

**Impact:** Docker shows container as "unhealthy" but RPC works fine when accessed with correct password.

**Fix Required:** Update healthcheck in docker-compose.production.yml to use hardcoded password or use a different healthcheck method.

### Environment Variable Warnings
**Status:** Cosmetic only

**Warnings:**
```
The "BACKBLAZE_KEY_ID" variable is not set
The "BACKBLAZE_APPLICATION_KEY" variable is not set
The "BITCOIN_CORE_RPC_PASSWORD" variable is not set
```

**Cause:** Docker Compose checks for variables before loading .env.production

**Impact:** None - variables are loaded correctly from .env.production when containers run

**Fix Required:** None (cosmetic warning only)

## Daily Routine

Run this command once per day to check progress:
```bash
ssh typeless_sandbox "cd /opt/blockchain-ingestion && ./scripts/daily-status-check.sh"
```

Expected timeline:
- **Days 1-3:** Rapid progress (older, smaller blocks)
- **Days 4-7:** Slower progress (larger blocks, more transactions)
- **Days 8-14:** Final stretch to current blockchain height

## Reference

See [Bitcoin Core Interaction Guide](docs/bitcoin-core-guide.md) for detailed RPC command reference.
