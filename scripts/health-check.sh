#!/bin/bash
# Health Check Script
# Comprehensive health monitoring for blockchain data ingestion service

set -e

# Configuration
COMPOSE_FILE="docker-compose.production.yml"
CONTAINER_CLICKHOUSE="blockchain_clickhouse_prod"
CONTAINER_COLLECTOR="blockchain_collector_prod"
CONTAINER_DASHBOARD="blockchain_dashboard_prod"
API_URL="http://localhost:8000"

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-clickhouse_password}"
CLICKHOUSE_DB="${CLICKHOUSE_DB:-blockchain_data}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

HEALTH_OK=0
HEALTH_ERROR=0

log_info() {
  echo -e "${GREEN}[OK]${NC} $1"
  HEALTH_OK=$((HEALTH_OK + 1))
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  HEALTH_ERROR=$((HEALTH_ERROR + 1))
}

log_section() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Check Docker service
log_section "Docker Service Status"
if systemctl is-active --quiet docker; then
  log_info "Docker service is running"
else
  log_error "Docker service is not running"
fi

# Check container status
log_section "Container Status"
for container in "$CONTAINER_CLICKHOUSE" "$CONTAINER_COLLECTOR" "$CONTAINER_DASHBOARD"; do
  if docker ps | grep -q "$container"; then
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container")
    if [ "$STATUS" = "running" ]; then
      log_info "Container $container is running"
    else
      log_error "Container $container is in state: $STATUS"
    fi
  else
    log_error "Container $container is not running"
  fi
done

# Check collector API health
log_section "Collector API Health"
if curl -s -f "$API_URL/health" > /dev/null 2>&1; then
  HEALTH_RESPONSE=$(curl -s "$API_URL/health")
  log_info "Collector API is responding"
  echo "$HEALTH_RESPONSE" | jq '.' 2>/dev/null || echo "$HEALTH_RESPONSE"
else
  log_error "Collector API is not responding at $API_URL/health"
fi

# Check collector status
log_section "Collection Status"
if curl -s -f "$API_URL/status" > /dev/null 2>&1; then
  STATUS_RESPONSE=$(curl -s "$API_URL/status")
  echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"

  IS_COLLECTING=$(echo "$STATUS_RESPONSE" | jq -r '.is_collecting' 2>/dev/null || echo "unknown")
  if [ "$IS_COLLECTING" = "true" ]; then
    log_info "Data collection is active"
  elif [ "$IS_COLLECTING" = "false" ]; then
    log_warn "Data collection is stopped"
  else
    log_error "Could not determine collection status"
  fi
else
  log_error "Could not retrieve collection status"
fi

# Check ClickHouse connectivity
log_section "ClickHouse Database"
if docker exec "$CONTAINER_CLICKHOUSE" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT 1" > /dev/null 2>&1; then
  log_info "ClickHouse is accepting connections"
else
  log_error "ClickHouse is not accepting connections"
fi

# Check table sizes and row counts
log_section "Database Statistics"
echo ""
echo "Table Row Counts:"
docker exec "$CONTAINER_CLICKHOUSE" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --database="$CLICKHOUSE_DB" \
  --query="
    SELECT
      table AS Table,
      formatReadableQuantity(total_rows) AS Rows,
      formatReadableSize(total_bytes) AS Size
    FROM system.tables
    WHERE database = '$CLICKHOUSE_DB'
    AND table NOT LIKE '.%'
    ORDER BY total_bytes DESC
    FORMAT PrettyCompact
  " 2>/dev/null || log_error "Could not retrieve table statistics"

# Check recent collection metrics
log_section "Recent Collection Activity"
echo ""
echo "Last 5 collection events:"
docker exec "$CONTAINER_CLICKHOUSE" clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --database="$CLICKHOUSE_DB" \
  --query="
    SELECT
      source,
      records_collected,
      metric_time,
      age(now(), metric_time) AS time_ago
    FROM collection_metrics
    ORDER BY metric_time DESC
    LIMIT 5
    FORMAT PrettyCompact
  " 2>/dev/null || log_warn "Could not retrieve recent collection metrics"

# Check disk space
log_section "Disk Space Usage"
DISK_USAGE=$(df -h /var/lib/blockchain-data 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
if [ -n "$DISK_USAGE" ]; then
  if [ "$DISK_USAGE" -lt 80 ]; then
    log_info "Disk usage is at ${DISK_USAGE}%"
  elif [ "$DISK_USAGE" -lt 90 ]; then
    log_warn "Disk usage is at ${DISK_USAGE}% (consider cleanup)"
  else
    log_error "Disk usage is at ${DISK_USAGE}% (critical - cleanup required)"
  fi
else
  log_warn "Could not determine disk usage for /var/lib/blockchain-data"
fi

# Summary
log_section "Health Check Summary"
echo ""
if [ $HEALTH_ERROR -eq 0 ]; then
  echo -e "${GREEN}All checks passed ($HEALTH_OK OK, 0 errors)${NC}"
  exit 0
else
  echo -e "${RED}Health check failed ($HEALTH_OK OK, $HEALTH_ERROR errors)${NC}"
  exit 1
fi
