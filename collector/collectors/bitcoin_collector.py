"""
Bitcoin Blockchain Data Collector
Collects blocks and transactions from Bitcoin via Blockstream API

=== 5Vs OF BIG DATA IN THIS MODULE ===

This collector demonstrates multiple Vs of big data:

VOLUME:   Bitcoin's blockchain is ~500GB+ and growing. Each block contains thousands
          of transactions. We sample 25 transactions per block for educational purposes,
          but production systems process all data.

VELOCITY: Bitcoin produces ~1 block every 10 minutes - relatively slow compared to
          Solana (~2.5 blocks/second). This affects our collection strategy and
          how often we poll for new data.

VARIETY:  Bitcoin uses the UTXO (Unspent Transaction Output) model - fundamentally
          different from Ethereum's account model. This collector transforms Bitcoin's
          unique data structure into our unified schema.

VERACITY: We validate block hashes, check timestamps, verify transaction counts,
          and detect anomalies. See DataValidator integration below.

VALUE:    The collected data enables analysis of transaction fees, network congestion,
          mining difficulty trends, and UTXO patterns.

=== EDUCATIONAL OVERVIEW ===

Bitcoin uses the UTXO (Unspent Transaction Output) model, fundamentally different
from Ethereum's account model. Instead of balances, Bitcoin tracks individual
"coins" (UTXOs) that can be spent by their owners.

Key Concepts Demonstrated:
- REST API interaction (Blockstream's Esplora API)
- UTXO model: inputs consume previous outputs, outputs create new UTXOs
- Proof-of-Work consensus: nonce and difficulty
- Block structure: Merkle trees for transaction verification
- Transaction fees in Satoshis (1 BTC = 100,000,000 Satoshis)

Why Blockstream API instead of direct RPC?
Bitcoin Core's JSON-RPC requires running a full node (~500GB+ of blockchain data).
Public APIs like Blockstream's Esplora provide indexed, queryable blockchain data
without running infrastructure. Trade-off: you trust the API provider vs. verifying
the data yourself with your own node.

UTXO Model Explained:
Think of UTXOs like physical coins. When you spend a $10 bill to buy something for $7,
you don't "update your balance" - you destroy the $10 bill and create a $7 item and
$3 change. Similarly, Bitcoin transactions consume existing UTXOs (inputs) and create
new UTXOs (outputs).
"""

import logging
from datetime import datetime
import aiohttp
import asyncio
import os

from .data_validator import DataValidator, log_quality_issue

logger = logging.getLogger(__name__)


class BitcoinCollector:
    """
    Collects block and transaction data from the Bitcoin blockchain.

    Bitcoin was the first cryptocurrency (2009) and uses Proof-of-Work consensus
    where miners compete to find a valid block hash by adjusting the nonce.
    """

    def __init__(self, rpc_url: str, enabled: bool = True):
        """
        Initialize the Bitcoin collector.

        EDUCATIONAL NOTE - Hybrid Architecture:
        This collector supports both Bitcoin Core RPC (local full node) and
        public APIs (Blockstream Esplora). The hybrid approach provides:
        - Resilience: Fallback to public API during node maintenance
        - Complete data: Local node access for historical backfill
        - Smooth transition: No downtime when switching sources

        Args:
            rpc_url: Base URL for the Blockstream API (e.g., https://blockstream.info/api)
            enabled: Whether this collector should run
        """
        self.rpc_url = rpc_url
        self.enabled = enabled

        # Dual-source configuration
        self.use_local_node = os.getenv('BITCOIN_USE_LOCAL_NODE', 'false').lower() == 'true'
        self.local_node_url = os.getenv('BITCOIN_CORE_RPC_URL', 'http://bitcoin-core:8332')
        self.rpc_user = os.getenv('BITCOIN_CORE_RPC_USER', '')
        self.rpc_password = os.getenv('BITCOIN_CORE_RPC_PASSWORD', '')
        self.public_api_url = os.getenv('BITCOIN_PUBLIC_API_URL', 'https://blockstream.info/api')

        # Track last processed block to collect sequentially
        self.last_block_height = None
        # Retry and backoff state for resilient API calls
        self.retry_delay = 1  # Start with 1 second
        self.max_retry_delay = 300  # Max 5 minutes
        self.last_successful_collect = None
        self.rate_limited = False  # Track if we're currently rate limited
        self.last_api_call = None  # Track last API call time for rate limiting
        # Initialize data validator for quality checks
        self.validator = DataValidator()

    async def _call_rpc(self, session, method: str, params: list = []):
        """
        Call Bitcoin Core RPC.

        EDUCATIONAL NOTE - Bitcoin Core JSON-RPC:
        Bitcoin Core provides a JSON-RPC interface for querying blockchain data.
        This is more efficient than public APIs and doesn't have rate limits.

        Args:
            session: aiohttp ClientSession
            method: RPC method name (e.g., 'getblockhash', 'getblock')
            params: List of parameters for the method

        Returns:
            RPC result

        Raises:
            Exception: On RPC error or connection failure
        """
        payload = {
            "jsonrpc": "2.0",
            "id": "collector",
            "method": method,
            "params": params
        }

        try:
            auth = aiohttp.BasicAuth(self.rpc_user, self.rpc_password)
            timeout = aiohttp.ClientTimeout(total=120)
            async with session.post(
                self.local_node_url,
                json=payload,
                auth=auth,
                timeout=timeout
            ) as resp:
                result = await resp.json()

                if 'error' in result and result['error']:
                    raise Exception(f"RPC error: {result['error']}")

                return result.get('result')

        except Exception as e:
            logger.warning(f"Bitcoin Core RPC call failed ({method}): {e}")
            raise

    async def _fetch_block_from_local_node(self, session, block_height: int):
        """
        Fetch block data from local Bitcoin Core node.

        Args:
            session: aiohttp ClientSession
            block_height: Block height to fetch

        Returns:
            Block data dict or None on failure
        """
        for attempt in range(3):
            try:
                # Get block hash for this height
                block_hash = await self._call_rpc(session, 'getblockhash', [block_height])

                # Get block with verbosity=2 (includes full transaction details)
                block = await self._call_rpc(session, 'getblock', [block_hash, 2])

                return block

            except Exception as e:
                if attempt < 2:
                    await asyncio.sleep(2 ** attempt)
                    continue
                logger.warning(f"Local node failed for block {block_height} after 3 attempts: {e}")
                return None

    async def _fetch_block_from_public_api(self, session, block_height: int):
        """
        Fetch block data from public API (Blockstream).

        Args:
            session: aiohttp ClientSession
            block_height: Block height to fetch

        Returns:
            Block data dict or None on failure
        """
        try:
            # Get block hash for this height
            block_hash = await self._api_call_with_retry(
                session, f"{self.public_api_url}/block-height/{block_height}", return_type='text'
            )
            if block_hash is None:
                return None

            # Get block data
            block = await self._api_call_with_retry(
                session, f"{self.public_api_url}/block/{block_hash}", return_type='json'
            )
            if block is None:
                return None

            # Get transaction IDs
            block['tx'] = await self._api_call_with_retry(
                session, f"{self.public_api_url}/block/{block_hash}/txids", return_type='json'
            )
            if block['tx'] is None:
                return None

            return block

        except Exception as e:
            logger.warning(f"Public API failed for block {block_height}: {e}")
            return None

    async def _api_call_with_retry(self, session, url, max_retries=3, return_type='json'):
        """
        Make API call with exponential backoff for rate limits and transient failures.

        EDUCATIONAL NOTE - Resilient API Calls:
        Public APIs can fail for many reasons: rate limits, network issues, temporary
        outages. Exponential backoff (1s, 2s, 4s, 8s...) prevents overwhelming the
        server while allowing recovery from transient failures.

        Args:
            session: aiohttp ClientSession
            url: Full URL to fetch
            max_retries: Maximum number of retry attempts
            return_type: 'json' or 'text' for response parsing

        Returns:
            Parsed response (dict/list for JSON, str for text)

        Raises:
            Exception: After all retries exhausted
        """
        # Add minimum delay between API calls to be respectful (0.5 seconds)
        if self.last_api_call:
            time_since_last = (datetime.now() - self.last_api_call).total_seconds()
            if time_since_last < 0.5:
                await asyncio.sleep(0.5 - time_since_last)

        # If we're rate limited, wait longer before trying
        if self.rate_limited:
            await asyncio.sleep(self.retry_delay)

        for attempt in range(max_retries):
            try:
                self.last_api_call = datetime.now()
                timeout = aiohttp.ClientTimeout(total=15)
                async with session.get(url, timeout=timeout) as resp:
                    # Check for rate limiting
                    if resp.status == 429:
                        self.rate_limited = True
                        retry_after = int(resp.headers.get('Retry-After', self.retry_delay))
                        logger.warning(f"Rate limited by Blockstream API, waiting {retry_after}s (attempt {attempt + 1}/{max_retries})")
                        await asyncio.sleep(retry_after)
                        self.retry_delay = min(self.retry_delay * 2, self.max_retry_delay)
                        continue

                    # Check for "block not found" (404) - not an error, just no new block yet
                    if resp.status == 404:
                        logger.info("Bitcoin block not found - waiting for next block to be mined")
                        return None

                    # Check for other HTTP errors
                    if resp.status >= 400:
                        error_text = await resp.text()
                        logger.warning(f"HTTP {resp.status} error on {url}: {error_text[:100]}")
                        if attempt < max_retries - 1:
                            await asyncio.sleep(2 ** attempt)
                            continue
                        else:
                            raise Exception(f"HTTP {resp.status}: {error_text[:100]}")

                    # Success - parse response and reset rate limit tracking
                    self.rate_limited = False
                    self.retry_delay = max(1, self.retry_delay // 2)  # Reduce delay on success

                    if return_type == 'json':
                        return await resp.json()
                    else:
                        return await resp.text()

            except asyncio.TimeoutError:
                logger.warning(f"Timeout on {url}, attempt {attempt + 1}/{max_retries}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(2 ** attempt)
            except aiohttp.ClientError as e:
                logger.warning(f"Connection error on {url}: {e}, attempt {attempt + 1}/{max_retries}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(2 ** attempt)

        raise Exception(f"Failed to fetch {url} after {max_retries} attempts")

    async def collect_block(self, session, client, block_height):
        """
        Collect a single Bitcoin block and its transactions.

        EDUCATIONAL NOTE - Dual-Source Collection:
        This method tries the local Bitcoin Core node first (if enabled), then
        falls back to the public API if the local node is unavailable. This
        provides resilience during node maintenance or sync.

        Args:
            session: aiohttp ClientSession
            client: ClickHouse database client
            block_height: Block height to collect

        Returns:
            Number of records collected (0 on failure)
        """
        records_collected = 0
        try:
            block = None
            all_tx_ids = None

            # Try local node first if enabled
            if self.use_local_node:
                block = await self._fetch_block_from_local_node(session, block_height)

            # Fallback to public API if local node failed or not enabled
            if block is None:
                if self.use_local_node:
                    logger.info(f"Using public API fallback for block {block_height}")
                block = await self._fetch_block_from_public_api(session, block_height)

            if block is None:
                return 0

            # Extract transaction data based on source
            local_tx_map = {}
            if 'tx' in block and isinstance(block['tx'], list):
                # From local node (full tx objects) or public API (tx IDs)
                if len(block['tx']) > 0 and isinstance(block['tx'][0], dict):
                    # Local node format: full transaction objects already available
                    all_tx_ids = [tx['txid'] for tx in block['tx']]
                    local_tx_map = {tx['txid']: tx for tx in block['tx']}
                else:
                    # Public API format: transaction IDs
                    all_tx_ids = block['tx']
            else:
                all_tx_ids = []

            # Limit transactions based on configuration
            tx_limit = int(os.getenv('BITCOIN_TX_LIMIT', '100'))
            tx_ids = all_tx_ids if tx_limit == 0 else all_tx_ids[:tx_limit]

            # Prepare block data (handle both API formats)
            block_data = {
                'block_height': block_height,
                'block_hash': block.get('id') or block.get('hash'),
                'timestamp': datetime.fromtimestamp(block['timestamp'] if 'timestamp' in block else block['time']),
                'previous_block_hash': block['previousblockhash'],
                'merkle_root': block.get('merkle_root') or block.get('merkleroot'),
                'difficulty': int(block['difficulty']),
                'nonce': block['nonce'],
                'size': block['size'],
                'weight': block.get('weight', block.get('strippedsize', 0) * 3 + block['size']),
                'transaction_count': block.get('tx_count') or block.get('nTx') or len(all_tx_ids)
            }

            # Validate block
            block_validation = self.validator.validate_bitcoin_block(block_data)
            if not block_validation.is_valid:
                logger.warning(
                    f"[VERACITY] Bitcoin block {block_height} has quality issues: "
                    f"{block_validation.issues}"
                )
                log_quality_issue(
                    source='bitcoin',
                    record_type='block',
                    record_id=str(block_height),
                    result=block_validation,
                    client=client
                )

            # Insert block
            columns = ['block_height', 'block_hash', 'timestamp', 'previous_block_hash',
                     'merkle_root', 'difficulty', 'nonce', 'size', 'weight', 'transaction_count']
            block_values = [[block_data[col] for col in columns]]
            client.insert('bitcoin_blocks', block_values, column_names=columns)
            records_collected += 1

            # Collect transactions
            tx_data = []
            for tx_id in tx_ids:
                try:
                    # Use cached tx data from block response if available (local node verbosity=2)
                    tx = local_tx_map.get(tx_id)

                    # Only fetch individually if not in cache (public API blocks don't include tx details)
                    if tx is None:
                        if self.use_local_node:
                            try:
                                tx = await self._call_rpc(session, 'getrawtransaction', [tx_id, True])
                            except Exception as e:
                                logger.debug(f"Local RPC failed for tx {tx_id}: {e}")

                        # Fallback to public API only if local node unavailable
                        if tx is None:
                            tx = await self._api_call_with_retry(
                                session, f"{self.public_api_url}/tx/{tx_id}", return_type='json'
                            )

                    if tx is None:
                        continue

                    # Handle different formats
                    tx_record = {
                        'tx_hash': tx['txid'],
                        'block_height': block_height,
                        'block_hash': block_data['block_hash'],
                        'size': tx.get('size', tx.get('vsize', 0)),
                        'weight': tx.get('weight', tx.get('vsize', 0) * 4),
                        'fee': int(tx.get('fee', 0) * 100000000 if isinstance(tx.get('fee'), float) else tx.get('fee', 0)),
                        'input_count': len(tx['vin']),
                        'output_count': len(tx['vout']),
                        'timestamp': block_data['timestamp']
                    }

                    tx_validation = self.validator.validate_bitcoin_transaction(tx_record)
                    if not tx_validation.is_valid:
                        logger.debug(
                            f"[VERACITY] Bitcoin tx {tx['txid'][:16]}... has issues: "
                            f"{tx_validation.issues}"
                        )

                    tx_data.append(tx_record)
                except Exception as e:
                    logger.warning(f"Error collecting Bitcoin tx {tx_id}: {e}")
                    continue

            if tx_data:
                columns = ['tx_hash', 'block_height', 'block_hash', 'size',
                         'weight', 'fee', 'input_count', 'output_count', 'timestamp']
                tx_values = [[tx[col] for col in columns] for tx in tx_data]
                client.insert('bitcoin_transactions', tx_values, column_names=columns)
                records_collected += len(tx_data)

            logger.info(f"Collected Bitcoin block {block_height} with {len(tx_data)} transactions")
            return records_collected

        except Exception as e:
            logger.error(f"Error collecting Bitcoin block {block_height}: {e}")
            return 0

    async def _save_position(self, client, height):
        """Save current collection position to ClickHouse for resume on restart."""
        try:
            client.command(
                f"INSERT INTO collector_positions (collector, last_position) "
                f"VALUES ('bitcoin', {height})"
            )
        except Exception as e:
            logger.warning(f"Failed to save Bitcoin position: {e}")

    async def _load_position(self, client):
        """Load last collection position from ClickHouse."""
        try:
            result = client.query(
                "SELECT last_position FROM collector_positions FINAL "
                "WHERE collector = 'bitcoin'"
            )
            if result.result_rows:
                return int(result.result_rows[0][0])
        except Exception as e:
            logger.warning(f"Failed to load Bitcoin position: {e}")
        return None

    async def collect(self, client):
        """
        Collect the next Bitcoin block and its transactions.

        EDUCATIONAL NOTE - Bitcoin Block Time:
        Bitcoin targets a 10-minute average block time, achieved through difficulty
        adjustments every 2016 blocks (~2 weeks). This is much slower than Ethereum's
        12 seconds, but Bitcoin prioritizes security and decentralization over speed.

        Args:
            client: ClickHouse database client for inserting collected data
        """
        if not self.enabled:
            return

        start_time = datetime.now()
        records_collected = 0
        error_msg = ""

        try:
            # EDUCATIONAL NOTE - aiohttp for Async HTTP:
            # We use aiohttp (async HTTP client) instead of requests (sync) to enable
            # concurrent API calls. This is important when collecting from multiple
            # blockchains simultaneously - we don't want to block while waiting for
            # one API response.
            async with aiohttp.ClientSession() as session:
                # Get the current blockchain height (number of blocks)
                latest_height = None
                if self.use_local_node:
                    try:
                        result = await self._call_rpc(session, 'getblockcount')
                        if result is not None:
                            latest_height = int(result)
                    except Exception as e:
                        logger.warning(f"Failed to get block count from local node: {e}")

                if latest_height is None:
                    latest_height_str = await self._api_call_with_retry(
                        session, f"{self.rpc_url}/blocks/tip/height", return_type='text'
                    )
                    if latest_height_str is None:
                        return  # API temporarily unavailable
                    latest_height = int(latest_height_str)

                # If first run, try to resume from saved position, then fall back
                # to env var configuration
                if self.last_block_height is None:
                    saved = await self._load_position(client)
                    if saved is not None:
                        self.last_block_height = saved
                        logger.info(f"Resuming Bitcoin collection from saved position {saved}")
                    else:
                        enable_backfill = os.getenv('ENABLE_HISTORICAL_BACKFILL', 'false').lower() == 'true'
                        start_block = int(os.getenv('BITCOIN_START_BLOCK', '-1'))

                        if enable_backfill and start_block >= 0:
                            self.last_block_height = start_block
                            logger.info(f"Starting Bitcoin collection from block {start_block} (historical backfill)")
                        else:
                            self.last_block_height = latest_height - 1
                            logger.info(f"Starting Bitcoin collection from latest block {latest_height}")

                # Only collect if there's a new block
                if self.last_block_height < latest_height:
                    # Check if parallel processing is enabled
                    parallel_count = int(os.getenv('PARALLEL_BLOCK_FETCH_COUNT', '1'))
                    blocks_behind = latest_height - self.last_block_height

                    # Reduce parallel count if we're being rate limited
                    if self.rate_limited:
                        parallel_count = 1
                        logger.info("Rate limited - switching to sequential block collection")

                    # Use parallel fetching if enabled and we're behind
                    if parallel_count > 1 and blocks_behind > 1:
                        fetch_count = min(parallel_count, blocks_behind)
                        logger.info(f"Fetching {fetch_count} Bitcoin blocks in parallel (blocks {self.last_block_height + 1} to {self.last_block_height + fetch_count})")

                        # Collect multiple blocks in parallel
                        tasks = [
                            self.collect_block(session, client, self.last_block_height + i + 1)
                            for i in range(fetch_count)
                        ]
                        results = await asyncio.gather(*tasks, return_exceptions=True)

                        # Find the highest contiguous successful block from batch start
                        # to avoid skipping failed blocks in the middle of the batch
                        batch_start = self.last_block_height + 1
                        successful_heights = set()
                        for i, result in enumerate(results):
                            block_h = batch_start + i
                            if isinstance(result, Exception):
                                logger.error(f"Error collecting block {block_h}: {result}")
                            elif result > 0:
                                successful_heights.add(block_h)
                                records_collected += result

                        # Only advance position to the end of the contiguous run
                        contiguous_end = self.last_block_height
                        for h in range(batch_start, batch_start + fetch_count):
                            if h in successful_heights:
                                contiguous_end = h
                            else:
                                break
                        self.last_block_height = contiguous_end

                        if successful_heights:
                            self.last_successful_collect = datetime.now()
                            self.retry_delay = max(1, self.retry_delay // 2)
                            await self._save_position(client, self.last_block_height)

                        return  # Exit early after parallel collection

                    # Fall through to sequential collection for single blocks
                    block_height = self.last_block_height + 1

                    # Bitcoin requires two API calls: first get hash, then get block
                    # This is because blocks are identified by hash, not height
                    block_hash = await self._api_call_with_retry(
                        session, f"{self.rpc_url}/block-height/{block_height}", return_type='text'
                    )
                    if block_hash is None:
                        return  # Block not found yet (404) - waiting for next block to be mined

                    block = await self._api_call_with_retry(
                        session, f"{self.rpc_url}/block/{block_hash}", return_type='json'
                    )
                    if block is None:
                        return  # Block not available

                    # EDUCATIONAL NOTE - Fetching Transaction IDs:
                    # The Blockstream API's /block/{hash} endpoint returns block metadata only.
                    # To get transaction IDs, we need a separate API call to /block/{hash}/txids
                    # This returns an array of transaction hashes (txids) that we can then query.
                    all_tx_ids = await self._api_call_with_retry(
                        session, f"{self.rpc_url}/block/{block_hash}/txids", return_type='json'
                    )
                    if all_tx_ids is None:
                        return  # Transaction IDs not available

                    # Limit transactions based on configuration (0 = unlimited)
                    tx_limit = int(os.getenv('BITCOIN_TX_LIMIT', '100'))
                    tx_ids = all_tx_ids if tx_limit == 0 else all_tx_ids[:tx_limit]

                    # EDUCATIONAL NOTE - Bitcoin Block Structure:
                    #
                    # block_height: Number of blocks since genesis (block 0). Also called
                    #               "block number" in other chains.
                    #
                    # previous_block_hash: Links to parent block, creating the blockchain.
                    #                      Genesis block has this set to all zeros.
                    #
                    # merkle_root: Root hash of a Merkle tree containing all transaction hashes.
                    #              This allows efficient verification that a transaction is in
                    #              a block without downloading all transactions (Simplified
                    #              Payment Verification / SPV). Changing ANY transaction
                    #              changes the merkle root.
                    #
                    # difficulty: A measure of how hard it is to find a valid block hash.
                    #             Adjusts every 2016 blocks to maintain ~10 minute block times.
                    #
                    # nonce: A 32-bit number miners increment to find a valid block hash.
                    #        A valid hash must be less than the target (derived from difficulty).
                    #        This is the "work" in Proof-of-Work: trial and error until valid.
                    #
                    # size: Block size in bytes. Bitcoin has a ~1MB base block size limit.
                    #
                    # weight: Replaced "size" as the limiting factor after SegWit upgrade.
                    #         Maximum weight is 4,000,000 units (allows ~1-4 MB of data).
                    #         SegWit transactions have lower weight, incentivizing adoption.
                    block_data = {
                        'block_height': block_height,
                        'block_hash': block['id'],
                        'timestamp': datetime.fromtimestamp(block['timestamp']),
                        'previous_block_hash': block['previousblockhash'],
                        'merkle_root': block['merkle_root'],
                        'difficulty': int(block['difficulty']),
                        'nonce': block['nonce'],
                        'size': block['size'],
                        'weight': block['weight'],
                        'transaction_count': block['tx_count']
                    }

                    # ================================================================
                    # [VERACITY] Validate block data before insertion
                    # ================================================================
                    # This is a critical step in ensuring data quality. We check:
                    # - All required fields are present
                    # - Values are within expected ranges
                    # - Timestamp is reasonable
                    # - Hash formats are valid
                    block_validation = self.validator.validate_bitcoin_block(block_data)

                    if not block_validation.is_valid:
                        logger.warning(
                            f"[VERACITY] Bitcoin block {block_height} has quality issues: "
                            f"{block_validation.issues}"
                        )
                        # Log quality issue for tracking and analysis
                        log_quality_issue(
                            source='bitcoin',
                            record_type='block',
                            record_id=str(block_height),
                            result=block_validation,
                            client=client
                        )

                    if block_validation.warnings:
                        logger.info(
                            f"[VERACITY] Bitcoin block {block_height} warnings: "
                            f"{block_validation.warnings}"
                        )

                    # Convert dict to list for clickhouse_connect (required when table has DEFAULT columns)
                    columns = ['block_height', 'block_hash', 'timestamp', 'previous_block_hash',
                             'merkle_root', 'difficulty', 'nonce', 'size', 'weight', 'transaction_count']
                    block_values = [[block_data[col] for col in columns]]
                    client.insert('bitcoin_blocks', block_values, column_names=columns)
                    records_collected += 1

                    # EDUCATIONAL NOTE - API Rate Limiting:
                    # We limit to 25 transactions per block for several reasons:
                    # 1. API Rate Limits: Public APIs have request quotas
                    # 2. Educational Focus: 25 transactions provide sufficient data for learning
                    # 3. Performance: Bitcoin blocks can have 2000+ transactions
                    # 4. Cost: Some APIs charge per request
                    #
                    # In production systems, you would:
                    # - Use pagination to fetch all transactions
                    # - Implement exponential backoff for rate limit errors
                    # - Consider running your own Bitcoin node for unlimited access

                    # tx_ids already fetched above from /block/{hash}/txids endpoint
                    tx_data = []

                    for tx_id in tx_ids:
                        try:
                            tx = await self._api_call_with_retry(
                                session, f"{self.rpc_url}/tx/{tx_id}", return_type='json'
                            )
                            if tx is None:
                                logger.warning(f"Could not fetch Bitcoin tx {tx_id}")
                                continue

                            # EDUCATIONAL NOTE - Bitcoin Transaction Structure (UTXO Model):
                            #
                            # Unlike Ethereum, Bitcoin transactions don't have a simple
                            # "from" address field. The sender is determined by which
                            # UTXOs (inputs) are being spent.
                            #
                            # vin (inputs): List of UTXOs being consumed (spent)
                            #               Each input references a previous transaction output
                            #
                            # vout (outputs): List of new UTXOs being created
                            #                 Each output has an amount and locking script
                            #
                            # input_count: Number of UTXOs being spent in this transaction
                            # output_count: Number of new UTXOs being created
                            #
                            # fee: Satoshis paid to miners = sum(input values) - sum(output values)
                            #      Higher fees = faster confirmation (miners prioritize profitable txs)
                            #      Fee is implicit, not a separate field in the transaction
                            #
                            # size: Transaction size in bytes (affects fee calculation)
                            # weight: SegWit-adjusted size for fee calculation
                            #
                            # Bitcoin's smallest unit: 1 Satoshi = 0.00000001 BTC (8 decimal places)
                            tx_record = {
                                'tx_hash': tx['txid'],
                                'block_height': block_height,
                                'block_hash': block['id'],
                                'size': tx['size'],
                                'weight': tx['weight'],
                                'fee': int(tx.get('fee', 0)),  # Fee in satoshis, convert to int for UInt64
                                'input_count': len(tx['vin']),
                                'output_count': len(tx['vout']),
                                'timestamp': datetime.fromtimestamp(block['timestamp'])
                            }

                            # [VERACITY] Validate transaction before adding to batch
                            tx_validation = self.validator.validate_bitcoin_transaction(tx_record)
                            if not tx_validation.is_valid:
                                logger.debug(
                                    f"[VERACITY] Bitcoin tx {tx['txid'][:16]}... has issues: "
                                    f"{tx_validation.issues}"
                                )

                            tx_data.append(tx_record)
                        except Exception as e:
                            # Log but continue - don't let one bad transaction stop collection
                            logger.warning(f"Error collecting Bitcoin tx {tx_id}: {e}")
                            continue

                    if tx_data:
                        # Convert list of dicts to list of lists for clickhouse_connect
                        # (required when table has DEFAULT columns)
                        columns = ['tx_hash', 'block_height', 'block_hash', 'size',
                                 'weight', 'fee', 'input_count', 'output_count', 'timestamp']
                        tx_values = [[tx[col] for col in columns] for tx in tx_data]
                        client.insert('bitcoin_transactions', tx_values, column_names=columns)
                        records_collected += len(tx_data)

                    self.last_block_height = block_height
                    self.last_successful_collect = datetime.now()
                    # Reduce retry delay on successful collection
                    self.retry_delay = max(1, self.retry_delay // 2)
                    await self._save_position(client, self.last_block_height)
                    logger.info(f"Collected Bitcoin block {block_height} with {len(tx_data)} transactions")

        except Exception as e:
            error_msg = str(e)
            logger.exception(f"Error collecting Bitcoin data: {e}")

        finally:
            # Record collection metrics for monitoring and analysis
            duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            client.insert('collection_metrics', [{
                'metric_time': start_time,
                'source': 'bitcoin',
                'records_collected': records_collected,
                'collection_duration_ms': duration_ms,
                'error_count': 1 if error_msg else 0,
                'error_message': error_msg
            }])
