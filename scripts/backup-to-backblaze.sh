#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DAY_OF_WEEK=$(date +%u)

echo "ClickHouse Backup to Backblaze"
echo "==============================="
echo "Timestamp: $TIMESTAMP"
echo ""

# Source environment variables
if [ -f .env.production ]; then
    export $(grep -v '^#' .env.production | grep -E 'BACKBLAZE_' | xargs)
else
    echo "ERROR: .env.production not found"
    exit 1
fi

# Determine backup type (full on Sunday, incremental other days)
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    BACKUP_TYPE="full"
else
    BACKUP_TYPE="incremental"
fi

BACKUP_NAME="clickhouse_${BACKUP_TYPE}_${TIMESTAMP}"

echo "Backup type: $BACKUP_TYPE"
echo "Backup name: $BACKUP_NAME"
echo ""

# Pause collection
echo "Pausing data collection..."
curl -s -X POST http://localhost:8010/stop || echo "Warning: Could not stop collector"
sleep 5

# Create local backup directory
BACKUP_DIR="/var/lib/blockchain-data/clickhouse-backups/$BACKUP_NAME"
sudo mkdir -p "$BACKUP_DIR"

# Create backup using ClickHouse BACKUP command
echo "Creating ClickHouse backup..."
docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="BACKUP DATABASE blockchain_data TO Disk('default', 'backups/$BACKUP_NAME')"

echo "Backup created: $BACKUP_NAME"
echo ""

# Resume collection
echo "Resuming data collection..."
curl -s -X POST http://localhost:8010/start || echo "Warning: Could not start collector"

# Get backup size
BACKUP_SIZE=$(du -sh "/var/lib/blockchain-data/clickhouse/backups/$BACKUP_NAME" 2>/dev/null | cut -f1 || echo "unknown")
echo "Backup size: $BACKUP_SIZE"
echo ""

# Upload to Backblaze
echo "Uploading to Backblaze B2..."
rclone sync "/var/lib/blockchain-data/clickhouse/backups/$BACKUP_NAME" \
    "backblaze:$BACKBLAZE_BUCKET/clickhouse-backups/$BACKUP_NAME" \
    --progress \
    --transfers=8 \
    --b2-upload-cutoff=200M \
    --log-level INFO

echo ""
echo "Upload complete"
echo ""

# Clean up old local backups (keep last 3)
echo "Cleaning up old local backups (keeping last 3)..."
cd /var/lib/blockchain-data/clickhouse/backups/
ls -t | tail -n +4 | xargs -I {} sudo rm -rf {}
echo "Local cleanup complete"
echo ""

# Clean up old remote backups (30-day retention)
echo "Cleaning up old remote backups (30-day retention)..."
CUTOFF_DATE=$(date -d '30 days ago' +%Y%m%d 2>/dev/null || date -v-30d +%Y%m%d)

rclone lsf "backblaze:$BACKBLAZE_BUCKET/clickhouse-backups" --max-depth 1 --dirs-only | while read backup_dir; do
    # Extract date from backup directory name (format: clickhouse_TYPE_YYYYMMDD-HHMMSS)
    BACKUP_DATE=$(echo "$backup_dir" | grep -oP '\d{8}(?=-\d{6})' || echo "")

    if [ -n "$BACKUP_DATE" ]; then
        if [ "$BACKUP_DATE" -lt "$CUTOFF_DATE" ]; then
            echo "Deleting old backup: $backup_dir (date: $BACKUP_DATE)"
            rclone purge "backblaze:$BACKBLAZE_BUCKET/clickhouse-backups/$backup_dir"
        fi
    fi
done

echo "Remote cleanup complete"
echo ""

# List current backups
echo "Current backups on Backblaze:"
rclone lsf "backblaze:$BACKBLAZE_BUCKET/clickhouse-backups" --max-depth 1 --dirs-only | sort
echo ""

echo "Backup complete: $BACKUP_NAME"
echo ""
echo "Backup location: backblaze:$BACKBLAZE_BUCKET/clickhouse-backups/$BACKUP_NAME"
