#!/bin/bash
# Set up daily cron job for sync status monitoring

set -e

echo "Setting up daily Bitcoin sync monitoring"
echo "========================================"
echo ""

# Create cron job that runs daily at 8 AM
CRON_CMD="0 8 * * * cd /opt/blockchain-ingestion && /opt/blockchain-ingestion/scripts/check-sync.sh >> /var/log/bitcoin-sync.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "check-sync.sh"; then
    echo "Cron job already exists"
else
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo "Cron job added: Daily sync check at 8:00 AM"
fi

echo ""
echo "View cron jobs: crontab -l"
echo "View sync logs: tail -f /var/log/bitcoin-sync.log"
echo ""

# Create initial log file
touch /var/log/bitcoin-sync.log
chmod 644 /var/log/bitcoin-sync.log

echo "Setup complete!"
