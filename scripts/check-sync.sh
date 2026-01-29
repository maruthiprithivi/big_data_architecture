#!/bin/bash
# Simple Bitcoin Core Sync Check

cd /opt/blockchain-ingestion

echo "Bitcoin Core Sync Progress"
echo "==========================="
echo ""

docker compose -f docker-compose.production.yml exec -T bitcoin-core \
    bitcoin-cli -rpcuser=blockchain_collector -rpcpassword=jEz5nDUgr1S4HUHZ0M3qqPDjIU2F6uhd \
    getblockchaininfo 2>/dev/null | grep -E '"(blocks|headers|size_on_disk|verificationprogress)"' | \
    while IFS=: read -r key value; do
        key=$(echo "$key" | tr -d ' "')
        value=$(echo "$value" | tr -d ', ')

        case "$key" in
            blocks) echo "Blocks: $value" ;;
            headers) echo "Headers: $value" ;;
            size_on_disk)
                size_gb=$(echo "scale=2; $value / 1024 / 1024 / 1024" | bc 2>/dev/null || awk "BEGIN {printf \"%.2f\", $value/1024/1024/1024}")
                echo "Disk Usage: ${size_gb} GB"
                ;;
            verificationprogress)
                progress=$(echo "scale=2; $value * 100" | bc 2>/dev/null || awk "BEGIN {printf \"%.2f\", $value*100}")
                echo "Progress: ${progress}%"
                ;;
        esac
    done

echo ""
echo "Last checked: $(date)"
