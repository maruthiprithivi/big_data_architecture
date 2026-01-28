#!/bin/bash
set -e

echo "rclone Setup for Backblaze B2"
echo "============================="
echo ""

# Check if rclone is already installed
if command -v rclone &> /dev/null; then
    RCLONE_VERSION=$(rclone version | head -1)
    echo "rclone already installed: $RCLONE_VERSION"
    echo ""
else
    echo "Installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
    echo ""
fi

# Source environment variables
if [ -f .env.production ]; then
    export $(grep -v '^#' .env.production | grep -E 'BACKBLAZE_' | xargs)
else
    echo "ERROR: .env.production not found"
    exit 1
fi

# Check required environment variables
if [ -z "$BACKBLAZE_KEY_ID" ] || [ -z "$BACKBLAZE_APPLICATION_KEY" ] || [ -z "$BACKBLAZE_BUCKET" ]; then
    echo "ERROR: Missing Backblaze credentials in .env.production"
    echo "Required: BACKBLAZE_KEY_ID, BACKBLAZE_APPLICATION_KEY, BACKBLAZE_BUCKET"
    exit 1
fi

echo "Configuring rclone for Backblaze B2..."

# Create rclone config directory
mkdir -p ~/.config/rclone

# Create rclone configuration
cat > ~/.config/rclone/rclone.conf <<EOF
[backblaze]
type = b2
account = $BACKBLAZE_KEY_ID
key = $BACKBLAZE_APPLICATION_KEY
hard_delete = false
EOF

echo "rclone configuration created"
echo ""

# Test connection
echo "Testing connection to Backblaze..."
if rclone lsd backblaze:$BACKBLAZE_BUCKET 2>&1; then
    echo ""
    echo "Connection successful!"
    echo ""
    echo "Bucket: $BACKBLAZE_BUCKET"
    echo ""
    echo "Next steps:"
    echo "1. Create initial backup: ./scripts/backup-to-backblaze.sh"
    echo "2. Set up daily backups: sudo cp scripts/clickhouse-backup.* /etc/systemd/system/ && sudo systemctl enable clickhouse-backup.timer"
else
    echo ""
    echo "ERROR: Could not connect to Backblaze"
    echo "Please verify credentials in .env.production"
    exit 1
fi
