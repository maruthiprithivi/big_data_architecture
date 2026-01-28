#!/bin/bash
set -e

echo "Installing ClickHouse Backup Timer"
echo "==================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if systemd files exist
if [ ! -f "scripts/clickhouse-backup.service" ] || [ ! -f "scripts/clickhouse-backup.timer" ]; then
    echo "ERROR: systemd files not found in scripts directory"
    exit 1
fi

# Copy systemd files
echo "Installing systemd files..."
cp scripts/clickhouse-backup.service /etc/systemd/system/
cp scripts/clickhouse-backup.timer /etc/systemd/system/

# Set proper permissions
chmod 644 /etc/systemd/system/clickhouse-backup.service
chmod 644 /etc/systemd/system/clickhouse-backup.timer

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start timer
echo "Enabling backup timer..."
systemctl enable clickhouse-backup.timer
systemctl start clickhouse-backup.timer

echo ""
echo "Backup timer installed and enabled!"
echo ""
echo "Status:"
systemctl status clickhouse-backup.timer --no-pager
echo ""
echo "Next backup scheduled for: 2:00 AM daily"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status clickhouse-backup.timer   # Check timer status"
echo "  sudo systemctl list-timers                      # List all timers"
echo "  sudo journalctl -u clickhouse-backup.service    # View backup logs"
echo "  sudo systemctl start clickhouse-backup.service  # Run backup manually"
