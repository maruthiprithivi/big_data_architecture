-- ========================================
-- Blockchain Data Ingestion Schema
-- ========================================

CREATE DATABASE IF NOT EXISTS blockchain_data;

USE blockchain_data;

-- Ethereum Blocks Table
CREATE TABLE IF NOT EXISTS ethereum_blocks (
    block_number UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    parent_hash String CODEC(ZSTD(3)),
    miner String CODEC(ZSTD(3)),
    difficulty UInt64 CODEC(Delta, ZSTD(3)),
    total_difficulty String CODEC(ZSTD(3)),
    size UInt32 CODEC(ZSTD(3)),
    gas_limit UInt64 CODEC(Delta, ZSTD(3)),
    gas_used UInt64 CODEC(Delta, ZSTD(3)),
    transaction_count UInt32 CODEC(ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'ethereum' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, block_number)
PARTITION BY toYYYYMM(timestamp);

-- Ethereum Transactions Table
CREATE TABLE IF NOT EXISTS ethereum_transactions (
    tx_hash String CODEC(ZSTD(3)),
    block_number UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    from_address String CODEC(ZSTD(3)),
    to_address String CODEC(ZSTD(3)),
    value String CODEC(ZSTD(3)),
    gas UInt64 CODEC(Delta, ZSTD(3)),
    gas_price String CODEC(ZSTD(3)),
    nonce UInt64 CODEC(Delta, ZSTD(3)),
    transaction_index UInt32 CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'ethereum' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, block_number, transaction_index)
PARTITION BY toYYYYMM(timestamp);

-- Bitcoin Blocks Table
CREATE TABLE IF NOT EXISTS bitcoin_blocks (
    block_height UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    previous_block_hash String CODEC(ZSTD(3)),
    merkle_root String CODEC(ZSTD(3)),
    difficulty UInt64 CODEC(Delta, ZSTD(3)),
    nonce UInt64 CODEC(ZSTD(3)),
    size UInt32 CODEC(ZSTD(3)),
    weight UInt32 CODEC(ZSTD(3)),
    transaction_count UInt32 CODEC(ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'bitcoin' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, block_height)
PARTITION BY toYYYYMM(timestamp);

-- Bitcoin Transactions Table
CREATE TABLE IF NOT EXISTS bitcoin_transactions (
    tx_hash String CODEC(ZSTD(3)),
    block_height UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    size UInt32 CODEC(ZSTD(3)),
    weight UInt32 CODEC(ZSTD(3)),
    fee UInt64 CODEC(Delta, ZSTD(3)),
    input_count UInt32 CODEC(ZSTD(3)),
    output_count UInt32 CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'bitcoin' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, block_height)
PARTITION BY toYYYYMM(timestamp);

-- Solana Blocks Table
CREATE TABLE IF NOT EXISTS solana_blocks (
    slot UInt64 CODEC(Delta, ZSTD(3)),
    block_height UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    parent_slot UInt64 CODEC(Delta, ZSTD(3)),
    previous_block_hash String CODEC(ZSTD(3)),
    transaction_count UInt32 CODEC(ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'solana' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, slot)
PARTITION BY toYYYYMM(timestamp);

-- Solana Transactions Table
CREATE TABLE IF NOT EXISTS solana_transactions (
    signature String CODEC(ZSTD(3)),
    slot UInt64 CODEC(Delta, ZSTD(3)),
    block_hash String CODEC(ZSTD(3)),
    fee UInt64 CODEC(Delta, ZSTD(3)),
    status String CODEC(ZSTD(3)),
    timestamp DateTime CODEC(Delta, ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3)),
    source String DEFAULT 'solana' CODEC(ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (timestamp, slot)
PARTITION BY toYYYYMM(timestamp);

-- Collection Metrics Table (for monitoring)
CREATE TABLE IF NOT EXISTS collection_metrics (
    metric_time DateTime CODEC(Delta, ZSTD(3)),
    source String CODEC(ZSTD(3)),
    records_collected UInt32 CODEC(ZSTD(3)),
    collection_duration_ms UInt32 CODEC(ZSTD(3)),
    error_count UInt32 CODEC(ZSTD(3)),
    error_message String CODEC(ZSTD(3)),
    collected_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3))
) ENGINE = MergeTree()
ORDER BY (metric_time, source)
PARTITION BY toYYYYMM(metric_time);

-- Collection State Table (for tracking collection status)
CREATE TABLE IF NOT EXISTS collection_state (
    id UInt8 DEFAULT 1 CODEC(ZSTD(3)),
    is_running Boolean CODEC(ZSTD(3)),
    started_at Nullable(DateTime) CODEC(Delta, ZSTD(3)),
    stopped_at Nullable(DateTime) CODEC(Delta, ZSTD(3)),
    total_records UInt64 CODEC(Delta, ZSTD(3)),
    total_size_bytes UInt64 CODEC(Delta, ZSTD(3)),
    updated_at DateTime DEFAULT now() CODEC(Delta, ZSTD(3))
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id;

-- Initialize collection state
INSERT INTO collection_state (id, is_running, total_records, total_size_bytes) 
VALUES (1, false, 0, 0);
