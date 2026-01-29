#!/bin/bash
# Zero-Downtime Update Script
# Updates the blockchain data ingestion service on remote server

set -e

# Configuration
REMOTE_HOST="${REMOTE_HOST:-typeless_sandbox}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_DIR="/opt/blockchain-ingestion"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Parse options
SKIP_BACKUP=false
while getopts "s" opt; do
  case $opt in
    s)
      SKIP_BACKUP=true
      ;;
    *)
      echo "Usage: $0 [-s]"
      echo "  -s  Skip backup before update"
      exit 1
      ;;
  esac
done

# Check SSH connectivity
log_section "Pre-Update Checks"
log_info "Checking SSH connectivity to $REMOTE_HOST..."
if ! ssh -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" &> /dev/null; then
  log_error "Cannot connect to $REMOTE_HOST"
  exit 1
fi
log_info "SSH connectivity confirmed"

# Create backup before update (unless skipped)
if [ "$SKIP_BACKUP" = false ]; then
  log_section "Creating Pre-Update Backup"
  log_info "Creating backup on remote server..."
  ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && ./scripts/backup-clickhouse.sh"
  log_info "Backup completed"
else
  log_warn "Skipping pre-update backup (use caution)"
fi

# Stop data collection (preserve data)
log_section "Stopping Data Collection"
log_info "Stopping data collection..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && curl -s -X POST http://localhost:8000/stop || true"
sleep 2
log_info "Data collection stopped"

# Pull latest code from Git
log_section "Updating Code"
log_info "Pulling latest code on remote server..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && git pull origin main"

# Rebuild and restart collector and dashboard (keep ClickHouse running)
log_section "Rebuilding Services"
log_info "Rebuilding collector and dashboard containers..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker compose -f docker-compose.production.yml build collector dashboard"

log_info "Restarting collector and dashboard services..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker compose -f docker-compose.production.yml up -d --no-deps collector dashboard"

# Wait for services to stabilize
log_section "Waiting for Services"
log_info "Waiting for services to start (15 seconds)..."
sleep 15

# Verify services are healthy
log_section "Health Check"
log_info "Checking service health..."
HEALTH_CHECK=$(ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && curl -s http://localhost:8000/health || echo 'FAILED'")
if [[ "$HEALTH_CHECK" == *"FAILED"* ]]; then
  log_error "Health check failed after update"
  log_error "Services may need manual intervention"
  exit 1
else
  log_info "Health check passed"
fi

# Resume data collection
log_section "Resuming Collection"
log_info "Restarting data collection..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && curl -s -X POST http://localhost:8000/start || true"
sleep 2

# Verify collection is active
COLLECTION_STATUS=$(ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && curl -s http://localhost:8000/status | jq -r '.is_collecting' 2>/dev/null || echo 'unknown'")
if [ "$COLLECTION_STATUS" = "true" ]; then
  log_info "Data collection resumed successfully"
elif [ "$COLLECTION_STATUS" = "false" ]; then
  log_warn "Collection is stopped - may need manual start"
else
  log_warn "Could not verify collection status"
fi

# Display final status
log_section "Update Complete"
log_info "Service update completed successfully"
log_info ""
log_info "Next steps:"
log_info "  - Monitor logs: ssh $REMOTE_USER@$REMOTE_HOST 'cd $REMOTE_DIR && ./scripts/manage.sh logs'"
log_info "  - Check health: ssh $REMOTE_USER@$REMOTE_HOST 'cd $REMOTE_DIR && ./scripts/health-check.sh'"
log_info "  - View dashboard: Access http://<REMOTE_IP>:3001"
