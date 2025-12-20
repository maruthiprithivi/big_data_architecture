"""
Ethereum Blockchain Data Collector
Collects blocks and transactions from Ethereum via RPC

=== EDUCATIONAL OVERVIEW ===

This collector demonstrates how to interact with the Ethereum blockchain using
the JSON-RPC API. Ethereum is an account-based blockchain (unlike Bitcoin's UTXO
model), meaning accounts have balances that get updated with each transaction.

Key Concepts Demonstrated:
- JSON-RPC 2.0 protocol for Ethereum interaction
- Block structure in a Proof-of-Stake blockchain
- Transaction data including gas fees and nonces
- Async data collection patterns

Understanding Gas:
Gas is Ethereum's unit of computational effort. Every operation on the Ethereum
Virtual Machine (EVM) costs a specific amount of gas. Users pay gas_price (in Wei)
multiplied by gas_used to compensate validators for processing transactions.

Wei is the smallest unit of Ether: 1 ETH = 10^18 Wei (similar to satoshis in Bitcoin)
"""

import logging
from datetime import datetime
import aiohttp

logger = logging.getLogger(__name__)


class EthereumCollector:
    """
    Collects block and transaction data from the Ethereum blockchain.

    Ethereum uses an account-based model where each address has a balance.
    This differs from Bitcoin's UTXO (Unspent Transaction Output) model.
    """

    def __init__(self, rpc_url: str, enabled: bool = True):
        """
        Initialize the Ethereum collector.

        EDUCATIONAL NOTE - RPC (Remote Procedure Call):
        Ethereum nodes expose a JSON-RPC 2.0 API that allows external applications to
        query blockchain data and submit transactions. We use direct HTTP requests
        with aiohttp (async HTTP client) for better compatibility with free RPC endpoints.

        Common public RPC endpoints have rate limits (typically 10-100 requests/second).
        Production systems use dedicated providers like Infura, Alchemy, or QuickNode.

        Args:
            rpc_url: The HTTP endpoint for an Ethereum node's JSON-RPC API
            enabled: Whether this collector should run (allows disabling via config)
        """
        self.rpc_url = rpc_url
        self.enabled = enabled
        # Track last processed block to avoid duplicates and ensure sequential collection
        self.last_block = None

    async def rpc_call(self, session, method: str, params: list):
        """
        Make a JSON-RPC 2.0 call to the Ethereum node.

        EDUCATIONAL NOTE - JSON-RPC 2.0 Protocol:
        A stateless, light-weight remote procedure call protocol using JSON.

        Request format:
        {
            "jsonrpc": "2.0",           # Protocol version (always "2.0")
            "id": 1,                    # Request identifier for matching responses
            "method": "eth_blockNumber", # RPC method name
            "params": []                # Method parameters as an array
        }

        Response format (success):
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": "0x10d4f"         # The method's return value (hex encoded)
        }

        Common Ethereum methods: eth_blockNumber, eth_getBlockByNumber, eth_getTransactionByHash, etc.

        Args:
            session: aiohttp client session for making HTTP requests
            method: The RPC method name to call
            params: List of parameters for the method

        Returns:
            The 'result' field from the response, or None if there was an error
        """
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        }
        async with session.post(self.rpc_url, json=payload) as resp:
            result = await resp.json()
            if 'error' in result:
                raise Exception(f"RPC error: {result['error']}")
            return result.get('result')

    async def collect(self, client):
        """
        Collect the next Ethereum block and its transactions.

        EDUCATIONAL NOTE - Block Production:
        On Ethereum mainnet (post-merge to Proof-of-Stake), a new block is produced
        approximately every 12 seconds. Validators take turns proposing blocks based
        on their staked ETH.

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
            # We use aiohttp (async HTTP client) instead of Web3.py to enable
            # better compatibility with free public RPC endpoints. Some free
            # endpoints reject Web3.py's HTTPProvider but accept standard JSON-RPC calls.
            async with aiohttp.ClientSession() as session:
                # EDUCATIONAL NOTE - Block Numbers:
                # Ethereum blocks are numbered sequentially starting from 0 (genesis block).
                # The "latest" block is the most recently finalized block on the chain.
                # Block numbers are also called "block height" in some contexts.

                # Get current block number (returns hex string like "0x10d4f")
                block_num_hex = await self.rpc_call(session, "eth_blockNumber", [])
                latest_block_num = int(block_num_hex, 16)  # Convert hex to integer

                # If first run, start from latest block (don't try to backfill history)
                if self.last_block is None:
                    self.last_block = latest_block_num - 1

                # Only collect if there's a new block we haven't processed
                if self.last_block < latest_block_num:
                    block_num = self.last_block + 1

                    # EDUCATIONAL NOTE - Block Retrieval Parameters:
                    # eth_getBlockByNumber takes two parameters:
                    # 1. Block number as hex string (e.g., "0x10d4f")
                    # 2. Boolean: true = return full transaction objects, false = just tx hashes
                    #
                    # We use true to get complete transaction data in one API call.
                    # For production with high transaction counts, you might fetch separately.
                    block = await self.rpc_call(session, "eth_getBlockByNumber", [
                        hex(block_num),  # Convert integer to hex string
                        True  # Include full transaction objects
                    ])

                    if block:
                        # EDUCATIONAL NOTE - Ethereum Block Structure:
                        # A block contains: header (metadata), transactions list, and uncles (ommers).
                        #
                        # Key fields explained:
                        # - hash: Unique identifier computed from block header using Keccak-256
                        # - parentHash: Links this block to the previous block, creating the "chain"
                        #   Changing any block changes its hash, invalidating all subsequent blocks
                        # - miner: Address that proposed this block (post-merge: the validator address)
                        # - difficulty: Legacy field from Proof-of-Work era; now always 0 post-merge
                        # - gasLimit: Maximum gas allowed in this block (~30M on mainnet)
                        # - gasUsed: Actual gas consumed by all transactions in this block
                        # - size: Block size in bytes (affects network propagation time)
                        block_data = {
                            'block_number': int(block['number'], 16),
                            'block_hash': block['hash'],  # Already a hex string
                            'timestamp': datetime.fromtimestamp(int(block['timestamp'], 16)),
                            'parent_hash': block['parentHash'],
                            'miner': block['miner'],
                            'difficulty': int(block['difficulty'], 16),
                            'total_difficulty': str(int(block.get('totalDifficulty', '0x0'), 16)),
                            'size': int(block['size'], 16),
                            'gas_limit': int(block['gasLimit'], 16),
                            'gas_used': int(block['gasUsed'], 16),
                            'transaction_count': len(block['transactions'])
                        }

                        # Convert dict to list for clickhouse_connect (required when table has DEFAULT columns)
                        columns = ['block_number', 'block_hash', 'timestamp', 'parent_hash', 'miner',
                                 'difficulty', 'total_difficulty', 'size', 'gas_limit', 'gas_used', 'transaction_count']
                        block_values = [[block_data[col] for col in columns]]
                        client.insert('ethereum_blocks', block_values, column_names=columns)
                        records_collected += 1

                        # EDUCATIONAL NOTE - Ethereum Transaction Fields:
                        #
                        # hash: Unique identifier computed from transaction contents
                        # from: The sender's 20-byte Ethereum address (derived from public key)
                        # to: Recipient address; null for contract creation transactions
                        # value: Amount of Ether transferred in Wei (1 ETH = 10^18 Wei)
                        # gas: Maximum gas the sender is willing to spend (gas limit for this tx)
                        # gasPrice: Price per gas unit in Wei (determines priority in block inclusion)
                        # nonce: Sequential counter for sender's account; prevents replay attacks
                        #        Each account's nonce starts at 0 and increments with each transaction
                        #        If you send tx with nonce 5, you must have already sent 0,1,2,3,4
                        # transactionIndex: Position in the block (0 = first transaction)
                        #
                        # Transaction Cost = gas_used * gas_price (actual cost after execution)
                        # The 'gas' field is the limit; actual gas_used may be less
                        tx_data = []
                        for tx in block['transactions']:
                            tx_record = {
                                'tx_hash': tx['hash'],
                                'block_number': int(tx['blockNumber'], 16),
                                'block_hash': tx['blockHash'],
                                'from_address': tx['from'],
                                # to_address is None for contract creation transactions
                                'to_address': tx['to'] if tx['to'] else '',
                                # Value stored as string to handle large numbers (uint256)
                                'value': str(int(tx['value'], 16)),
                                'gas': int(tx['gas'], 16),
                                'gas_price': str(int(tx['gasPrice'], 16)),
                                'nonce': int(tx['nonce'], 16),
                                'transaction_index': int(tx['transactionIndex'], 16),
                                'timestamp': datetime.fromtimestamp(int(block['timestamp'], 16))
                            }
                            tx_data.append(tx_record)

                        if tx_data:
                            # Convert list of dicts to list of lists for clickhouse_connect
                            # (required when table has DEFAULT columns)
                            columns = ['tx_hash', 'block_number', 'block_hash', 'from_address', 'to_address',
                                     'value', 'gas', 'gas_price', 'nonce', 'transaction_index', 'timestamp']
                            tx_values = [[tx[col] for col in columns] for tx in tx_data]
                            client.insert('ethereum_transactions', tx_values, column_names=columns)
                            records_collected += len(tx_data)

                        self.last_block = block_num
                        logger.info(f"Collected Ethereum block {block_num} with {len(tx_data)} transactions")

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error collecting Ethereum data: {e}")

        finally:
            # EDUCATIONAL NOTE - Metrics Collection:
            # Recording metrics for each collection cycle enables:
            # 1. Performance monitoring (how long does collection take?)
            # 2. Error tracking (which chains have issues?)
            # 3. Throughput analysis (records per second)
            # This is a common pattern in data engineering pipelines.
            duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            client.insert('collection_metrics', [{
                'metric_time': start_time,
                'source': 'ethereum',
                'records_collected': records_collected,
                'collection_duration_ms': duration_ms,
                'error_count': 1 if error_msg else 0,
                'error_message': error_msg
            }])
