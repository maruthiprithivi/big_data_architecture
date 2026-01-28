#!/bin/bash
set -e

# Source environment variables
if [ -f .env.production ]; then
    export $(grep -v '^#' .env.production | grep BITCOIN_CORE_RPC_PASSWORD | xargs)
fi

# Default password if not set
RPC_PASSWORD=${BITCOIN_CORE_RPC_PASSWORD:-SECURE_PASSWORD_HERE}

echo "Bitcoin Historical Backfill"
echo "==========================="
echo ""

# Check Bitcoin Core is running
if ! docker compose -f docker-compose.production.yml ps bitcoin-core | grep -q "Up"; then
    echo "ERROR: Bitcoin Core is not running"
    echo "Start it with: docker compose -f docker-compose.production.yml up -d bitcoin-core"
    exit 1
fi

# Check Bitcoin Core is synced
BLOCKS=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
    getblockchaininfo 2>/dev/null | grep -o '"blocks":[0-9]*' | cut -d':' -f2)

HEADERS=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
    getblockchaininfo 2>/dev/null | grep -o '"headers":[0-9]*' | cut -d':' -f2)

if [ -z "$BLOCKS" ] || [ -z "$HEADERS" ]; then
    echo "ERROR: Could not connect to Bitcoin Core"
    exit 1
fi

if [ "$BLOCKS" != "$HEADERS" ]; then
    echo "ERROR: Bitcoin Core not fully synced"
    echo "Blocks: $BLOCKS / $HEADERS"
    echo "Wait for sync completion: ./scripts/check-bitcoin-sync.sh"
    exit 1
fi

echo "Bitcoin Core is synced: $BLOCKS blocks"
echo ""

# Check current backfill status
CURRENT_BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null || echo "0")

echo "Current Bitcoin blocks in ClickHouse: $CURRENT_BITCOIN_BLOCKS"
echo ""

# Enable backfill configuration
echo "Updating configuration for historical backfill..."
sed -i.bak 's/^BITCOIN_USE_LOCAL_NODE=.*/BITCOIN_USE_LOCAL_NODE=true/' .env.production
sed -i.bak 's/^ENABLE_HISTORICAL_BACKFILL=.*/ENABLE_HISTORICAL_BACKFILL=true/' .env.production
sed -i.bak 's/^BITCOIN_START_BLOCK=.*/BITCOIN_START_BLOCK=0/' .env.production
sed -i.bak 's/^PARALLEL_BLOCK_FETCH_COUNT=.*/PARALLEL_BLOCK_FETCH_COUNT=50/' .env.production

echo "Configuration updated:"
echo "  - BITCOIN_USE_LOCAL_NODE=true"
echo "  - ENABLE_HISTORICAL_BACKFILL=true"
echo "  - BITCOIN_START_BLOCK=0"
echo "  - PARALLEL_BLOCK_FETCH_COUNT=50"
echo ""

# Restart collector to apply new configuration
echo "Restarting collector with new configuration..."
docker compose -f docker-compose.production.yml restart collector

# Wait for collector to start
sleep 5

# Start collection
echo "Starting collection..."
curl -s -X POST http://localhost:8010/start

echo ""
echo "Historical backfill started!"
echo ""
echo "Monitor progress with:"
echo "  ./scripts/monitor-backfill.sh"
echo ""
echo "View logs with:"
echo "  docker compose -f docker-compose.production.yml logs -f collector"
echo ""
echo "Expected duration: 2-4 weeks for 880,000+ blocks"
