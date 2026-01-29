#!/bin/bash
# Monitoring and Alert Script
# Checks system health and sends alerts if issues are detected
# Can be run via cron for continuous monitoring

set -e

# Configuration
API_URL="http://localhost:8000"
DISK_WARNING_THRESHOLD=90
DISK_CRITICAL_THRESHOLD=95
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ALERT_COUNT=0
ALERT_MESSAGES=()

log_info() {
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  ALERT_COUNT=$((ALERT_COUNT + 1))
  ALERT_MESSAGES+=("$1")
}

send_slack_alert() {
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    return
  fi

  local message="$1"
  local color="${2:-danger}"

  curl -s -X POST "$SLACK_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "{
      \"attachments\": [{
        \"color\": \"$color\",
        \"title\": \"Blockchain Data Ingestion Alert\",
        \"text\": \"$message\",
        \"footer\": \"$(hostname)\",
        \"ts\": $(date +%s)
      }]
    }" > /dev/null 2>&1
}

# Check collector API health
if ! curl -s -f "$API_URL/health" > /dev/null 2>&1; then
  log_error "Collector API is not responding"
else
  log_info "Collector API is healthy"
fi

# Check collection status
if curl -s -f "$API_URL/status" > /dev/null 2>&1; then
  STATUS_RESPONSE=$(curl -s "$API_URL/status")
  IS_COLLECTING=$(echo "$STATUS_RESPONSE" | jq -r '.is_collecting' 2>/dev/null || echo "unknown")

  if [ "$IS_COLLECTING" = "false" ]; then
    log_warn "Data collection is currently stopped"
  elif [ "$IS_COLLECTING" = "true" ]; then
    log_info "Data collection is active"
  else
    log_error "Could not determine collection status"
  fi
else
  log_error "Could not retrieve collection status"
fi

# Check disk space
if [ -d "/var/lib/blockchain-data" ]; then
  DISK_USAGE=$(df /var/lib/blockchain-data | awk 'NR==2 {print $5}' | sed 's/%//')

  if [ -n "$DISK_USAGE" ]; then
    if [ "$DISK_USAGE" -ge "$DISK_CRITICAL_THRESHOLD" ]; then
      log_error "CRITICAL: Disk usage at ${DISK_USAGE}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)"
    elif [ "$DISK_USAGE" -ge "$DISK_WARNING_THRESHOLD" ]; then
      log_warn "WARNING: Disk usage at ${DISK_USAGE}% (threshold: ${DISK_WARNING_THRESHOLD}%)"
    else
      log_info "Disk usage is healthy at ${DISK_USAGE}%"
    fi
  fi
fi

# Check Docker container status
CONTAINERS=("blockchain_clickhouse_prod" "blockchain_collector_prod" "blockchain_dashboard_prod")
for container in "${CONTAINERS[@]}"; do
  if docker ps | grep -q "$container"; then
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "running" ]; then
      log_info "Container $container is running"
    else
      log_error "Container $container is in state: $STATUS"
    fi
  else
    log_error "Container $container is not running"
  fi
done

# Check ClickHouse connectivity
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-clickhouse_password}"
if docker exec blockchain_clickhouse_prod clickhouse-client \
  --password="$CLICKHOUSE_PASSWORD" \
  --query="SELECT 1" > /dev/null 2>&1; then
  log_info "ClickHouse is accepting connections"
else
  log_error "ClickHouse is not accepting connections"
fi

# Send alerts if there are issues
if [ $ALERT_COUNT -gt 0 ]; then
  echo ""
  echo -e "${RED}ALERT: $ALERT_COUNT issue(s) detected${NC}"

  # Build alert message
  ALERT_MESSAGE="$ALERT_COUNT issue(s) detected in blockchain data ingestion service:\n"
  for msg in "${ALERT_MESSAGES[@]}"; do
    ALERT_MESSAGE+="\n- $msg"
  done

  # Send to Slack if configured
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    send_slack_alert "$ALERT_MESSAGE" "danger"
    echo "Alert sent to Slack"
  else
    echo "Slack webhook not configured (set SLACK_WEBHOOK_URL to enable)"
  fi

  exit 1
else
  log_info "All monitoring checks passed"
  exit 0
fi
