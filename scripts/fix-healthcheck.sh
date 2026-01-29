#!/bin/bash
# Fix Bitcoin Core Healthcheck Issue

set -e

echo "Fixing Bitcoin Core Healthcheck"
echo "================================"
echo ""

# Backup current docker-compose
cp docker-compose.production.yml docker-compose.production.yml.backup-$(date +%Y%m%d-%H%M%S)

# Stop bitcoin-core container
echo "Stopping bitcoin-core container..."
docker compose -f docker-compose.production.yml stop bitcoin-core

# Start with updated configuration
echo "Starting bitcoin-core with fixed healthcheck..."
docker compose -f docker-compose.production.yml up -d bitcoin-core

# Wait for container to start
sleep 10

# Check health status
echo ""
echo "Checking container health..."
docker compose -f docker-compose.production.yml ps bitcoin-core

echo ""
echo "Healthcheck fix applied!"
echo "Container should become healthy in 2-3 minutes."
