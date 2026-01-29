#!/bin/bash
# ClickHouse Backup Script
# Creates timestamped backups of ClickHouse data and cleans up old backups

set -e

# Configuration
BACKUP_DIR="/var/backups/blockchain-ingestion"
CONTAINER_NAME="blockchain_clickhouse_prod"
COMPOSE_FILE="docker-compose.production.yml"
KEEP_DAYS=7

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-clickhouse_password}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-blockchain_data}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

log_info "Starting ClickHouse backup..."
log_info "Backup location: $BACKUP_PATH"

# Check if ClickHouse container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
  log_error "ClickHouse container is not running"
  exit 1
fi

# Stop data collection during backup
log_info "Stopping data collection..."
curl -s -X POST http://localhost:8000/stop > /dev/null 2>&1 || log_warn "Could not stop collection (may already be stopped)"
sleep 2

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Backup database using clickhouse-client
log_info "Creating database backup..."
docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.bitcoin_blocks FORMAT Native" > "$BACKUP_PATH/bitcoin_blocks.native" 2>/dev/null || true

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.bitcoin_transactions FORMAT Native" > "$BACKUP_PATH/bitcoin_transactions.native" 2>/dev/null || true

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.solana_blocks FORMAT Native" > "$BACKUP_PATH/solana_blocks.native" 2>/dev/null || true

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.solana_transactions FORMAT Native" > "$BACKUP_PATH/solana_transactions.native" 2>/dev/null || true

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.collection_state FORMAT Native" > "$BACKUP_PATH/collection_state.native" 2>/dev/null || true

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT * FROM $CLICKHOUSE_DB.collection_metrics FORMAT Native" > "$BACKUP_PATH/collection_metrics.native" 2>/dev/null || true

# Backup schema
log_info "Backing up database schema..."
docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SHOW CREATE DATABASE $CLICKHOUSE_DB" > "$BACKUP_PATH/schema.sql"

docker exec "$CONTAINER_NAME" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --database="$CLICKHOUSE_DB" \
  --query="SHOW TABLES" | while read table; do
  docker exec "$CONTAINER_NAME" clickhouse-client \
    --password="$CLICKHOUSE_PASSWORD" \
    --database="$CLICKHOUSE_DB" \
    --query="SHOW CREATE TABLE $table" >> "$BACKUP_PATH/schema.sql"
done

# Get backup size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
log_info "Backup completed: $BACKUP_SIZE"

# Restart data collection
log_info "Restarting data collection..."
curl -s -X POST http://localhost:8000/start > /dev/null 2>&1 || log_warn "Could not restart collection automatically"

# Clean up old backups
log_info "Cleaning up backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -type d -mtime +$KEEP_DAYS -exec rm -rf {} + 2>/dev/null || true

# List current backups
log_info "Current backups:"
ls -lh "$BACKUP_DIR" | tail -n +2

log_info "Backup completed successfully"
log_info "To restore this backup, use: scripts/restore-clickhouse.sh $TIMESTAMP"
