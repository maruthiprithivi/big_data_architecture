-- ========================================
-- Blockchain Data Ingestion Schema
-- ========================================

CREATE DATABASE IF NOT EXISTS blockchain_data;

USE blockchain_data;

-- Ethereum Blocks Table
CREATE TABLE IF NOT EXISTS ethereum_blocks (
    block_number UInt64,
    block_hash String,
    timestamp DateTime,
    parent_hash String,
    miner String,
    difficulty UInt64,
    total_difficulty String,
    size UInt32,
    gas_limit UInt64,
    gas_used UInt64,
    transaction_count UInt32,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'ethereum'
) ENGINE = MergeTree()
ORDER BY (timestamp, block_number)
PARTITION BY toYYYYMM(timestamp);

-- Ethereum Transactions Table
CREATE TABLE IF NOT EXISTS ethereum_transactions (
    tx_hash String,
    block_number UInt64,
    block_hash String,
    from_address String,
    to_address String,
    value String,
    gas UInt64,
    gas_price String,
    nonce UInt64,
    transaction_index UInt32,
    timestamp DateTime,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'ethereum'
) ENGINE = MergeTree()
ORDER BY (timestamp, block_number, transaction_index)
PARTITION BY toYYYYMM(timestamp);

-- Bitcoin Blocks Table
CREATE TABLE IF NOT EXISTS bitcoin_blocks (
    block_height UInt64,
    block_hash String,
    timestamp DateTime,
    previous_block_hash String,
    merkle_root String,
    difficulty UInt64,
    nonce UInt64,
    size UInt32,
    weight UInt32,
    transaction_count UInt32,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'bitcoin'
) ENGINE = MergeTree()
ORDER BY (timestamp, block_height)
PARTITION BY toYYYYMM(timestamp);

-- Bitcoin Transactions Table
CREATE TABLE IF NOT EXISTS bitcoin_transactions (
    tx_hash String,
    block_height UInt64,
    block_hash String,
    size UInt32,
    weight UInt32,
    fee UInt64,
    input_count UInt32,
    output_count UInt32,
    timestamp DateTime,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'bitcoin'
) ENGINE = MergeTree()
ORDER BY (timestamp, block_height)
PARTITION BY toYYYYMM(timestamp);

-- Solana Blocks Table
CREATE TABLE IF NOT EXISTS solana_blocks (
    slot UInt64,
    block_height UInt64,
    block_hash String,
    timestamp DateTime,
    parent_slot UInt64,
    previous_block_hash String,
    transaction_count UInt32,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'solana'
) ENGINE = MergeTree()
ORDER BY (timestamp, slot)
PARTITION BY toYYYYMM(timestamp);

-- Solana Transactions Table
CREATE TABLE IF NOT EXISTS solana_transactions (
    signature String,
    slot UInt64,
    block_hash String,
    fee UInt64,
    status String,
    timestamp DateTime,
    collected_at DateTime DEFAULT now(),
    source String DEFAULT 'solana'
) ENGINE = MergeTree()
ORDER BY (timestamp, slot)
PARTITION BY toYYYYMM(timestamp);

-- Collection Metrics Table (for monitoring)
CREATE TABLE IF NOT EXISTS collection_metrics (
    metric_time DateTime,
    source String,
    records_collected UInt32,
    collection_duration_ms UInt32,
    error_count UInt32,
    error_message String,
    collected_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (metric_time, source)
PARTITION BY toYYYYMM(metric_time);

-- Collection State Table (for tracking collection status)
CREATE TABLE IF NOT EXISTS collection_state (
    id UInt8 DEFAULT 1,
    is_running Boolean,
    started_at Nullable(DateTime),
    stopped_at Nullable(DateTime),
    total_records UInt64,
    total_size_bytes UInt64,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id;

-- Initialize collection state
INSERT INTO collection_state (id, is_running, total_records, total_size_bytes) 
VALUES (1, false, 0, 0);
