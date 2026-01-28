-- Enable Tiered Storage for ClickHouse Tables
-- This script applies tiered storage policy and TTL rules to move data older than 30 days to Backblaze

USE blockchain_data;

-- Bitcoin blocks table
ALTER TABLE bitcoin_blocks
    MODIFY SETTING storage_policy = 'tiered_storage';

ALTER TABLE bitcoin_blocks
    MODIFY TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold';

-- Bitcoin transactions table
ALTER TABLE bitcoin_transactions
    MODIFY SETTING storage_policy = 'tiered_storage';

ALTER TABLE bitcoin_transactions
    MODIFY TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold';

-- Solana blocks table
ALTER TABLE solana_blocks
    MODIFY SETTING storage_policy = 'tiered_storage';

ALTER TABLE solana_blocks
    MODIFY TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold';

-- Solana transactions table
ALTER TABLE solana_transactions
    MODIFY SETTING storage_policy = 'tiered_storage';

ALTER TABLE solana_transactions
    MODIFY TTL timestamp + INTERVAL 30 DAY TO VOLUME 'cold';

-- Verify tiered storage is applied
SELECT
    table,
    storage_policy,
    count() as parts
FROM system.parts
WHERE database = 'blockchain_data' AND active = 1
GROUP BY table, storage_policy
ORDER BY table;

-- Show disk distribution
SELECT
    disk_name,
    formatReadableSize(sum(bytes)) as total_size,
    count() as parts
FROM system.parts
WHERE database = 'blockchain_data' AND active = 1
GROUP BY disk_name;
