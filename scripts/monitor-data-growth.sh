#!/bin/bash
# 24-Hour Data Growth Monitoring Script
# Monitors ClickHouse tables every hour for 24 hours

set -e

# Configuration
REMOTE_HOST="typeless_sandbox"
CONTAINER_NAME="blockchain_clickhouse_prod"
DURATION_HOURS=24
CHECK_INTERVAL_SECONDS=3600  # 1 hour
OUTPUT_FILE="data_growth_report_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_header() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$OUTPUT_FILE"
}

# Function to query ClickHouse
query_clickhouse() {
  local query=$1
  ssh "$REMOTE_HOST" "docker exec $CONTAINER_NAME clickhouse-client --query=\"$query\" --format=TabSeparated" 2>/dev/null
}

# Function to get table metrics
get_table_metrics() {
  local table=$1
  local rows=$(query_clickhouse "SELECT count() FROM blockchain_data.$table")
  local size_bytes=$(query_clickhouse "SELECT sum(bytes_on_disk) FROM system.parts WHERE database='blockchain_data' AND table='$table' AND active=1")

  # Convert bytes to GB (handle empty result)
  if [ -z "$size_bytes" ] || [ "$size_bytes" = "0" ]; then
    size_bytes=0
  fi
  local size_gb=$(echo "scale=6; $size_bytes / 1073741824" | bc 2>/dev/null || echo "0")

  echo "$rows|$size_gb"
}

# Function to format number with commas
format_number() {
  printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# Initialize tracking variables
prev_bitcoin_blocks_rows=0
prev_bitcoin_blocks_size=0
prev_bitcoin_txs_rows=0
prev_bitcoin_txs_size=0
prev_solana_blocks_rows=0
prev_solana_blocks_size=0
prev_solana_txs_rows=0
prev_solana_txs_size=0

# Store initial baseline for 24-hour summary
baseline_bitcoin_blocks_rows=0
baseline_bitcoin_blocks_size=0
baseline_bitcoin_txs_rows=0
baseline_bitcoin_txs_size=0
baseline_solana_blocks_rows=0
baseline_solana_blocks_size=0
baseline_solana_txs_rows=0
baseline_solana_txs_size=0

# Get initial baseline
log_header "=========================================="
log_header "24-Hour Data Growth Monitoring Started"
log_header "=========================================="
log_info "Remote Host: $REMOTE_HOST"
log_info "Duration: $DURATION_HOURS hours"
log_info "Check Interval: Every 1 hour"
log_info "Output File: $OUTPUT_FILE"
log_header "==========================================="
echo "" | tee -a "$OUTPUT_FILE"

# Get initial metrics
log_info "Getting baseline metrics..."
bitcoin_blocks_data=$(get_table_metrics "bitcoin_blocks")
bitcoin_txs_data=$(get_table_metrics "bitcoin_transactions")
solana_blocks_data=$(get_table_metrics "solana_blocks")
solana_txs_data=$(get_table_metrics "solana_transactions")

prev_bitcoin_blocks_rows=$(echo "$bitcoin_blocks_data" | cut -d'|' -f1)
prev_bitcoin_blocks_size=$(echo "$bitcoin_blocks_data" | cut -d'|' -f2)
prev_bitcoin_txs_rows=$(echo "$bitcoin_txs_data" | cut -d'|' -f1)
prev_bitcoin_txs_size=$(echo "$bitcoin_txs_data" | cut -d'|' -f2)
prev_solana_blocks_rows=$(echo "$solana_blocks_data" | cut -d'|' -f1)
prev_solana_blocks_size=$(echo "$solana_blocks_data" | cut -d'|' -f2)
prev_solana_txs_rows=$(echo "$solana_txs_data" | cut -d'|' -f1)
prev_solana_txs_size=$(echo "$solana_txs_data" | cut -d'|' -f2)

# Store baseline
baseline_bitcoin_blocks_rows=$prev_bitcoin_blocks_rows
baseline_bitcoin_blocks_size=$prev_bitcoin_blocks_size
baseline_bitcoin_txs_rows=$prev_bitcoin_txs_rows
baseline_bitcoin_txs_size=$prev_bitcoin_txs_size
baseline_solana_blocks_rows=$prev_solana_blocks_rows
baseline_solana_blocks_size=$prev_solana_blocks_size
baseline_solana_txs_rows=$prev_solana_txs_rows
baseline_solana_txs_size=$prev_solana_txs_size

log_info "Baseline Metrics:"
echo "  Bitcoin Blocks:       $(format_number $prev_bitcoin_blocks_rows) rows, $prev_bitcoin_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Bitcoin Transactions: $(format_number $prev_bitcoin_txs_rows) rows, $prev_bitcoin_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "  Solana Blocks:        $(format_number $prev_solana_blocks_rows) rows, $prev_solana_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Solana Transactions:  $(format_number $prev_solana_txs_rows) rows, $prev_solana_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Monitor for 24 hours
total_checks=$DURATION_HOURS
for ((check=1; check<=total_checks; check++)); do
  log_info "Waiting for next check ($check/$total_checks)..."
  sleep $CHECK_INTERVAL_SECONDS

  log_header "=========================================="
  log_header "HOURLY CHECK #$check (Hour $check of $DURATION_HOURS)"
  log_header "=========================================="

  # Get current metrics
  bitcoin_blocks_data=$(get_table_metrics "bitcoin_blocks")
  bitcoin_txs_data=$(get_table_metrics "bitcoin_transactions")
  solana_blocks_data=$(get_table_metrics "solana_blocks")
  solana_txs_data=$(get_table_metrics "solana_transactions")

  curr_bitcoin_blocks_rows=$(echo "$bitcoin_blocks_data" | cut -d'|' -f1)
  curr_bitcoin_blocks_size=$(echo "$bitcoin_blocks_data" | cut -d'|' -f2)
  curr_bitcoin_txs_rows=$(echo "$bitcoin_txs_data" | cut -d'|' -f1)
  curr_bitcoin_txs_size=$(echo "$bitcoin_txs_data" | cut -d'|' -f2)
  curr_solana_blocks_rows=$(echo "$solana_blocks_data" | cut -d'|' -f1)
  curr_solana_blocks_size=$(echo "$solana_blocks_data" | cut -d'|' -f2)
  curr_solana_txs_rows=$(echo "$solana_txs_data" | cut -d'|' -f1)
  curr_solana_txs_size=$(echo "$solana_txs_data" | cut -d'|' -f2)

  # Calculate growth
  bitcoin_blocks_growth=$((curr_bitcoin_blocks_rows - prev_bitcoin_blocks_rows))
  bitcoin_txs_growth=$((curr_bitcoin_txs_rows - prev_bitcoin_txs_rows))
  solana_blocks_growth=$((curr_solana_blocks_rows - prev_solana_blocks_rows))
  solana_txs_growth=$((curr_solana_txs_rows - prev_solana_txs_rows))

  bitcoin_blocks_size_growth=$(echo "scale=6; $curr_bitcoin_blocks_size - $prev_bitcoin_blocks_size" | bc)
  bitcoin_txs_size_growth=$(echo "scale=6; $curr_bitcoin_txs_size - $prev_bitcoin_txs_size" | bc)
  solana_blocks_size_growth=$(echo "scale=6; $curr_solana_blocks_size - $prev_solana_blocks_size" | bc)
  solana_txs_size_growth=$(echo "scale=6; $curr_solana_txs_size - $prev_solana_txs_size" | bc)

  # Display current state and growth
  echo "" | tee -a "$OUTPUT_FILE"
  log_info "Bitcoin Blocks:"
  echo "  Current:  $(format_number $curr_bitcoin_blocks_rows) rows, $curr_bitcoin_blocks_size GB" | tee -a "$OUTPUT_FILE"
  echo "  Growth:   $(format_number $bitcoin_blocks_growth) rows/hour, $bitcoin_blocks_size_growth GB/hour" | tee -a "$OUTPUT_FILE"
  echo "" | tee -a "$OUTPUT_FILE"

  log_info "Bitcoin Transactions:"
  echo "  Current:  $(format_number $curr_bitcoin_txs_rows) rows, $curr_bitcoin_txs_size GB" | tee -a "$OUTPUT_FILE"
  echo "  Growth:   $(format_number $bitcoin_txs_growth) rows/hour, $bitcoin_txs_size_growth GB/hour" | tee -a "$OUTPUT_FILE"
  echo "" | tee -a "$OUTPUT_FILE"

  log_info "Solana Blocks:"
  echo "  Current:  $(format_number $curr_solana_blocks_rows) rows, $curr_solana_blocks_size GB" | tee -a "$OUTPUT_FILE"
  echo "  Growth:   $(format_number $solana_blocks_growth) rows/hour, $solana_blocks_size_growth GB/hour" | tee -a "$OUTPUT_FILE"
  echo "" | tee -a "$OUTPUT_FILE"

  log_info "Solana Transactions:"
  echo "  Current:  $(format_number $curr_solana_txs_rows) rows, $curr_solana_txs_size GB" | tee -a "$OUTPUT_FILE"
  echo "  Growth:   $(format_number $solana_txs_growth) rows/hour, $solana_txs_size_growth GB/hour" | tee -a "$OUTPUT_FILE"
  echo "" | tee -a "$OUTPUT_FILE"

  # Total growth summary
  total_row_growth=$((bitcoin_blocks_growth + bitcoin_txs_growth + solana_blocks_growth + solana_txs_growth))
  total_size_growth=$(echo "scale=6; $bitcoin_blocks_size_growth + $bitcoin_txs_size_growth + $solana_blocks_size_growth + $solana_txs_size_growth" | bc)

  log_header "HOURLY SUMMARY:"
  echo "  Total rows added:     $(format_number $total_row_growth) rows/hour" | tee -a "$OUTPUT_FILE"
  echo "  Total size increase:  $total_size_growth GB/hour" | tee -a "$OUTPUT_FILE"
  echo "" | tee -a "$OUTPUT_FILE"

  # Check collection health
  health_check=$(ssh "$REMOTE_HOST" "curl -s http://localhost:8010/health" 2>/dev/null || echo "failed")
  if echo "$health_check" | grep -q '"status":"healthy"'; then
    log_info "Collection Status: Healthy"
  else
    log_warn "Collection Status: Unhealthy or Unable to Check"
  fi

  log_header "==========================================="
  echo "" | tee -a "$OUTPUT_FILE"

  # Update previous values for next iteration
  prev_bitcoin_blocks_rows=$curr_bitcoin_blocks_rows
  prev_bitcoin_blocks_size=$curr_bitcoin_blocks_size
  prev_bitcoin_txs_rows=$curr_bitcoin_txs_rows
  prev_bitcoin_txs_size=$curr_bitcoin_txs_size
  prev_solana_blocks_rows=$curr_solana_blocks_rows
  prev_solana_blocks_size=$curr_solana_blocks_size
  prev_solana_txs_rows=$curr_solana_txs_rows
  prev_solana_txs_size=$curr_solana_txs_size
done

# Final summary
log_header "=========================================="
log_header "24-Hour Monitoring Complete"
log_header "=========================================="

# Get final metrics
final_bitcoin_blocks_data=$(get_table_metrics "bitcoin_blocks")
final_bitcoin_txs_data=$(get_table_metrics "bitcoin_transactions")
final_solana_blocks_data=$(get_table_metrics "solana_blocks")
final_solana_txs_data=$(get_table_metrics "solana_transactions")

final_bitcoin_blocks_rows=$(echo "$final_bitcoin_blocks_data" | cut -d'|' -f1)
final_bitcoin_blocks_size=$(echo "$final_bitcoin_blocks_data" | cut -d'|' -f2)
final_bitcoin_txs_rows=$(echo "$final_bitcoin_txs_data" | cut -d'|' -f1)
final_bitcoin_txs_size=$(echo "$final_bitcoin_txs_data" | cut -d'|' -f2)
final_solana_blocks_rows=$(echo "$final_solana_blocks_data" | cut -d'|' -f1)
final_solana_blocks_size=$(echo "$final_solana_blocks_data" | cut -d'|' -f2)
final_solana_txs_rows=$(echo "$final_solana_txs_data" | cut -d'|' -f1)
final_solana_txs_size=$(echo "$final_solana_txs_data" | cut -d'|' -f2)

# Calculate 24-hour totals from baseline
log_info "24-Hour Growth Report:"
echo "" | tee -a "$OUTPUT_FILE"
echo "Bitcoin Blocks:" | tee -a "$OUTPUT_FILE"
echo "  Started:  $(format_number $baseline_bitcoin_blocks_rows) rows, $baseline_bitcoin_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Ended:    $(format_number $final_bitcoin_blocks_rows) rows, $final_bitcoin_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Growth:   $(format_number $((final_bitcoin_blocks_rows - baseline_bitcoin_blocks_rows))) rows in 24 hours" | tee -a "$OUTPUT_FILE"
echo "  Size +/-: $(echo "scale=6; $final_bitcoin_blocks_size - $baseline_bitcoin_blocks_size" | bc) GB" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "Bitcoin Transactions:" | tee -a "$OUTPUT_FILE"
echo "  Started:  $(format_number $baseline_bitcoin_txs_rows) rows, $baseline_bitcoin_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "  Ended:    $(format_number $final_bitcoin_txs_rows) rows, $final_bitcoin_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "  Growth:   $(format_number $((final_bitcoin_txs_rows - baseline_bitcoin_txs_rows))) rows in 24 hours" | tee -a "$OUTPUT_FILE"
echo "  Size +/-: $(echo "scale=6; $final_bitcoin_txs_size - $baseline_bitcoin_txs_size" | bc) GB" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "Solana Blocks:" | tee -a "$OUTPUT_FILE"
echo "  Started:  $(format_number $baseline_solana_blocks_rows) rows, $baseline_solana_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Ended:    $(format_number $final_solana_blocks_rows) rows, $final_solana_blocks_size GB" | tee -a "$OUTPUT_FILE"
echo "  Growth:   $(format_number $((final_solana_blocks_rows - baseline_solana_blocks_rows))) rows in 24 hours" | tee -a "$OUTPUT_FILE"
echo "  Size +/-: $(echo "scale=6; $final_solana_blocks_size - $baseline_solana_blocks_size" | bc) GB" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "Solana Transactions:" | tee -a "$OUTPUT_FILE"
echo "  Started:  $(format_number $baseline_solana_txs_rows) rows, $baseline_solana_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "  Ended:    $(format_number $final_solana_txs_rows) rows, $final_solana_txs_size GB" | tee -a "$OUTPUT_FILE"
echo "  Growth:   $(format_number $((final_solana_txs_rows - baseline_solana_txs_rows))) rows in 24 hours" | tee -a "$OUTPUT_FILE"
echo "  Size +/-: $(echo "scale=6; $final_solana_txs_size - $baseline_solana_txs_size" | bc) GB" | tee -a "$OUTPUT_FILE"

# Total 24-hour growth
total_24h_rows=$((final_bitcoin_blocks_rows + final_bitcoin_txs_rows + final_solana_blocks_rows + final_solana_txs_rows - baseline_bitcoin_blocks_rows - baseline_bitcoin_txs_rows - baseline_solana_blocks_rows - baseline_solana_txs_rows))
total_24h_size=$(echo "scale=6; ($final_bitcoin_blocks_size + $final_bitcoin_txs_size + $final_solana_blocks_size + $final_solana_txs_size) - ($baseline_bitcoin_blocks_size + $baseline_bitcoin_txs_size + $baseline_solana_blocks_size + $baseline_solana_txs_size)" | bc)

echo "" | tee -a "$OUTPUT_FILE"
log_header "TOTAL 24-HOUR GROWTH:"
echo "  Total rows added:     $(format_number $total_24h_rows) rows" | tee -a "$OUTPUT_FILE"
echo "  Total size increase:  $total_24h_size GB" | tee -a "$OUTPUT_FILE"
echo "  Average per hour:     $(format_number $((total_24h_rows / 24))) rows/hour" | tee -a "$OUTPUT_FILE"

log_header "==========================================="
log_info "Report saved to: $OUTPUT_FILE"
