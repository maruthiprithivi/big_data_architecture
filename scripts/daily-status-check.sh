#!/bin/bash

# Daily Status Check for Hybrid Architecture
# Run this daily to monitor Bitcoin Core sync and system health

set +e

echo "=========================================="
echo "Blockchain Infrastructure Status"
echo "$(date)"
echo "=========================================="
echo ""

# Load environment variables
if [ -f .env.production ]; then
    set -a
    source .env.production
    set +a
fi

# Use password from env or default
RPC_PASSWORD=${BITCOIN_CORE_RPC_PASSWORD:-jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd}

#------------------------------------------
# Bitcoin Core Sync Status
#------------------------------------------
echo "Bitcoin Core Sync Progress"
echo "--------------------------"

if docker compose -f docker-compose.production.yml ps bitcoin-core | grep -q "Up"; then
    SYNC_INFO=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
        bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
        getblockchaininfo 2>/dev/null)

    if [ -n "$SYNC_INFO" ]; then
        BLOCKS=$(echo "$SYNC_INFO" | grep -o '"blocks":[0-9]*' | cut -d':' -f2)
        HEADERS=$(echo "$SYNC_INFO" | grep -o '"headers":[0-9]*' | cut -d':' -f2)
        SIZE_GB=$(echo "$SYNC_INFO" | jq -r '.size_on_disk / 1024 / 1024 / 1024' | xargs printf "%.2f")

        if [ -n "$BLOCKS" ] && [ -n "$HEADERS" ]; then
            if command -v bc &> /dev/null; then
                PROGRESS=$(echo "scale=2; $BLOCKS * 100 / $HEADERS" | bc)
            else
                PROGRESS=$(awk "BEGIN {printf \"%.2f\", $BLOCKS * 100 / $HEADERS}")
            fi
            REMAINING=$((HEADERS - BLOCKS))

            echo "  Status: Syncing"
            echo "  Progress: $PROGRESS%"
            echo "  Blocks: $BLOCKS / $HEADERS"
            echo "  Remaining: $REMAINING blocks"
            echo "  Disk Usage: ${SIZE_GB} GB"

            if [ "$BLOCKS" -eq "$HEADERS" ]; then
                echo ""
                echo "  SYNC COMPLETE!"
                echo "  Ready for Phase 2: Historical Backfill"
                echo "  Run: ./scripts/start-historical-backfill.sh"
            fi
        fi
    else
        echo "  Status: RPC not responding"
    fi
else
    echo "  Status: Container not running"
fi

echo ""

#------------------------------------------
# ClickHouse Status
#------------------------------------------
echo "ClickHouse Data Collection"
echo "--------------------------"

if docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT 1" >/dev/null 2>&1; then

    BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null)

    SOLANA_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT count() FROM blockchain_data.solana_blocks" 2>/dev/null)

    echo "  Bitcoin blocks: $BITCOIN_BLOCKS"
    echo "  Solana blocks: $SOLANA_BLOCKS"
else
    echo "  Status: ClickHouse not responding"
fi

echo ""

#------------------------------------------
# Disk Space
#------------------------------------------
echo "Disk Space"
echo "----------"

TOTAL_USAGE=$(df -h /var/lib | tail -1 | awk '{print $5}')
AVAILABLE=$(df -h /var/lib | tail -1 | awk '{print $4}')

echo "  Total usage: $TOTAL_USAGE"
echo "  Available: $AVAILABLE"

BTC_SIZE=$(du -sh /var/lib/blockchain-data/bitcoin 2>/dev/null | cut -f1)
if [ -n "$BTC_SIZE" ]; then
    echo "  Bitcoin Core: $BTC_SIZE"
fi

CH_SIZE=$(du -sh /var/lib/blockchain-data/clickhouse 2>/dev/null | cut -f1)
if [ -n "$CH_SIZE" ]; then
    echo "  ClickHouse: $CH_SIZE"
fi

echo ""

#------------------------------------------
# Phase Tracker
#------------------------------------------
echo "Deployment Progress"
echo "-------------------"

# Check which phase we're in
if [ -n "$BLOCKS" ] && [ -n "$HEADERS" ] && [ "$BLOCKS" -eq "$HEADERS" ] && [ "$BLOCKS" -gt 900000 ]; then
    if [ "$BITCOIN_BLOCKS" -gt 800000 ]; then
        echo "  Current Phase: 3 (Pruning) or later"
    else
        echo "  Current Phase: 2 (Historical Backfill)"
        echo "  Action: Monitor backfill progress"
    fi
elif [ -n "$BLOCKS" ] && [ -n "$HEADERS" ] && [ "$BLOCKS" -eq "$HEADERS" ]; then
    echo "  Current Phase: 1 Complete"
    echo "  Next: Start Phase 2 (Historical Backfill)"
    echo "  Action: ./scripts/start-historical-backfill.sh"
else
    echo "  Current Phase: 1 (Bitcoin Core Sync)"
    echo "  Action: Wait for sync completion (check daily)"
fi

echo ""
echo "=========================================="
echo "Next Check: $(date -d '+1 day' 2>/dev/null || date -v +1d 2>/dev/null)"
echo "=========================================="
