# Sample Queries for Blockchain Data Exploration

This document provides a comprehensive set of SQL queries for exploring and analyzing Bitcoin and Solana blockchain data collected in ClickHouse. These queries are designed to help students understand data analysis patterns and gain insights into blockchain activity.

## Table of Contents

1. [Basic Queries](#basic-queries)
2. [Aggregation Queries](#aggregation-queries)
3. [Time-Series Analysis](#time-series-analysis)
4. [Cross-Chain Comparisons](#cross-chain-comparisons)
5. [Advanced Analytics](#advanced-analytics)

---

## Basic Queries

### View Recent Bitcoin Blocks

```sql
SELECT 
    block_height,
    block_hash,
    timestamp,
    transaction_count,
    size,
    weight
FROM bitcoin_blocks
ORDER BY block_height DESC
LIMIT 10;
```

### Check Solana Transaction Status Distribution

```sql
SELECT 
    status,
    count() AS count
FROM solana_transactions
GROUP BY status;
```

---

## Aggregation Queries

### Bitcoin Transaction Fee Statistics

```sql
SELECT 
    min(fee) AS min_fee,
    max(fee) AS max_fee,
    avg(fee) AS avg_fee,
    median(fee) AS median_fee,
    sum(fee) AS total_fees
FROM bitcoin_transactions;
```

### Average Transactions Per Block by Blockchain

```sql
SELECT
    'Bitcoin' AS blockchain,
    avg(transaction_count) AS avg_tx_per_block
FROM bitcoin_blocks

UNION ALL

SELECT
    'Solana' AS blockchain,
    avg(transaction_count) AS avg_tx_per_block
FROM solana_blocks;
```

---

## Time-Series Analysis

### Bitcoin Transaction Volume by Day

```sql
SELECT 
    toDate(timestamp) AS day,
    count() AS transaction_count,
    sum(fee) AS total_fees,
    avg(fee) AS avg_fee
FROM bitcoin_transactions
GROUP BY day
ORDER BY day;
```

### Solana Success Rate Over Time

```sql
SELECT 
    toStartOfHour(timestamp) AS hour,
    countIf(status = 'success') AS successful,
    countIf(status = 'failed') AS failed,
    (countIf(status = 'success') * 100.0 / count()) AS success_rate_percent
FROM solana_transactions
GROUP BY hour
ORDER BY hour;
```

---

## Cross-Chain Comparisons

### Block Production Rate Comparison

```sql
WITH bitcoin_rate AS (
    SELECT
        'Bitcoin' AS chain,
        count() / (max(timestamp) - min(timestamp)) * 3600 AS blocks_per_hour
    FROM bitcoin_blocks
),
solana_rate AS (
    SELECT
        'Solana' AS chain,
        count() / (max(timestamp) - min(timestamp)) * 3600 AS blocks_per_hour
    FROM solana_blocks
)
SELECT * FROM bitcoin_rate
UNION ALL
SELECT * FROM solana_rate;
```

### Transaction Throughput Comparison

```sql
SELECT
    'Bitcoin' AS blockchain,
    count() AS total_transactions,
    count() / (max(timestamp) - min(timestamp)) AS tx_per_second
FROM bitcoin_transactions

UNION ALL

SELECT
    'Solana' AS blockchain,
    count() AS total_transactions,
    count() / (max(timestamp) - min(timestamp)) AS tx_per_second
FROM solana_transactions;
```

### Data Collection Performance by Source

```sql
SELECT 
    source,
    count() AS collection_events,
    sum(records_collected) AS total_records,
    avg(collection_duration_ms) AS avg_duration_ms,
    sum(error_count) AS total_errors,
    (sum(error_count) * 100.0 / count()) AS error_rate_percent
FROM collection_metrics
GROUP BY source
ORDER BY total_records DESC;
```

---

## Advanced Analytics

### Bitcoin Block Size Analysis

```sql
SELECT 
    toDate(timestamp) AS day,
    avg(size) AS avg_size_bytes,
    avg(weight) AS avg_weight,
    max(size) AS max_size_bytes,
    avg(transaction_count) AS avg_tx_count
FROM bitcoin_blocks
GROUP BY day
ORDER BY day;
```

### Solana Slot Time Distribution

```sql
SELECT 
    slot,
    timestamp,
    timestamp - lagInFrame(timestamp) OVER (ORDER BY slot) AS time_since_previous_slot
FROM solana_blocks
ORDER BY slot DESC
LIMIT 100;
```

### Calculate Total Data Volume by Table

```sql
SELECT 
    table,
    sum(rows) AS total_rows,
    formatReadableSize(sum(bytes)) AS uncompressed_size,
    formatReadableSize(sum(bytes_on_disk)) AS compressed_size,
    round((1 - sum(bytes_on_disk) / sum(bytes)) * 100, 2) AS compression_ratio_percent
FROM system.parts
WHERE database = 'blockchain_data' AND active = 1
GROUP BY table
ORDER BY sum(bytes) DESC;
```

### Collection Metrics Summary

```sql
SELECT 
    source,
    min(metric_time) AS first_collection,
    max(metric_time) AS last_collection,
    sum(records_collected) AS total_records,
    avg(collection_duration_ms) AS avg_duration_ms,
    sum(error_count) AS total_errors
FROM collection_metrics
GROUP BY source;
```

---

## Tips for Query Optimization

1. **Use Appropriate Time Ranges**: When querying large datasets, always filter by timestamp to reduce the amount of data scanned.

   ```sql
   WHERE timestamp >= now() - INTERVAL 1 HOUR
   ```

2. **Leverage Partitioning**: The tables are partitioned by month. Queries that filter by date will automatically benefit from partition pruning.

3. **Use PREWHERE for Filtering**: ClickHouse's `PREWHERE` clause can improve query performance by filtering data before reading all columns.

   ```sql
   SELECT * FROM bitcoin_blocks
   PREWHERE block_height > 800000
   WHERE transaction_count > 100;
   ```

4. **Aggregate Before Joining**: When joining tables, aggregate data first to reduce the size of intermediate results.

5. **Monitor Query Performance**: Use the `EXPLAIN` statement to understand query execution plans.

   ```sql
   EXPLAIN SELECT * FROM bitcoin_blocks WHERE block_height > 800000;
   ```

---

## Additional Resources

- [ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference/)
- [ClickHouse Query Optimization](https://clickhouse.com/docs/en/guides/improving-query-performance/)
- [ClickHouse Functions](https://clickhouse.com/docs/en/sql-reference/functions/)
