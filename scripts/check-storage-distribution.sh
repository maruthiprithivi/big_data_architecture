#!/bin/bash

echo "ClickHouse Storage Distribution"
echo "================================"
echo ""

# Check if ClickHouse is running
if ! docker compose -f docker-compose.production.yml ps clickhouse | grep -q "Up"; then
    echo "ERROR: ClickHouse is not running"
    exit 1
fi

# Get disk distribution from ClickHouse
echo "Storage by Disk:"
echo "----------------"
docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="
    SELECT
        disk_name,
        formatReadableSize(sum(bytes)) as total_size,
        count() as parts,
        count(DISTINCT table) as tables
    FROM system.parts
    WHERE database = 'blockchain_data' AND active = 1
    GROUP BY disk_name
    ORDER BY disk_name
    FORMAT PrettyCompact
    " 2>/dev/null

echo ""
echo "Storage by Table:"
echo "-----------------"
docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="
    SELECT
        table,
        disk_name,
        formatReadableSize(sum(bytes)) as size,
        count() as parts
    FROM system.parts
    WHERE database = 'blockchain_data' AND active = 1
    GROUP BY table, disk_name
    ORDER BY table, disk_name
    FORMAT PrettyCompact
    " 2>/dev/null

echo ""
echo "Local Disk Usage:"
echo "-----------------"
df -h /var/lib/blockchain-data/clickhouse 2>/dev/null | tail -1 | awk '{print "Used: " $3 " / " $2 " (" $5 ")"}'

echo ""

# Check Backblaze storage
if command -v rclone &> /dev/null; then
    # Source environment variables for Backblaze bucket name
    if [ -f .env.production ]; then
        export $(grep -v '^#' .env.production | grep BACKBLAZE_BUCKET | xargs)
    fi

    if [ -n "$BACKBLAZE_BUCKET" ]; then
        echo "Backblaze B2 Storage:"
        echo "---------------------"
        BACKBLAZE_SIZE=$(rclone size "backblaze:$BACKBLAZE_BUCKET" 2>/dev/null | grep "Total size:" | awk '{print $3, $4}')
        if [ -n "$BACKBLAZE_SIZE" ]; then
            echo "Total: $BACKBLAZE_SIZE"
        else
            echo "Unable to retrieve Backblaze size"
        fi
        echo ""
    fi
fi

# Get storage policy configuration
echo "Storage Policies:"
echo "-----------------"
docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="
    SELECT
        table,
        storage_policy
    FROM system.tables
    WHERE database = 'blockchain_data'
    ORDER BY table
    FORMAT PrettyCompact
    " 2>/dev/null

echo ""

# Show data movement (TTL) status
echo "Data Movement Status (TTL):"
echo "---------------------------"
docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="
    SELECT
        table,
        count() as total_parts,
        countIf(disk_name = 'default') as hot_parts,
        countIf(disk_name != 'default') as cold_parts,
        formatReadableSize(sumIf(bytes, disk_name = 'default')) as hot_size,
        formatReadableSize(sumIf(bytes, disk_name != 'default')) as cold_size
    FROM system.parts
    WHERE database = 'blockchain_data' AND active = 1
    GROUP BY table
    ORDER BY table
    FORMAT PrettyCompact
    " 2>/dev/null

echo ""
echo "Note: ClickHouse runs TTL operations every 15 minutes"
echo "Data older than 30 days will be gradually moved to Backblaze"
