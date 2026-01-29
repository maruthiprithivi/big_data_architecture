#!/bin/bash
# Management script for historical data backfill
#
# EDUCATIONAL NOTE - Backfill Management:
# This script provides a convenient interface for managing historical blockchain data collection.
# It allows you to start/stop backfill operations, check progress, and view current configuration.
#
# Usage:
#   ./scripts/manage-backfill.sh start [bitcoin_start_block] [solana_start_slot]
#   ./scripts/manage-backfill.sh stop
#   ./scripts/manage-backfill.sh progress
#   ./scripts/manage-backfill.sh status

set -e  # Exit on any error

REMOTE_HOST="typeless_sandbox"
API_URL="http://localhost:8010"
PROJECT_DIR="/opt/blockchain-ingestion"

case "$1" in
  start)
    echo "========================================="
    echo "Starting Historical Backfill"
    echo "========================================="
    echo ""

    BITCOIN_START="${2:-0}"
    SOLANA_START="${3:-0}"

    echo "Configuration:"
    echo "  Bitcoin starting block: $BITCOIN_START"
    echo "  Solana starting slot:   $SOLANA_START"
    echo ""

    # Confirm with user
    read -p "This will modify .env and restart the collector. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 1
    fi

    echo ""
    echo "Updating .env.production on remote server..."
    ssh $REMOTE_HOST "cd $PROJECT_DIR && \
      sed -i 's/ENABLE_HISTORICAL_BACKFILL=.*/ENABLE_HISTORICAL_BACKFILL=true/' .env.production && \
      sed -i 's/BITCOIN_START_BLOCK=.*/BITCOIN_START_BLOCK=$BITCOIN_START/' .env.production && \
      sed -i 's/SOLANA_START_SLOT=.*/SOLANA_START_SLOT=$SOLANA_START/' .env.production"

    echo "Restarting collector container..."
    ssh $REMOTE_HOST "cd $PROJECT_DIR && \
      docker compose -f docker-compose.production.yml restart collector"

    echo ""
    echo "========================================="
    echo "Backfill Started Successfully"
    echo "========================================="
    echo ""
    echo "Monitor progress with:"
    echo "  ./scripts/manage-backfill.sh progress"
    echo ""
    echo "Or view logs with:"
    echo "  ssh $REMOTE_HOST 'docker logs -f blockchain_collector_prod'"
    ;;

  stop)
    echo "========================================="
    echo "Stopping Historical Backfill"
    echo "========================================="
    echo ""
    echo "Switching to real-time collection only..."

    ssh $REMOTE_HOST "cd $PROJECT_DIR && \
      sed -i 's/ENABLE_HISTORICAL_BACKFILL=.*/ENABLE_HISTORICAL_BACKFILL=false/' .env.production && \
      sed -i 's/BITCOIN_START_BLOCK=.*/BITCOIN_START_BLOCK=-1/' .env.production && \
      sed -i 's/SOLANA_START_SLOT=.*/SOLANA_START_SLOT=-1/' .env.production"

    echo "Restarting collector container..."
    ssh $REMOTE_HOST "cd $PROJECT_DIR && \
      docker compose -f docker-compose.production.yml restart collector"

    echo ""
    echo "========================================="
    echo "Backfill Stopped"
    echo "========================================="
    echo ""
    echo "Collector is now in real-time mode (collecting only new blocks)"
    ;;

  progress)
    echo "========================================="
    echo "Backfill Progress"
    echo "========================================="
    echo ""

    # Fetch progress from API
    ssh $REMOTE_HOST "curl -s $API_URL/backfill-progress | jq" || {
      echo "Error: Could not fetch progress from API"
      echo "Make sure the collector is running and accessible at $API_URL"
      exit 1
    }
    ;;

  status)
    echo "========================================="
    echo "Current Backfill Configuration"
    echo "========================================="
    echo ""

    ssh $REMOTE_HOST "cd $PROJECT_DIR && grep -E 'HISTORICAL|START_BLOCK|START_SLOT|TX_LIMIT|PARALLEL|BATCH' .env.production"

    echo ""
    echo "========================================="
    echo "Collector Status"
    echo "========================================="
    echo ""

    # Check if collector is running
    if ssh $REMOTE_HOST "docker ps --filter name=blockchain_collector_prod --format '{{.Status}}'" | grep -q "Up"; then
      echo "Status: Running"
      echo ""
      ssh $REMOTE_HOST "curl -s $API_URL/status | jq '.is_running, .total_records, .records_per_second'"
    else
      echo "Status: Not Running"
    fi
    ;;

  *)
    echo "Usage: $0 {start|stop|progress|status} [bitcoin_start_block] [solana_start_slot]"
    echo ""
    echo "Commands:"
    echo "  start [bitcoin_block] [solana_slot]  - Start historical backfill"
    echo "  stop                                  - Stop backfill, switch to real-time"
    echo "  progress                              - Show backfill progress"
    echo "  status                                - Show current configuration"
    echo ""
    echo "Examples:"
    echo "  $0 start 0 0              # Start from genesis for both chains"
    echo "  $0 start 800000 0         # Start Bitcoin from block 800000, Solana from genesis"
    echo "  $0 start 850000 280000000 # Start from recent blocks"
    echo "  $0 progress               # Show backfill progress"
    echo "  $0 stop                   # Stop backfill, switch to real-time"
    echo "  $0 status                 # Show current configuration"
    echo ""
    echo "WARNINGS:"
    echo "  - Historical backfill can take days/weeks for full blockchain history"
    echo "  - Ensure sufficient disk space (500GB+ for full Bitcoin history)"
    echo "  - Monitor API rate limits to avoid being blocked"
    echo "  - Use 'progress' command regularly to monitor backfill status"
    exit 1
    ;;
esac
