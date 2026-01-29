#!/bin/bash
# Automated Deployment Script to Hetzner (typeless_sandbox)
# This script deploys the blockchain data ingestion service to the remote server

set -e

# Configuration
REMOTE_HOST="typeless_sandbox"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_DIR="/opt/blockchain-ingestion"
DATA_DIR="/var/lib/blockchain-data"
BACKUP_DIR="/var/backups/blockchain-ingestion"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check SSH connectivity
log_info "Checking SSH connectivity to $REMOTE_HOST..."
if ! ssh -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" &> /dev/null; then
  log_error "Cannot connect to $REMOTE_HOST. Please check your SSH configuration."
  log_error "Ensure ~/.ssh/config has an entry for 'typeless_sandbox' or set REMOTE_USER environment variable."
  exit 1
fi
log_info "SSH connectivity confirmed"

# Detect available ClickHouse port on remote server
log_info "Detecting available ClickHouse port on remote server..."
AVAILABLE_PORT=$(ssh "$REMOTE_USER@$REMOTE_HOST" 'bash -s' < scripts/detect-ports.sh)
if [ $? -ne 0 ]; then
  log_error "Failed to detect available port on remote server"
  exit 1
fi
log_info "Using ClickHouse HTTP port: $AVAILABLE_PORT"

# Create remote directories
log_info "Creating remote directories..."
ssh "$REMOTE_USER@$REMOTE_HOST" "sudo mkdir -p $REMOTE_DIR $DATA_DIR/clickhouse $DATA_DIR/collector-state $BACKUP_DIR && sudo chown -R \$USER:\$USER $REMOTE_DIR $DATA_DIR $BACKUP_DIR"

# Sync files to remote server
log_info "Syncing files to remote server (excluding data/, node_modules/, .git/)..."
rsync -avz --exclude 'data/' \
           --exclude 'node_modules/' \
           --exclude '.git/' \
           --exclude '.env' \
           --exclude '__pycache__/' \
           --exclude '*.pyc' \
           --exclude '.next/' \
           --exclude 'venv/' \
           --progress \
           . "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

# Copy production environment file
log_info "Setting up production environment file..."
scp .env.production "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/.env"

# Update ClickHouse port in remote .env file
log_info "Updating ClickHouse port to $AVAILABLE_PORT in remote .env..."
ssh "$REMOTE_USER@$REMOTE_HOST" "sed -i 's/^CLICKHOUSE_PORT=.*/CLICKHOUSE_PORT=$AVAILABLE_PORT/' $REMOTE_DIR/.env"

# Deploy services using docker compose
log_info "Deploying services with docker compose..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker compose -f docker-compose.production.yml up --build -d"

# Wait for services to start
log_info "Waiting for services to start (30 seconds)..."
sleep 30

# Check service health
log_info "Checking service health..."
HEALTH_CHECK=$(ssh "$REMOTE_USER@$REMOTE_HOST" "curl -s http://localhost:8000/health || echo 'FAILED'")
if [[ "$HEALTH_CHECK" == *"FAILED"* ]]; then
  log_warn "Health check failed. Services may still be starting up."
else
  log_info "Health check passed"
fi

# Get remote IP address
REMOTE_IP=$(ssh "$REMOTE_USER@$REMOTE_HOST" "curl -s ifconfig.me || echo 'UNKNOWN'")

# Display deployment information
echo ""
log_info "=========================================="
log_info "Deployment completed successfully!"
log_info "=========================================="
echo ""
log_info "Service URLs:"
log_info "  - Dashboard: http://$REMOTE_IP:3001"
log_info "  - API: http://$REMOTE_IP:8000"
log_info "  - ClickHouse HTTP: http://$REMOTE_IP:$AVAILABLE_PORT"
echo ""
log_info "Next steps:"
log_info "  1. SSH to server: ssh $REMOTE_USER@$REMOTE_HOST"
log_info "  2. View logs: cd $REMOTE_DIR && ./scripts/manage.sh logs"
log_info "  3. Start collection: ./scripts/manage.sh start-collection"
log_info "  4. Set up systemd service (see DEPLOYMENT.md)"
echo ""
log_info "To check service status:"
log_info "  ssh $REMOTE_USER@$REMOTE_HOST 'cd $REMOTE_DIR && docker compose -f docker-compose.production.yml ps'"
echo ""
