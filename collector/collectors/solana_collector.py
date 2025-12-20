"""
Solana Blockchain Data Collector
Collects blocks and transactions from Solana via RPC

=== EDUCATIONAL OVERVIEW ===

Solana is a high-throughput blockchain using Proof-of-Stake combined with
Proof-of-History (PoH). It can process thousands of transactions per second
(theoretical max ~65,000 TPS) compared to ~15 for Ethereum and ~7 for Bitcoin.

Key Concepts Demonstrated:
- JSON-RPC 2.0 protocol interaction
- Slots vs Block Height (Solana's unique terminology)
- Transaction signatures instead of hashes
- Lamports: Solana's smallest unit (1 SOL = 10^9 Lamports)
- High-throughput blockchain data collection challenges

Slots vs Blocks:
- Slot: A time window (~400ms) when a designated leader can produce a block
- Not every slot has a block (leader might miss their slot or be offline)
- Block height: Count of successful blocks (may skip slot numbers)
- Example: Slots 100, 101, 103 might exist while slot 102 was skipped

Why Solana is Fast:
1. Proof-of-History: Cryptographic timestamp creates ordering before consensus,
   reducing the communication overhead between validators
2. Parallel transaction processing: Transactions that don't touch the same
   accounts can execute in parallel (unlike sequential EVM execution)
3. Gulf Stream: Forwards transactions to expected leaders before they're needed
4. Turbine: Block propagation protocol that breaks data into smaller pieces
5. Pipelining: Different stages of block processing happen simultaneously
"""

import logging
from datetime import datetime
import aiohttp
import json

logger = logging.getLogger(__name__)


class SolanaCollector:
    """
    Collects block and transaction data from the Solana blockchain.

    Solana uses a unique leader-based consensus where validators take turns
    producing blocks based on a predetermined schedule derived from stake.
    """

    def __init__(self, rpc_url: str, enabled: bool = True):
        """
        Initialize the Solana collector.

        EDUCATIONAL NOTE - Solana RPC:
        Solana nodes expose a JSON-RPC 2.0 API similar to Ethereum.
        The public mainnet endpoint (api.mainnet-beta.solana.com) has rate limits.
        For production, use dedicated RPC providers like Helius, QuickNode, or Alchemy.

        API Documentation: https://docs.solana.com/api/http

        Args:
            rpc_url: The RPC endpoint URL for a Solana node
            enabled: Whether this collector should run
        """
        self.rpc_url = rpc_url
        self.enabled = enabled
        # Track last processed slot (not block height) for sequential collection
        self.last_slot = None

    async def rpc_call(self, session, method: str, params: list):
        """
        Make a JSON-RPC 2.0 call to the Solana node.

        EDUCATIONAL NOTE - JSON-RPC 2.0 Protocol:
        A stateless, light-weight remote procedure call protocol using JSON.

        Request format:
        {
            "jsonrpc": "2.0",      # Protocol version (always "2.0")
            "id": 1,               # Request identifier for matching responses
            "method": "getSlot",   # RPC method name
            "params": []           # Method parameters as an array
        }

        Response format (success):
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": 123456789    # The method's return value
        }

        Response format (error):
        {
            "jsonrpc": "2.0",
            "id": 1,
            "error": {"code": -32600, "message": "Invalid Request"}
        }

        Common Solana methods: getSlot, getBlock, getTransaction, getBalance, etc.

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
            return result.get('result')

    async def collect(self, client):
        """
        Collect the next Solana block (slot) and its transactions.

        EDUCATIONAL NOTE - Solana Block Time:
        Solana targets ~400ms slots, making it one of the fastest blockchains.
        However, not every slot produces a block (skipped slots), so actual
        block production varies. The leader schedule determines which validator
        proposes blocks for each slot.

        Args:
            client: ClickHouse database client for inserting collected data
        """
        if not self.enabled:
            return

        start_time = datetime.now()
        records_collected = 0
        error_msg = ""

        try:
            async with aiohttp.ClientSession() as session:
                # Get the current slot number (like block height, but includes skipped)
                latest_slot = await self.rpc_call(session, "getSlot", [])

                # If first run, start from latest slot
                if self.last_slot is None:
                    self.last_slot = latest_slot - 1

                # Only collect if there's a new slot
                if self.last_slot < latest_slot:
                    slot = self.last_slot + 1

                    # EDUCATIONAL NOTE - getBlock Parameters:
                    #
                    # encoding: "json" returns human-readable format
                    #           "base64" or "base58" for raw transaction data
                    #
                    # transactionDetails: "full" returns complete transaction data
                    #                     "signatures" returns only signatures (faster)
                    #                     "none" returns only block metadata
                    #
                    # rewards: Include staking rewards in response (we skip for simplicity)
                    #
                    # maxSupportedTransactionVersion: Solana has versioned transactions
                    #   - Version 0: Original transaction format
                    #   - Version 1+: Support address lookup tables (more accounts per tx)
                    #   Setting to 0 ensures we can parse all transaction versions
                    block = await self.rpc_call(session, "getBlock", [
                        slot,
                        {
                            "encoding": "json",
                            "transactionDetails": "full",
                            "rewards": False,
                            "maxSupportedTransactionVersion": 0
                        }
                    ])

                    if block:
                        # EDUCATIONAL NOTE - Solana Block Structure:
                        #
                        # slot: The slot number (time window index). Primary identifier.
                        #       Unlike other chains, slot numbers can have gaps (skipped slots).
                        #
                        # block_height: Count of confirmed blocks (no gaps, always sequential).
                        #               block_height <= slot because slots can be skipped.
                        #
                        # blockhash: Unique identifier for the block, computed from contents.
                        #
                        # blockTime: Unix timestamp when the block was produced.
                        #            May be null if the block is too old or not yet available.
                        #
                        # parentSlot: The slot number of the parent block.
                        #             parentSlot < slot, but might not be slot-1 if slots skipped.
                        #
                        # previousBlockhash: Hash of the parent block, creating the chain.
                        block_data = {
                            'slot': slot,
                            'block_height': block.get('blockHeight', 0),
                            'block_hash': block.get('blockhash', ''),
                            'timestamp': datetime.fromtimestamp(block.get('blockTime', 0)) if block.get('blockTime') else datetime.now(),
                            'parent_slot': block.get('parentSlot', 0),
                            'previous_block_hash': block.get('previousBlockhash', ''),
                            'transaction_count': len(block.get('transactions', []))
                        }

                        # Convert dict to list for clickhouse_connect (required when table has DEFAULT columns)
                        columns = ['slot', 'block_height', 'block_hash', 'timestamp',
                                 'parent_slot', 'previous_block_hash', 'transaction_count']
                        block_values = [[block_data[col] for col in columns]]
                        client.insert('solana_blocks', block_values, column_names=columns)
                        records_collected += 1

                        # Process transactions
                        tx_data = []
                        transactions = block.get('transactions', [])

                        # EDUCATIONAL NOTE - Why Limit to 50 Transactions:
                        # Solana blocks can contain 1000+ transactions due to high throughput.
                        # We limit to 50 for educational purposes:
                        # 1. Keeps database size manageable for learning environment
                        # 2. Demonstrates sampling technique common in big data processing
                        # 3. Reduces API response time and memory usage
                        # 4. Focus on quality of data understanding over quantity
                        #
                        # In production, you would either:
                        # - Process all transactions (for completeness)
                        # - Use Solana's Geyser plugin for real-time streaming
                        # - Subscribe to specific programs/accounts of interest
                        for tx in transactions[:50]:
                            try:
                                meta = tx.get('meta', {})
                                transaction = tx.get('transaction', {})

                                # EDUCATIONAL NOTE - Solana Transaction Structure:
                                #
                                # signatures: List of signatures on this transaction.
                                #             The FIRST signature is the transaction ID!
                                #             Unlike Ethereum where tx hash is computed from contents,
                                #             Solana uses the fee payer's signature as the identifier.
                                #             Uses Ed25519 elliptic curve cryptography (fast verification).
                                #
                                # fee: Transaction fee in Lamports (1 SOL = 10^9 Lamports).
                                #      Fee = signature_count * lamports_per_signature (~5000 lamports).
                                #      Much cheaper than Ethereum! (~$0.00025 vs $1-100).
                                #
                                # status: Determined by checking if 'err' field is null.
                                #         'success': Transaction executed successfully
                                #         'failed': Transaction failed (e.g., insufficient funds,
                                #                   program error, account already in use)
                                #
                                #         IMPORTANT: Solana charges fees even for FAILED transactions!
                                #         This differs from Ethereum which refunds unused gas but
                                #         still consumes gas used up to the point of failure.
                                signatures = transaction.get('signatures', [])
                                signature = signatures[0] if signatures else ''

                                tx_record = {
                                    'signature': signature,
                                    'slot': slot,
                                    'block_hash': block.get('blockhash', ''),
                                    'fee': int(meta.get('fee', 0)),  # Fee in lamports, convert to int for UInt64
                                    'status': 'success' if meta.get('err') is None else 'failed',
                                    'timestamp': datetime.fromtimestamp(block.get('blockTime', 0)) if block.get('blockTime') else datetime.now()
                                }
                                tx_data.append(tx_record)
                            except Exception as e:
                                # Log but continue - individual transaction errors shouldn't stop collection
                                logger.warning(f"Error processing Solana transaction: {e}")
                                continue

                        if tx_data:
                            # Convert list of dicts to list of lists for clickhouse_connect
                            columns = ['signature', 'slot', 'block_hash', 'fee', 'status', 'timestamp']
                            tx_values = [[tx[col] for col in columns] for tx in tx_data]
                            client.insert('solana_transactions', tx_values, column_names=columns)
                            records_collected += len(tx_data)

                        self.last_slot = slot
                        logger.info(f"Collected Solana slot {slot} with {len(tx_data)} transactions")
                    else:
                        # Block not available - slot might be skipped or not yet confirmed
                        # EDUCATIONAL NOTE: This is normal on Solana! Not every slot has a block.
                        # The leader for that slot might have been offline or too slow.
                        logger.debug(f"Solana slot {slot} not available yet")

        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error collecting Solana data: {e}")

        finally:
            # Record collection metrics for monitoring dashboard
            duration_ms = int((datetime.now() - start_time).total_seconds() * 1000)
            client.insert('collection_metrics', [{
                'metric_time': start_time,
                'source': 'solana',
                'records_collected': records_collected,
                'collection_duration_ms': duration_ms,
                'error_count': 1 if error_msg else 0,
                'error_message': error_msg
            }])
