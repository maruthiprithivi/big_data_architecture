# Bitcoin Core Healthcheck Fix

## Issue
Bitcoin Core container was showing as "unhealthy" even though it was functioning correctly. The healthcheck was failing because:

1. The docker-compose healthcheck used `${BITCOIN_CORE_RPC_PASSWORD}` which wasn't being substituted correctly in the command array
2. The bitcoin-core service didn't have `env_file` specified to load environment variables

## Solution Applied

### Changes to docker-compose.production.yml

1. **Added env_file to bitcoin-core service:**
   ```yaml
   env_file:
     - .env.production
   ```

2. **Fixed healthcheck command:**
   ```yaml
   healthcheck:
     test: ["CMD-SHELL", "bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=$${BITCOIN_CORE_RPC_PASSWORD} getblockchaininfo > /dev/null 2>&1"]
   ```

   Changed from `CMD` to `CMD-SHELL` and used `$${BITCOIN_CORE_RPC_PASSWORD}` (double dollar signs) so Docker Compose doesn't try to substitute it, allowing the shell to substitute it from the environment.

3. **Removed read-only mount for bitcoin.conf:**
   Removed `:ro` flag from bitcoin.conf mount (was causing issues earlier)

## Deployment

Fixed on 2026-01-29 at 02:17 CET:

```bash
cd /opt/blockchain-ingestion
./scripts/fix-healthcheck.sh
```

## Expected Behavior

After applying the fix:

1. Container restarts (brief interruption to sync)
2. Bitcoin Core goes through "rolling forward" validation (2-5 minutes)
3. RPC becomes responsive
4. Healthcheck passes
5. Container shows as "healthy"
6. Sync resumes from where it left off

## Verification

Check container health status:
```bash
docker compose -f docker-compose.production.yml ps bitcoin-core
```

Should show: `Up X minutes (healthy)` after 2-5 minutes

## Notes

- **Rolling Forward:** After restart, Bitcoin Core validates recent blocks. During this time:
  - Logs show "Rolling forward" messages
  - RPC may not respond immediately
  - This is normal and expected
  - Takes 2-5 minutes for ~10,000 blocks of validation

- **Sync Progress:** Bitcoin Core will resume syncing from the last validated block, not from zero. No data is lost.

- **Healthcheck Timing:**
  - `start_period: 120s` - No failures counted for first 2 minutes
  - `interval: 30s` - Check every 30 seconds
  - `retries: 3` - Mark unhealthy after 3 consecutive failures
  - `timeout: 10s` - Each check times out after 10 seconds

## Status

**Applied:** 2026-01-29 02:17 CET
**Container Restarted:** Yes
**Rolling Forward:** In progress (blocks ~450,000)
**Previous Sync:** ~458,000 blocks (15.03%)
**Expected Resume:** Within 5 minutes of restart

The container will become healthy automatically once the rolling forward process completes.
