"""
Blockchain Data Collector Service
Collects data from Ethereum, Bitcoin, and Solana blockchains via RPC

=== EDUCATIONAL OVERVIEW ===

This is the central orchestration service that coordinates data collection from
multiple blockchains. It demonstrates several key software engineering patterns:

1. FastAPI Framework: Modern Python web framework for building APIs
   - Async/await support for non-blocking I/O
   - Automatic OpenAPI/Swagger documentation at /docs
   - Type hints and validation with Pydantic
   - Dependency injection for clean code organization

2. Concurrent Data Collection: Uses asyncio.gather() to collect from all
   blockchains simultaneously, maximizing throughput while waiting for I/O.

3. State Management: Tracks collection status in ClickHouse for persistence
   across restarts and visibility from the dashboard.

4. Safety Limits: Prevents runaway data collection with time and size limits.
   This is crucial in educational environments to prevent unexpected costs.

Architecture Pattern:
This service acts as an ETL (Extract, Transform, Load) pipeline where:
- Extract: Pull data from blockchain RPC endpoints
- Transform: Convert blockchain-specific formats to our unified schema
- Load: Insert into ClickHouse for analysis

The service exposes a REST API for control (start/stop) and monitoring (status).
"""

import asyncio
import os
from datetime import datetime, timedelta
from typing import Optional
import logging

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import clickhouse_connect
from dotenv import load_dotenv

from collectors.ethereum_collector import EthereumCollector
from collectors.bitcoin_collector import BitcoinCollector
from collectors.solana_collector import SolanaCollector

# EDUCATIONAL NOTE - Logging Configuration:
# Structured logging is essential for debugging and monitoring data pipelines.
# The format includes timestamp, logger name, level, and message for traceability.
# In production, you'd typically send logs to a centralized system (ELK, CloudWatch).
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()

# EDUCATIONAL NOTE - FastAPI Application:
# FastAPI automatically generates interactive API documentation at /docs (Swagger UI)
# and /redoc (ReDoc). This is invaluable for API testing and documentation.
app = FastAPI(title="Blockchain Data Collector")

# EDUCATIONAL NOTE - Global State:
# We use global variables here for simplicity. In production, consider:
# - State management libraries (e.g., Redis for distributed state)
# - Dependency injection patterns
# - Proper shutdown handling with signals
collection_task: Optional[asyncio.Task] = None
is_collecting = False


def get_clickhouse_client():
    """
    Create a ClickHouse client connection.

    EDUCATIONAL NOTE - Why ClickHouse?
    ClickHouse is a columnar OLAP (Online Analytical Processing) database,
    designed for:
    - Fast analytical queries on large datasets (millions to billions of rows)
    - Excellent compression (often 10-20x for blockchain data)
    - Real-time data insertion with eventual consistency
    - SQL interface familiar to most developers

    Columnar vs Row Storage:
    - Row storage (PostgreSQL, MySQL): Stores all columns of a row together
      Good for: Fetching entire rows, UPDATE/DELETE operations, OLTP workloads
    - Columnar storage (ClickHouse): Stores each column separately
      Good for: Aggregate queries, compression, scanning specific columns

    For blockchain analytics, we often query aggregates across millions of
    transactions (e.g., total gas used, average fee), making columnar ideal.

    The HTTP interface (port 8123) is used for queries; native interface (9000)
    exists for faster bulk operations.
    """
    return clickhouse_connect.get_client(
        host=os.getenv('CLICKHOUSE_HOST', 'clickhouse'),
        port=int(os.getenv('CLICKHOUSE_PORT', 8123)),
        username=os.getenv('CLICKHOUSE_USER', 'default'),
        password=os.getenv('CLICKHOUSE_PASSWORD', ''),
        database=os.getenv('CLICKHOUSE_DB', 'blockchain_data')
    )


# EDUCATIONAL NOTE - Collector Initialization:
# Each collector is configured via environment variables, allowing:
# - Different RPC endpoints for different environments (dev, staging, prod)
# - Easy enabling/disabling of specific blockchains
# - No code changes needed to modify behavior
#
# Environment variables are loaded from .env file by python-dotenv,
# making local development easy while supporting containerized deployments.
ethereum_collector = EthereumCollector(
    rpc_url=os.getenv('ETHEREUM_RPC_URL'),
    enabled=os.getenv('ETHEREUM_ENABLED', 'true').lower() == 'true'
)

bitcoin_collector = BitcoinCollector(
    rpc_url=os.getenv('BITCOIN_RPC_URL'),
    enabled=os.getenv('BITCOIN_ENABLED', 'true').lower() == 'true'
)

solana_collector = SolanaCollector(
    rpc_url=os.getenv('SOLANA_RPC_URL'),
    enabled=os.getenv('SOLANA_ENABLED', 'true').lower() == 'true'
)


async def check_safety_limits(client) -> tuple[bool, str]:
    """
    Check if safety limits have been exceeded.

    EDUCATIONAL NOTE - Safety Limits:
    In educational and development environments, it's crucial to prevent:
    - Runaway processes that collect data indefinitely
    - Unexpected cloud storage costs (ClickHouse data persists to disk)
    - API rate limit violations from excessive requests

    We implement two safety checks:
    1. Time limit: Stop after MAX_COLLECTION_TIME_MINUTES
    2. Size limit: Stop when data exceeds MAX_DATA_SIZE_GB

    This is a common pattern in data pipelines called "circuit breaker" or
    "dead man's switch" - automatic shutdown if something goes wrong.

    Returns:
        Tuple of (within_limits: bool, reason: str)
        If within_limits is False, reason explains why
    """
    try:
        # Get collection state from database
        result = client.query("SELECT started_at, total_records, total_size_bytes FROM collection_state WHERE id = 1")
        if not result.result_rows:
            return True, ""

        started_at, total_records, total_size_bytes = result.result_rows[0]

        # Check time limit
        max_time = int(os.getenv('MAX_COLLECTION_TIME_MINUTES', 10))
        if started_at:
            elapsed = datetime.now() - started_at
            if elapsed > timedelta(minutes=max_time):
                return False, f"Time limit exceeded ({max_time} minutes)"

        # Check data size limit
        max_size_gb = float(os.getenv('MAX_DATA_SIZE_GB', 5))
        size_gb = total_size_bytes / (1024**3)
        if size_gb >= max_size_gb:
            return False, f"Data size limit exceeded ({max_size_gb} GB)"

        return True, ""
    except Exception as e:
        logger.error(f"Error checking safety limits: {e}")
        return True, ""  # Fail open - continue if we can't check


async def collect_data():
    """
    Main data collection loop.

    EDUCATIONAL NOTE - Event Loop Pattern:
    This is a classic "poll and collect" pattern common in data engineering:
    1. Sleep for an interval
    2. Check for new data from each source
    3. Insert into destination
    4. Repeat

    Alternatives for production:
    - Push-based: Use WebSocket subscriptions for real-time updates
    - Change Data Capture (CDC): Replicate data as it changes
    - Event streaming: Use Kafka/Pulsar for reliable data pipelines
    """
    global is_collecting

    client = get_clickhouse_client()
    interval = int(os.getenv('COLLECTION_INTERVAL_SECONDS', 5))

    logger.info("Starting data collection...")

    # EDUCATIONAL NOTE - Collection State:
    # We track state in the database (not just memory) so that:
    # 1. The dashboard can query current status
    # 2. State persists across service restarts
    # 3. Multiple instances could potentially coordinate (not implemented here)
    client.command("""
        INSERT INTO collection_state (id, is_running, started_at, total_records, total_size_bytes, updated_at)
        VALUES (1, true, now(), 0, 0, now())
    """)

    try:
        while is_collecting:
            # Check safety limits before each collection cycle
            within_limits, reason = await check_safety_limits(client)
            if not within_limits:
                logger.warning(f"Safety limit reached: {reason}. Stopping collection.")
                is_collecting = False
                break

            # EDUCATIONAL NOTE - Concurrent vs Parallel Execution:
            #
            # asyncio.gather() runs coroutines CONCURRENTLY, not in parallel.
            # - Concurrent: Multiple tasks make progress by switching during I/O waits
            # - Parallel: Multiple tasks run simultaneously on different CPU cores
            #
            # Since our collectors spend most time waiting for HTTP responses (I/O-bound),
            # concurrency is highly effective. While waiting for Ethereum RPC response,
            # Python can send requests to Bitcoin and Solana APIs.
            #
            # For CPU-bound work, you'd need multiprocessing for true parallelism
            # due to Python's Global Interpreter Lock (GIL).
            tasks = []

            if ethereum_collector.enabled:
                tasks.append(ethereum_collector.collect(client))

            if bitcoin_collector.enabled:
                tasks.append(bitcoin_collector.collect(client))

            if solana_collector.enabled:
                tasks.append(solana_collector.collect(client))

            # return_exceptions=True prevents one collector's error from crashing others
            # Errors are returned as exception objects in the results list
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)

            # EDUCATIONAL NOTE - UNION ALL for Multi-Table Counting:
            # We use UNION ALL to combine counts from all tables in a single query.
            # This is more efficient than running 6 separate queries.
            #
            # UNION vs UNION ALL:
            # - UNION: Removes duplicate rows (slower, requires sorting)
            # - UNION ALL: Keeps all rows including duplicates (faster)
            #
            # Since we're counting distinct tables, duplicates are impossible,
            # so UNION ALL is the correct and faster choice.
            try:
                total_records = client.query("""
                    SELECT
                        sum(cnt) as total
                    FROM (
                        SELECT count() as cnt FROM ethereum_blocks
                        UNION ALL
                        SELECT count() as cnt FROM ethereum_transactions
                        UNION ALL
                        SELECT count() as cnt FROM bitcoin_blocks
                        UNION ALL
                        SELECT count() as cnt FROM bitcoin_transactions
                        UNION ALL
                        SELECT count() as cnt FROM solana_blocks
                        UNION ALL
                        SELECT count() as cnt FROM solana_transactions
                    )
                """).result_rows[0][0]

                # EDUCATIONAL NOTE - ClickHouse System Tables:
                # ClickHouse exposes metadata through system.* tables:
                # - system.parts: Information about data parts (storage units)
                # - system.tables: Table metadata
                # - system.columns: Column information
                # - system.query_log: Query execution history
                #
                # 'active = 1' filters for current parts (excluding merged/deleted ones).
                # This query gives us actual disk usage including compression.
                total_size = client.query("""
                    SELECT sum(bytes) as total_bytes
                    FROM system.parts
                    WHERE database = 'blockchain_data'
                    AND active = 1
                """).result_rows[0][0] or 0

                # Update state with current totals
                client.command(f"""
                    INSERT INTO collection_state (id, is_running, total_records, total_size_bytes, updated_at)
                    VALUES (1, true, {total_records}, {total_size}, now())
                """)
            except Exception as e:
                logger.error(f"Error updating totals: {e}")

            # Sleep before next collection cycle
            await asyncio.sleep(interval)

    except Exception as e:
        logger.error(f"Error in collection loop: {e}")
    finally:
        # Always update state to stopped when exiting, regardless of how we exit
        client.command("""
            INSERT INTO collection_state (id, is_running, stopped_at, updated_at)
            VALUES (1, false, now(), now())
        """)
        logger.info("Data collection stopped")


# =============================================================================
# API ENDPOINTS
# =============================================================================

# EDUCATIONAL NOTE - REST API Design:
# Our API follows RESTful conventions:
# - GET for retrieving data (/, /status, /health)
# - POST for actions that change state (/start, /stop)
#
# FastAPI automatically validates request/response types and generates
# OpenAPI documentation. Visit http://localhost:8000/docs to see it!


@app.get("/")
async def root():
    """Root endpoint - returns API information."""
    return {"status": "Blockchain Data Collector API", "version": "1.0"}


@app.post("/start")
async def start_collection():
    """
    Start data collection.

    EDUCATIONAL NOTE - Background Tasks:
    asyncio.create_task() schedules the coroutine to run in the background.
    The HTTP response returns immediately while collection continues.

    This is different from 'await collect_data()' which would block the
    response until collection finished (which is never, as it's a loop).
    """
    global collection_task, is_collecting

    if is_collecting:
        raise HTTPException(status_code=400, detail="Collection already running")

    is_collecting = True
    collection_task = asyncio.create_task(collect_data())

    return JSONResponse({"status": "started", "message": "Data collection started"})


@app.post("/stop")
async def stop_collection():
    """
    Stop data collection.

    EDUCATIONAL NOTE - Graceful Shutdown:
    We set is_collecting to False, which causes the collection loop to exit
    on its next iteration. Then we 'await' the task to ensure it completes
    cleanly before returning. This is important for:
    - Flushing any pending database writes
    - Updating the collection state to "stopped"
    - Releasing resources properly
    """
    global collection_task, is_collecting

    if not is_collecting:
        raise HTTPException(status_code=400, detail="Collection not running")

    is_collecting = False

    if collection_task:
        await collection_task
        collection_task = None

    return JSONResponse({"status": "stopped", "message": "Data collection stopped"})


@app.get("/status")
async def get_status():
    """
    Get current collection status.

    Returns information about whether collection is running, when it started/stopped,
    and totals for records and data size.
    """
    client = get_clickhouse_client()

    try:
        result = client.query("""
            SELECT is_running, started_at, stopped_at, total_records, total_size_bytes
            FROM collection_state
            WHERE id = 1
            ORDER BY updated_at DESC
            LIMIT 1
        """)

        if result.result_rows:
            row = result.result_rows[0]
            return {
                "is_running": bool(row[0]),
                "started_at": str(row[1]) if row[1] else None,
                "stopped_at": str(row[2]) if row[2] else None,
                "total_records": row[3],
                "total_size_bytes": row[4]
            }

        return {"is_running": False}
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """
    Health check endpoint for container orchestration.

    EDUCATIONAL NOTE - Health Checks:
    Health endpoints are used by Docker, Kubernetes, and load balancers to:
    - Determine if the service is ready to receive traffic
    - Restart unhealthy containers automatically
    - Remove unhealthy instances from load balancer pools

    We check ClickHouse connectivity as it's a critical dependency.
    """
    try:
        client = get_clickhouse_client()
        client.query("SELECT 1")
        return {"status": "healthy", "clickhouse": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}
