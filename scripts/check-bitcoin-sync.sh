#!/bin/bash
set -e

# Source environment variables
if [ -f .env.production ]; then
    export $(grep -v '^#' .env.production | grep BITCOIN_CORE_RPC_PASSWORD | xargs)
fi

# Default password if not set
RPC_PASSWORD=${BITCOIN_CORE_RPC_PASSWORD:-SECURE_PASSWORD_HERE}

# Get blockchain info from Bitcoin Core
SYNC_INFO=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
    getblockchaininfo 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "ERROR: Could not connect to Bitcoin Core"
    echo "Make sure Bitcoin Core is running: docker compose -f docker-compose.production.yml ps"
    exit 1
fi

# Parse JSON output
BLOCKS=$(echo "$SYNC_INFO" | grep -o '"blocks":[0-9]*' | cut -d':' -f2)
HEADERS=$(echo "$SYNC_INFO" | grep -o '"headers":[0-9]*' | cut -d':' -f2)
PROGRESS=$(echo "$SYNC_INFO" | grep -o '"verificationprogress":[0-9.]*' | cut -d':' -f2)
PROGRESS_PERCENT=$(echo "$PROGRESS * 100" | bc | xargs printf "%.2f")
SIZE_BYTES=$(echo "$SYNC_INFO" | grep -o '"size_on_disk":[0-9]*' | cut -d':' -f2)
SIZE_GB=$(echo "scale=2; $SIZE_BYTES / 1024 / 1024 / 1024" | bc)

echo "Bitcoin Core Sync Progress"
echo "=========================="
echo "Progress: $PROGRESS_PERCENT%"
echo "Blocks: $BLOCKS / $HEADERS"
echo "Disk Usage: ${SIZE_GB} GB"
echo ""

if [ "$BLOCKS" -eq "$HEADERS" ]; then
    echo "SYNC COMPLETE! Ready for Phase 2 (Historical Backfill)."
    echo ""
    echo "Next steps:"
    echo "1. Verify sync: docker compose -f docker-compose.production.yml exec bitcoin-core bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=\"$RPC_PASSWORD\" getblockcount"
    echo "2. Start backfill: ./scripts/start-historical-backfill.sh"
else
    REMAINING=$((HEADERS - BLOCKS))
    echo "Syncing... $REMAINING blocks remaining"
    echo ""
    echo "Check again in a few hours or tomorrow."
    echo "View live logs: docker compose -f docker-compose.production.yml logs -f bitcoin-core"
fi
