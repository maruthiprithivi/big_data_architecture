#!/bin/bash

# Quick Bitcoin Sync Status Check
# Simple script that just shows Bitcoin Core sync progress

echo "Bitcoin Core Sync Status"
echo "========================"
echo ""

# Get sync info
SYNC_INFO=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd \
    getblockchaininfo 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$SYNC_INFO" ]; then
    # Extract key metrics using grep instead of jq (more portable)
    BLOCKS=$(echo "$SYNC_INFO" | grep -o '"blocks":[0-9]*' | cut -d':' -f2)
    HEADERS=$(echo "$SYNC_INFO" | grep -o '"headers":[0-9]*' | cut -d':' -f2)
    SIZE=$(echo "$SYNC_INFO" | grep -o '"size_on_disk":[0-9]*' | cut -d':' -f2)

    if [ -n "$BLOCKS" ] && [ -n "$HEADERS" ]; then
        # Calculate progress using awk
        PROGRESS=$(awk "BEGIN {printf \"%.2f\", ($BLOCKS * 100.0 / $HEADERS)}")
        REMAINING=$((HEADERS - BLOCKS))
        SIZE_GB=$(awk "BEGIN {printf \"%.2f\", ($SIZE / 1024 / 1024 / 1024)}")

        echo "Progress: $PROGRESS%"
        echo "Blocks: $BLOCKS / $HEADERS"
        echo "Remaining: $REMAINING blocks"
        echo "Disk Usage: ${SIZE_GB} GB"
        echo ""

        if [ "$BLOCKS" -eq "$HEADERS" ]; then
            echo "SYNC COMPLETE!"
            echo "Ready for Phase 2: ./scripts/start-historical-backfill.sh"
        else
            echo "Status: Syncing (check daily)"
        fi
    else
        echo "Error: Could not parse blockchain info"
    fi
else
    echo "Error: Bitcoin Core not responding"
    echo "Check if container is running: docker compose ps bitcoin-core"
fi

echo ""
echo "Last checked: $(date)"
