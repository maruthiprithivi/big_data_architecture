CREATE DATABASE IF NOT EXISTS campusstream;
CREATE TABLE IF NOT EXISTS campusstream.sessions
(
    session_id UInt64,
    title LowCardinality(String),
    watch_seconds UInt16,
    device LowCardinality(String),
    event_time DateTime,
    ingested_at DateTime
)
ENGINE = MergeTree ORDER BY (title, event_time);

INSERT INTO campusstream.sessions
SELECT number AS session_id,
    multiIf(number % 10 < 5, 'The Matrix', number % 10 < 8, 'Apollo 13',
        number % 10 = 8, 'Sleepless in Seattle', 'Cloud Atlas') AS title,
    if(intDiv(number, 10) % 10 < multiIf(number % 10 < 5, 2,
        number % 10 < 8, 8, number % 10 = 8, 6, 9), 1800, 60) AS watch_seconds,
    if(intDiv(number, 100) % 2 = 0, 'mobile', 'web') AS device,
    toDateTime('2026-10-10 12:00:00', 'UTC') + intDiv(number, 100000) * 86400 AS event_time,
    event_time + number % 37 AS ingested_at
FROM numbers(1000000);

CREATE USER IF NOT EXISTS lab_reader IDENTIFIED WITH no_password
SETTINGS readonly = 1, max_execution_time = 5, max_memory_usage = 268435456,
    max_threads = 2, max_result_rows = 100, result_overflow_mode = 'throw';
GRANT SELECT ON campusstream.sessions TO lab_reader;
