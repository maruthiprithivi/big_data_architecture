#!/bin/bash
set -e

echo "Enable Bitcoin Core Pruning"
echo "==========================="
echo ""

# Verify backfill is complete
BITCOIN_CHAIN_HEIGHT=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="${BITCOIN_CORE_RPC_PASSWORD:-SECURE_PASSWORD_HERE}" \
    getblockcount 2>/dev/null || echo "0")

BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null || echo "0")

if [ "$BITCOIN_BLOCKS" -lt 800000 ]; then
    echo "ERROR: Backfill incomplete. Only $BITCOIN_BLOCKS blocks in ClickHouse."
    echo "Current blockchain height: $BITCOIN_CHAIN_HEIGHT"
    echo ""
    echo "Wait for backfill to complete:"
    echo "  ./scripts/monitor-backfill.sh"
    exit 1
fi

echo "Backfill verified: $BITCOIN_BLOCKS blocks in ClickHouse"
echo ""

# Check current Bitcoin Core disk usage
BITCOIN_SIZE=$(du -sh /var/lib/blockchain-data/bitcoin 2>/dev/null | cut -f1 || echo "unknown")
echo "Current Bitcoin Core disk usage: $BITCOIN_SIZE"
echo ""

# Stop Bitcoin Core
echo "Stopping Bitcoin Core..."
docker compose -f docker-compose.production.yml stop bitcoin-core

# Update bitcoin.conf with pruning
echo "Updating bitcoin.conf to enable pruning (200 GB)..."
sed -i.bak 's/^prune=0/prune=200000/' bitcoin-core/bitcoin.conf

# Verify the change
if grep -q "^prune=200000" bitcoin-core/bitcoin.conf; then
    echo "bitcoin.conf updated successfully"
else
    echo "ERROR: Failed to update bitcoin.conf"
    echo "Restoring from backup..."
    mv bitcoin-core/bitcoin.conf.bak bitcoin-core/bitcoin.conf
    docker compose -f docker-compose.production.yml up -d bitcoin-core
    exit 1
fi

echo ""

# Start Bitcoin Core with pruning
echo "Starting Bitcoin Core with pruning enabled..."
docker compose -f docker-compose.production.yml up -d bitcoin-core

echo ""
echo "Bitcoin Core pruning enabled!"
echo ""
echo "Pruning will reduce disk usage from ~650 GB to ~200 GB over the next few hours."
echo ""
echo "Monitor disk usage with:"
echo "  watch -n 300 'du -sh /var/lib/blockchain-data/bitcoin'"
echo ""
echo "Check Bitcoin Core logs:"
echo "  docker compose -f docker-compose.production.yml logs -f bitcoin-core"
echo ""
echo "Expected final size: ~200 GB"
