#!/bin/bash

echo "Bitcoin Historical Backfill Progress"
echo "====================================="
echo ""

# Get Bitcoin blockchain height
BITCOIN_CHAIN_HEIGHT=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="${BITCOIN_CORE_RPC_PASSWORD:-SECURE_PASSWORD_HERE}" \
    getblockcount 2>/dev/null || echo "0")

# Get blocks in ClickHouse
BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null || echo "0")

BITCOIN_TXS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_transactions" 2>/dev/null || echo "0")

# Calculate progress
if [ "$BITCOIN_CHAIN_HEIGHT" -gt 0 ]; then
    PROGRESS=$(echo "scale=2; $BITCOIN_BLOCKS * 100 / $BITCOIN_CHAIN_HEIGHT" | bc)
else
    PROGRESS="0.00"
fi

REMAINING=$((BITCOIN_CHAIN_HEIGHT - BITCOIN_BLOCKS))

echo "Bitcoin Blocks: $BITCOIN_BLOCKS / $BITCOIN_CHAIN_HEIGHT ($PROGRESS%)"
echo "Bitcoin Transactions: $BITCOIN_TXS"
echo "Remaining: $REMAINING blocks"
echo ""

# Get latest block timestamp
LATEST_BLOCK=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT max(block_height), max(timestamp) FROM blockchain_data.bitcoin_blocks FORMAT TabSeparated" 2>/dev/null)

if [ -n "$LATEST_BLOCK" ]; then
    LATEST_HEIGHT=$(echo "$LATEST_BLOCK" | cut -f1)
    LATEST_TIME=$(echo "$LATEST_BLOCK" | cut -f2)
    echo "Latest block: $LATEST_HEIGHT at $LATEST_TIME"
    echo ""
fi

# Get collection rate from metrics
RECENT_RATE=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="
    SELECT
        round(avg(records_collected) / (avg(collection_duration_ms) / 1000), 2) as records_per_sec
    FROM blockchain_data.collection_metrics
    WHERE source = 'bitcoin'
      AND metric_time > now() - INTERVAL 1 HOUR
      AND records_collected > 0
    " 2>/dev/null)

if [ -n "$RECENT_RATE" ] && [ "$RECENT_RATE" != "0" ]; then
    echo "Collection rate: $RECENT_RATE records/second"

    # Estimate time remaining
    if [ "$REMAINING" -gt 0 ]; then
        SECONDS_REMAINING=$(echo "scale=0; $REMAINING / $RECENT_RATE" | bc)
        DAYS_REMAINING=$(echo "scale=1; $SECONDS_REMAINING / 86400" | bc)
        echo "Estimated time remaining: $DAYS_REMAINING days"
    fi
fi

echo ""

# Check if backfill is complete
if [ "$BITCOIN_BLOCKS" -ge "$BITCOIN_CHAIN_HEIGHT" ] && [ "$BITCOIN_CHAIN_HEIGHT" -gt 0 ]; then
    echo "BACKFILL COMPLETE!"
    echo ""
    echo "Next steps:"
    echo "1. Enable Bitcoin Core pruning: ./scripts/enable-bitcoin-pruning.sh"
    echo "2. Upgrade ClickHouse to v26.1: ./scripts/upgrade-clickhouse.sh"
else
    echo "Backfill in progress..."
    echo ""
    echo "Check again later:"
    echo "  watch -n 300 ./scripts/monitor-backfill.sh  # Updates every 5 minutes"
fi
