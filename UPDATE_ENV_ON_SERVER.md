# Environment Variable Update on Server

## Issue Found

The .env.production file on the server was missing the Bitcoin Core RPC credentials. While these were added to the local version, they weren't deployed to the server initially.

## Variables Added

Added to `/opt/blockchain-ingestion/.env.production`:

```bash
# Bitcoin Core RPC Configuration
BITCOIN_CORE_RPC_URL=http://bitcoin-core:8332
BITCOIN_CORE_RPC_USER=blockchain_collector
BITCOIN_CORE_RPC_PASSWORD=jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd
BITCOIN_USE_LOCAL_NODE=false
```

## Applied On

2026-01-29 02:24 CET

## Next Steps

After Bitcoin Core completes its current rolling forward process and becomes healthy:

1. The healthcheck should pass
2. RPC commands will work properly
3. Sync will resume from where it left off

## Note on Rolling Forward

After each restart, Bitcoin Core validates recent blocks (rolling forward process). This can take 3-10 minutes depending on how many blocks need validation. During this time:
- RPC may not respond
- Healthchecks will fail
- This is normal Bitcoin Core startup behavior

The container will become healthy once this process completes.
