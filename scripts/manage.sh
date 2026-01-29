#!/bin/bash
# Management CLI for Blockchain Data Ingestion Service
# Provides simple commands to control the service

set -e

COMPOSE_FILE="docker-compose.production.yml"
API_URL="http://localhost:8000"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

show_usage() {
  echo "Blockchain Data Ingestion Service - Management CLI"
  echo ""
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Docker Service Commands:"
  echo "  start              Start all Docker services"
  echo "  stop               Stop all Docker services"
  echo "  restart            Restart all Docker services"
  echo "  status             Show status of all services"
  echo "  logs [service]     Show logs (optionally for specific service)"
  echo ""
  echo "Collection Control Commands:"
  echo "  start-collection   Start data collection"
  echo "  stop-collection    Stop data collection"
  echo "  collection-status  Show current collection status"
  echo ""
  echo "Monitoring Commands:"
  echo "  health             Check service health"
  echo "  stats              Show collection statistics"
  echo ""
  echo "Maintenance Commands:"
  echo "  backup             Create ClickHouse backup"
  echo "  cleanup-logs       Clean up old Docker logs"
  echo ""
  echo "Examples:"
  echo "  $0 start"
  echo "  $0 logs collector"
  echo "  $0 start-collection"
  echo "  $0 health"
}

case "$1" in
  start)
    log_info "Starting all services..."
    docker compose -f "$COMPOSE_FILE" up -d
    log_info "Services started successfully"
    ;;

  stop)
    log_info "Stopping all services..."
    docker compose -f "$COMPOSE_FILE" down
    log_info "Services stopped successfully"
    ;;

  restart)
    log_info "Restarting all services..."
    docker compose -f "$COMPOSE_FILE" restart
    log_info "Services restarted successfully"
    ;;

  status)
    log_info "Service status:"
    docker compose -f "$COMPOSE_FILE" ps
    ;;

  logs)
    SERVICE="${2:-}"
    if [ -n "$SERVICE" ]; then
      log_info "Showing logs for $SERVICE..."
      docker compose -f "$COMPOSE_FILE" logs -f "$SERVICE"
    else
      log_info "Showing logs for all services..."
      docker compose -f "$COMPOSE_FILE" logs -f
    fi
    ;;

  start-collection)
    log_info "Starting data collection..."
    RESPONSE=$(curl -s -X POST "$API_URL/start" || echo "FAILED")
    if [[ "$RESPONSE" == *"FAILED"* ]]; then
      log_error "Failed to start collection. Is the collector service running?"
      exit 1
    fi
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    log_info "Collection started successfully"
    ;;

  stop-collection)
    log_info "Stopping data collection..."
    RESPONSE=$(curl -s -X POST "$API_URL/stop" || echo "FAILED")
    if [[ "$RESPONSE" == *"FAILED"* ]]; then
      log_error "Failed to stop collection. Is the collector service running?"
      exit 1
    fi
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    log_info "Collection stopped successfully"
    ;;

  collection-status)
    log_info "Checking collection status..."
    RESPONSE=$(curl -s "$API_URL/status" || echo "FAILED")
    if [[ "$RESPONSE" == *"FAILED"* ]]; then
      log_error "Failed to get collection status. Is the collector service running?"
      exit 1
    fi
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    ;;

  health)
    log_info "Checking service health..."
    RESPONSE=$(curl -s "$API_URL/health" || echo "FAILED")
    if [[ "$RESPONSE" == *"FAILED"* ]]; then
      log_error "Health check failed. Is the collector service running?"
      exit 1
    fi
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    log_info "Health check completed"
    ;;

  stats)
    log_info "Fetching collection statistics..."
    RESPONSE=$(curl -s "$API_URL/stats" || echo "FAILED")
    if [[ "$RESPONSE" == *"FAILED"* ]]; then
      log_error "Failed to get statistics. Is the collector service running?"
      exit 1
    fi
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    ;;

  backup)
    log_info "Starting ClickHouse backup..."
    if [ -f "./scripts/backup-clickhouse.sh" ]; then
      ./scripts/backup-clickhouse.sh
    else
      log_error "Backup script not found at ./scripts/backup-clickhouse.sh"
      exit 1
    fi
    ;;

  cleanup-logs)
    log_info "Cleaning up Docker logs..."
    docker compose -f "$COMPOSE_FILE" logs --tail=0 > /dev/null 2>&1
    log_info "Docker logs cleaned up"
    ;;

  help|--help|-h|"")
    show_usage
    ;;

  *)
    log_error "Unknown command: $1"
    echo ""
    show_usage
    exit 1
    ;;
esac
