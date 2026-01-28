#!/bin/bash

# System Health Check for Hybrid Architecture
# Validates all components: Bitcoin Core, ClickHouse, Collector, Backups, Storage

set +e  # Don't exit on errors, we want to check everything

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

echo "========================================"
echo "System Health Check"
echo "========================================"
echo ""
echo "Timestamp: $(date)"
echo ""

# Source environment variables
if [ -f .env.production ]; then
    export $(grep -v '^#' .env.production | grep -E 'BITCOIN_CORE_RPC_PASSWORD|BACKBLAZE_' | xargs)
fi

RPC_PASSWORD=${BITCOIN_CORE_RPC_PASSWORD:-SECURE_PASSWORD_HERE}

#----------------------------------------
# Docker Services
#----------------------------------------
echo "Docker Services"
echo "----------------"

if docker compose -f docker-compose.production.yml ps | grep -q "Up"; then
    pass "Docker Compose services are running"
else
    fail "Docker Compose services are not running"
fi

# Check individual services
if docker compose -f docker-compose.production.yml ps clickhouse | grep -q "Up"; then
    pass "ClickHouse container is running"
else
    fail "ClickHouse container is not running"
fi

if docker compose -f docker-compose.production.yml ps collector | grep -q "Up"; then
    pass "Collector container is running"
else
    fail "Collector container is not running"
fi

if docker compose -f docker-compose.production.yml ps dashboard | grep -q "Up"; then
    pass "Dashboard container is running"
else
    fail "Dashboard container is not running"
fi

if docker compose -f docker-compose.production.yml ps bitcoin-core | grep -q "Up"; then
    pass "Bitcoin Core container is running"
elif docker compose -f docker-compose.production.yml ps bitcoin-core 2>/dev/null | grep -q "bitcoin-core"; then
    warn "Bitcoin Core container exists but not running"
else
    warn "Bitcoin Core container not deployed (Phase 1 not started)"
fi

echo ""

#----------------------------------------
# Bitcoin Core (if deployed)
#----------------------------------------
if docker compose -f docker-compose.production.yml ps bitcoin-core 2>/dev/null | grep -q "Up"; then
    echo "Bitcoin Core"
    echo "------------"

    # Test RPC connectivity
    if docker compose -f docker-compose.production.yml exec -T bitcoin-core \
        bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
        getblockchaininfo >/dev/null 2>&1; then
        pass "Bitcoin Core RPC is responding"

        # Check sync status
        SYNC_INFO=$(docker compose -f docker-compose.production.yml exec -T bitcoin-core \
            bitcoin-cli -rpcuser=blockchain_collector -rpcpassword="$RPC_PASSWORD" \
            getblockchaininfo 2>/dev/null)

        BLOCKS=$(echo "$SYNC_INFO" | grep -o '"blocks":[0-9]*' | cut -d':' -f2)
        HEADERS=$(echo "$SYNC_INFO" | grep -o '"headers":[0-9]*' | cut -d':' -f2)

        if [ "$BLOCKS" -eq "$HEADERS" ]; then
            pass "Bitcoin Core is fully synced ($BLOCKS blocks)"
        else
            REMAINING=$((HEADERS - BLOCKS))
            warn "Bitcoin Core syncing: $BLOCKS / $HEADERS ($REMAINING remaining)"
        fi

        # Check pruning status
        PRUNED=$(echo "$SYNC_INFO" | grep -o '"pruned":[a-z]*' | cut -d':' -f2)
        if [ "$PRUNED" = "true" ]; then
            pass "Bitcoin Core pruning is enabled"
        else
            warn "Bitcoin Core pruning not enabled (will use ~650 GB)"
        fi

    else
        fail "Bitcoin Core RPC not responding"
    fi

    # Check disk usage
    BTC_SIZE=$(docker exec blockchain_bitcoin_core du -sh /home/bitcoin/.bitcoin 2>/dev/null | cut -f1)
    if [ -n "$BTC_SIZE" ]; then
        echo "     Bitcoin Core disk usage: $BTC_SIZE"
    fi

    echo ""
fi

#----------------------------------------
# ClickHouse
#----------------------------------------
echo "ClickHouse"
echo "----------"

if docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT 1" >/dev/null 2>&1; then
    pass "ClickHouse is responding"

    # Check version
    VERSION=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT version()" 2>/dev/null)
    echo "     ClickHouse version: $VERSION"

    if echo "$VERSION" | grep -q "26.1"; then
        pass "ClickHouse v26.1 detected (S3 tiering available)"
    else
        warn "ClickHouse not on v26.1 (tiered storage not available)"
    fi

    # Check table counts
    BITCOIN_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT count() FROM blockchain_data.bitcoin_blocks" 2>/dev/null)

    if [ "$BITCOIN_BLOCKS" -gt 0 ]; then
        pass "Bitcoin blocks collected: $BITCOIN_BLOCKS"
    else
        warn "No Bitcoin blocks collected yet"
    fi

    BITCOIN_TXS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT count() FROM blockchain_data.bitcoin_transactions" 2>/dev/null)

    if [ "$BITCOIN_TXS" -gt 0 ]; then
        pass "Bitcoin transactions collected: $BITCOIN_TXS"
    fi

    SOLANA_BLOCKS=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT count() FROM blockchain_data.solana_blocks" 2>/dev/null)

    if [ "$SOLANA_BLOCKS" -gt 0 ]; then
        pass "Solana blocks collected: $SOLANA_BLOCKS"
    fi

else
    fail "ClickHouse is not responding"
fi

echo ""

#----------------------------------------
# Storage
#----------------------------------------
echo "Storage"
echo "-------"

# Overall disk space
DISK_USAGE=$(df -h /var/lib 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
if [ -n "$DISK_USAGE" ]; then
    if [ "$DISK_USAGE" -lt 80 ]; then
        pass "Disk usage is healthy ($DISK_USAGE%)"
    elif [ "$DISK_USAGE" -lt 90 ]; then
        warn "Disk usage is high ($DISK_USAGE%)"
    else
        fail "Disk usage is critical ($DISK_USAGE%)"
    fi
fi

# ClickHouse disk usage
CH_SIZE=$(du -sh /var/lib/blockchain-data/clickhouse 2>/dev/null | cut -f1)
if [ -n "$CH_SIZE" ]; then
    echo "     ClickHouse data: $CH_SIZE"
fi

# Check storage policy (if ClickHouse v26.1+)
if docker compose -f docker-compose.production.yml exec -T clickhouse \
    clickhouse-client --password=BlockchainData2026!Secure \
    --query="SELECT version()" 2>/dev/null | grep -q "26.1"; then

    TIERED=$(docker compose -f docker-compose.production.yml exec -T clickhouse \
        clickhouse-client --password=BlockchainData2026!Secure \
        --query="SELECT storage_policy FROM system.tables WHERE database = 'blockchain_data' AND table = 'bitcoin_blocks'" 2>/dev/null)

    if [ "$TIERED" = "tiered_storage" ]; then
        pass "Tiered storage policy is active"
    else
        warn "Tiered storage policy not applied (Phase 6 not complete)"
    fi
fi

echo ""

#----------------------------------------
# Collector
#----------------------------------------
echo "Collector"
echo "---------"

if curl -s http://localhost:8010/health >/dev/null 2>&1; then
    pass "Collector API is responding"

    # Check collection status
    STATUS=$(curl -s http://localhost:8010/status 2>/dev/null | grep -o '"is_collecting":[a-z]*' | cut -d':' -f2)
    if [ "$STATUS" = "true" ]; then
        pass "Collection is active"
    else
        warn "Collection is not active"
    fi

else
    fail "Collector API is not responding"
fi

echo ""

#----------------------------------------
# Backups
#----------------------------------------
echo "Backups"
echo "-------"

# Check local backups
if [ -d "/var/backups/blockchain-ingestion" ]; then
    BACKUP_COUNT=$(ls -1 /var/backups/blockchain-ingestion/ 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        pass "Local backups exist ($BACKUP_COUNT backups)"
        LATEST_BACKUP=$(ls -t /var/backups/blockchain-ingestion/ 2>/dev/null | head -1)
        echo "     Latest: $LATEST_BACKUP"
    else
        warn "No local backups found"
    fi
else
    warn "Local backup directory not found"
fi

# Check Backblaze (if rclone configured)
if command -v rclone &> /dev/null && [ -n "$BACKBLAZE_BUCKET" ]; then
    if rclone lsd "backblaze:$BACKBLAZE_BUCKET" >/dev/null 2>&1; then
        pass "Backblaze connection successful"

        REMOTE_BACKUPS=$(rclone lsf "backblaze:$BACKBLAZE_BUCKET/clickhouse-backups" --max-depth 1 --dirs-only 2>/dev/null | wc -l)
        if [ "$REMOTE_BACKUPS" -gt 0 ]; then
            pass "Remote backups exist ($REMOTE_BACKUPS backups)"
        else
            warn "No remote backups found (Phase 5 not complete)"
        fi
    else
        warn "Cannot connect to Backblaze (check credentials)"
    fi
else
    warn "rclone not configured (Phase 5 not complete)"
fi

# Check backup timer
if systemctl is-enabled clickhouse-backup.timer >/dev/null 2>&1; then
    if systemctl is-active clickhouse-backup.timer >/dev/null 2>&1; then
        pass "Backup timer is enabled and active"
        NEXT_BACKUP=$(systemctl status clickhouse-backup.timer 2>/dev/null | grep "Trigger:" | awk '{print $2, $3, $4, $5}')
        if [ -n "$NEXT_BACKUP" ]; then
            echo "     Next backup: $NEXT_BACKUP"
        fi
    else
        warn "Backup timer is enabled but not active"
    fi
else
    warn "Backup timer not enabled (Phase 5 not complete)"
fi

echo ""

#----------------------------------------
# Dashboard
#----------------------------------------
echo "Dashboard"
echo "---------"

if curl -s http://localhost:3001/api/data/overview >/dev/null 2>&1; then
    pass "Dashboard API is responding"
else
    fail "Dashboard API is not responding"
fi

echo ""

#----------------------------------------
# Summary
#----------------------------------------
echo "========================================"
echo "Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC} $FAILED"
echo ""

if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}All checks passed! System is healthy.${NC}"
    exit 0
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}System is operational with warnings.${NC}"
    exit 0
else
    echo -e "${RED}System has failures that need attention.${NC}"
    exit 1
fi
