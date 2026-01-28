#!/bin/bash
set -e

BITCOIN_DATA_DIR="/var/lib/blockchain-data/bitcoin"
COMPOSE_FILE="docker-compose.production.yml"

echo "Bitcoin Core Installation"
echo "========================="
echo ""

# Check disk space (need 700+ GB)
AVAILABLE_SPACE=$(df -BG /var/lib 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "0")
if [ "$AVAILABLE_SPACE" -lt 700 ]; then
    echo "ERROR: Insufficient disk space. Available: ${AVAILABLE_SPACE}GB, Required: 700GB"
    exit 1
fi

echo "Disk space check passed: ${AVAILABLE_SPACE}GB available"
echo ""

# Create data directory
echo "Creating Bitcoin data directory: $BITCOIN_DATA_DIR"
sudo mkdir -p "$BITCOIN_DATA_DIR"
sudo chown -R $USER:$USER "$BITCOIN_DATA_DIR"
echo "Directory created successfully"
echo ""

# Start Bitcoin Core
echo "Starting Bitcoin Core container..."
docker compose -f "$COMPOSE_FILE" up -d bitcoin-core

echo ""
echo "Bitcoin Core started successfully!"
echo ""
echo "Monitor sync progress with:"
echo "  ./scripts/check-bitcoin-sync.sh"
echo ""
echo "View logs with:"
echo "  docker compose -f $COMPOSE_FILE logs -f bitcoin-core"
echo ""
echo "Expected sync time: 7-14 days (depends on network and hardware)"
