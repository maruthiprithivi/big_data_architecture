"""
Bitcoin Blockchain Data Collector
Collects blocks and transactions from Bitcoin via Blockstream API

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

        EDUCATIONAL NOTE - Blockstream Esplora API:
        We use Blockstream's public API instead of running a Bitcoin full node.
        This is a REST API (not JSON-RPC like Ethereum) that provides:
        - Block data by height or hash
        - Transaction details by txid
        - Address information and UTXOs

        API Documentation: https://github.com/Blockstream/esplora/blob/master/API.md

        Args:
            rpc_url: Base URL for the Blockstream API (e.g., https://blockstream.info/api)
            enabled: Whether this collector should run
        """
        self.rpc_url = rpc_url
        self.enabled = enabled
        # Track last processed block to collect sequentially
        self.last_block_height = None

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
                async with session.get(f"{self.rpc_url}/blocks/tip/height") as resp:
                    latest_height = int(await resp.text())

                # If first run, start from latest block
                if self.last_block_height is None:
                    self.last_block_height = latest_height - 1

                # Only collect if there's a new block
                if self.last_block_height < latest_height:
                    block_height = self.last_block_height + 1

                    # Bitcoin requires two API calls: first get hash, then get block
                    # This is because blocks are identified by hash, not height
                    async with session.get(f"{self.rpc_url}/block-height/{block_height}") as resp:
                        block_hash = await resp.text()

                    async with session.get(f"{self.rpc_url}/block/{block_hash}") as resp:
                        block = await resp.json()

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
                    tx_ids = block['tx'][:25] if 'tx' in block else []
                    tx_data = []

                    for tx_id in tx_ids:
                        try:
                            async with session.get(f"{self.rpc_url}/tx/{tx_id}") as resp:
                                tx = await resp.json()

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
                    logger.info(f"Collected Bitcoin block {block_height} with {len(tx_data)} transactions")

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error collecting Bitcoin data: {e}")

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
