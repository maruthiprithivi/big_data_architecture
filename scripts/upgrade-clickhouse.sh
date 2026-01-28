#!/bin/bash
set -e

echo "ClickHouse Upgrade to v26.1"
echo "==========================="
echo ""

# Check if backup script exists
if [ ! -f "./scripts/backup-clickhouse.sh" ]; then
    echo "ERROR: Backup script not found at ./scripts/backup-clickhouse.sh"
    echo "Cannot proceed without backup capability"
    exit 1
fi

# Stop collection
echo "Stopping data collection..."
curl -s -X POST http://localhost:8010/stop || echo "Warning: Could not stop collector"
sleep 5

# Create pre-upgrade backup
echo ""
echo "Creating pre-upgrade backup..."
./scripts/backup-clickhouse.sh

# Verify backup was created
LATEST_BACKUP=$(ls -t /var/backups/blockchain-ingestion/ 2>/dev/null | head -1 || echo "")
if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: Backup verification failed"
    echo "Aborting upgrade"
    curl -s -X POST http://localhost:8010/start
    exit 1
fi

echo "Backup created: $LATEST_BACKUP"
echo ""

# Get current table counts
echo "Recording current table counts..."
BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null || echo "0")

BITCOIN_TXS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_transactions" 2>/dev/null || echo "0")

SOLANA_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.solana_blocks" 2>/dev/null || echo "0")

echo "  Bitcoin blocks: $BITCOIN_BLOCKS"
echo "  Bitcoin transactions: $BITCOIN_TXS"
echo "  Solana blocks: $SOLANA_BLOCKS"
echo ""

# Stop ClickHouse
echo "Stopping ClickHouse..."
docker compose -f docker-compose.production.yml stop clickhouse

# Update docker-compose.yml to use v26.1
echo "Updating docker-compose.production.yml to use ClickHouse v26.1..."
sed -i.bak 's/clickhouse\/clickhouse-server:[0-9.]*-alpine/clickhouse\/clickhouse-server:26.1-alpine/' docker-compose.production.yml

# Verify the change
if grep -q "clickhouse-server:26.1-alpine" docker-compose.production.yml; then
    echo "docker-compose.production.yml updated successfully"
else
    echo "ERROR: Failed to update docker-compose.production.yml"
    echo "Restoring from backup..."
    mv docker-compose.production.yml.bak docker-compose.production.yml
    docker compose -f docker-compose.production.yml up -d clickhouse
    curl -s -X POST http://localhost:8010/start
    exit 1
fi

echo ""

# Pull v26.1 image
echo "Pulling ClickHouse v26.1 image..."
docker pull clickhouse/clickhouse-server:26.1-alpine

echo ""

# Start v26.1
echo "Starting ClickHouse v26.1..."
docker compose -f docker-compose.production.yml up -d clickhouse

# Wait for migration
echo "Waiting for ClickHouse to start and migrate data (this may take 2-3 minutes)..."
sleep 120

# Test connectivity with retries
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT 1" >/dev/null 2>&1; then
        echo "ClickHouse is responding"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for ClickHouse... attempt $RETRY_COUNT/$MAX_RETRIES"
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: ClickHouse failed to start after upgrade"
    echo "Check logs: docker compose -f docker-compose.production.yml logs clickhouse"
    echo ""
    echo "To rollback:"
    echo "1. docker compose -f docker-compose.production.yml stop clickhouse"
    echo "2. mv docker-compose.production.yml.bak docker-compose.production.yml"
    echo "3. docker compose -f docker-compose.production.yml up -d clickhouse"
    exit 1
fi

echo ""

# Verify version
VERSION=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT version()" 2>/dev/null)

echo "ClickHouse version: $VERSION"
echo ""

# Verify table counts
echo "Verifying table counts..."
NEW_BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null || echo "0")

NEW_BITCOIN_TXS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.bitcoin_transactions" 2>/dev/null || echo "0")

NEW_SOLANA_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT count() FROM blockchain_data.solana_blocks" 2>/dev/null || echo "0")

echo "  Bitcoin blocks: $NEW_BITCOIN_BLOCKS (was $BITCOIN_BLOCKS)"
echo "  Bitcoin transactions: $NEW_BITCOIN_TXS (was $BITCOIN_TXS)"
echo "  Solana blocks: $NEW_SOLANA_BLOCKS (was $SOLANA_BLOCKS)"
echo ""

if [ "$NEW_BITCOIN_BLOCKS" != "$BITCOIN_BLOCKS" ] || \
   [ "$NEW_BITCOIN_TXS" != "$BITCOIN_TXS" ] || \
   [ "$NEW_SOLANA_BLOCKS" != "$SOLANA_BLOCKS" ]; then
    echo "WARNING: Table counts do not match!"
    echo "Consider rolling back if counts are significantly different"
fi

echo ""
echo "ClickHouse upgraded to v26.1 successfully!"
echo ""
echo "Resume collection with:"
echo "  curl -X POST http://localhost:8010/start"
echo ""
echo "Next steps:"
echo "1. Apply tiered storage: docker compose -f docker-compose.production.yml exec clickhouse clickhouse-client --password=BlockchainData2026!Secure --queries-file=/docker-entrypoint-initdb.d/02-enable-tiering.sql"
echo "2. Set up Backblaze backups: ./scripts/setup-rclone.sh"
