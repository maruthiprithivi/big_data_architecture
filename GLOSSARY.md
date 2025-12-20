# Blockchain Data Ingestion Glossary

A comprehensive glossary of terms used in this project, organized by category. Designed for undergraduate students learning about blockchain and data engineering.

## Table of Contents

1. [Ethereum-Specific Terms](#ethereum-specific-terms)
2. [Bitcoin-Specific Terms](#bitcoin-specific-terms)
3. [Solana-Specific Terms](#solana-specific-terms)
4. [Database & ClickHouse Terms](#database--clickhouse-terms)
5. [Data Engineering Terms](#data-engineering-terms)
6. [API & Web Terms](#api--web-terms)

**Note:** For blockchain fundamentals (blocks, transactions, hashing, consensus), see the Background section in README.md.

---

## Ethereum-Specific Terms

**Note:** Ethereum support is under development. These terms are provided for educational reference. The project currently focuses on Bitcoin and Solana. See README Future Development section for Ethereum roadmap.

### Gas
Unit measuring computational effort on Ethereum. Every operation on the Ethereum Virtual Machine (EVM) costs a specific amount of gas.

| Term | Description |
|------|-------------|
| **Gas Limit** | Maximum gas a transaction/block can use |
| **Gas Used** | Actual gas consumed by execution |
| **Gas Price** | Price per gas unit in Wei (determines priority) |

**Transaction Fee** = Gas Used × Gas Price

### Wei
The smallest unit of Ether. Named after Wei Dai, cryptography pioneer.

| Unit | Wei Value | Ether Value |
|------|-----------|-------------|
| Wei | 1 | 0.000000000000000001 ETH |
| Gwei | 10^9 | 0.000000001 ETH |
| Ether | 10^18 | 1 ETH |

### Nonce (Transaction)
Sequential counter for each Ethereum account. Starts at 0 and increments with each transaction.

**Purposes:**
- Prevent replay attacks (same transaction submitted twice)
- Ensure transaction ordering
- If nonce is 5, you've successfully sent 5 transactions (0-4)

### Smart Contract
Self-executing code stored on the blockchain. Characteristics:
- Has its own address (like a user account)
- Stores data (state variables)
- Can receive and send Ether
- Executes functions when called
- Created by transactions with empty "to" field

### EVM (Ethereum Virtual Machine)
The runtime environment for smart contracts.
- **Deterministic**: Same input always produces same output on all nodes
- **Isolated**: Contracts can't access external data directly
- **Turing-complete**: Can compute anything (within gas limits)

### Miner / Validator
Entity that proposes new blocks:
- **Pre-merge (PoW)**: Miners competed with computational power
- **Post-merge (PoS)**: Validators stake 32 ETH to earn the right to propose

### Parent Hash
Hash of the previous block in the chain. This cryptographic link:
- Creates the "chain" in blockchain
- Makes tampering detectable (changing a block changes its hash)
- Invalidates all subsequent blocks if modified

---

## Bitcoin-Specific Terms

### Satoshi
The smallest unit of Bitcoin. Named after Bitcoin's pseudonymous creator.

| Unit | Satoshi Value | BTC Value |
|------|---------------|-----------|
| Satoshi | 1 | 0.00000001 BTC |
| Bitcoin | 100,000,000 | 1 BTC |

### UTXO (Unspent Transaction Output)
Bitcoin's model for tracking ownership. Unlike account balances, Bitcoin tracks individual "coins" (UTXOs).

**How it works:**
1. When you receive Bitcoin, a UTXO is created for you
2. To spend, you reference the UTXO as an input
3. You prove ownership with your signature
4. The UTXO is consumed, new UTXOs created for recipient and change

**Analogy:** Like physical cash. You can't "update" a $10 bill - you spend it and get change.

### Merkle Root
Root hash of a Merkle tree containing all transaction hashes in a block.

**Benefits:**
- Efficient verification that a transaction is in a block
- Don't need to download all transactions (SPV wallets)
- Changing ANY transaction changes the merkle root

### Mining Difficulty
A measure of how hard it is to find a valid block hash.
- Adjusts every 2016 blocks (~2 weeks)
- Target: maintain ~10 minute average block time
- Higher difficulty = more computational work required

### Nonce (Block)
A 32-bit number in the block header that miners increment to find a valid hash.
- A valid hash must be less than the target (derived from difficulty)
- This trial-and-error process IS the "work" in Proof-of-Work
- Miners try billions of nonces per second

### Block Weight
Post-SegWit measure of block resource usage (replaced simple size limit).

| Metric | Limit | Notes |
|--------|-------|-------|
| Weight | 4,000,000 units | Current limit |
| Base Size | ~1 MB | Non-witness data |
| Total Size | Up to ~4 MB | With witness data |

### SegWit (Segregated Witness)
Bitcoin upgrade (2017) that separates signature data from transaction data.

**Benefits:**
- More transactions per block (witness data weighs less)
- Fixes transaction malleability bug
- Enables Lightning Network

### Coinbase Transaction
The first transaction in every block, created by the miner.
- Contains block reward (newly minted BTC) + transaction fees
- Has no inputs (the only transaction type that creates new Bitcoin)
- Includes arbitrary data field (used for messages, mining pool identification)

---

## Solana-Specific Terms

### Slot
A time window (~400ms) when a designated leader can produce a block.

**Key points:**
- Slots are numbered sequentially (like block numbers elsewhere)
- Not every slot has a block (leader might miss it)
- Slot numbers can have gaps in actual blocks

### Block Height
Count of successful blocks in the chain (no gaps, always sequential).

**Relationship:** Block Height ≤ Slot Number (because slots can be skipped)

**Example:** If slots 100, 101, 103 exist (102 skipped), block heights are 1, 2, 3

### Lamport
The smallest unit of SOL. Named after Leslie Lamport, computer scientist known for distributed systems work.

| Unit | Lamport Value | SOL Value |
|------|---------------|-----------|
| Lamport | 1 | 0.000000001 SOL |
| SOL | 1,000,000,000 | 1 SOL |

### Signature
In Solana, the transaction signature IS the transaction ID.
- First signature belongs to the fee payer
- Uses Ed25519 elliptic curve cryptography (very fast verification)
- Unlike Ethereum where tx hash is computed from contents

### Program
Solana's term for smart contracts. Key difference from Ethereum:
- Programs are **stateless** (don't store data themselves)
- Data stored in separate **accounts** that programs can read/modify
- This enables parallel execution of non-conflicting transactions

### Proof-of-History (PoH)
Solana's innovation: cryptographic timestamp created BEFORE consensus.
- Creates verifiable ordering of events
- Reduces communication overhead between validators
- Enables high throughput (~65,000 TPS theoretical)

### Leader
The validator designated to produce blocks during specific slots.
- Leader schedule computed in advance from stake distribution
- Known ahead of time, enabling transaction forwarding (Gulf Stream)

### Account
In Solana, everything is an account:
- Wallet addresses
- Program data storage
- Programs themselves

**Account fields:** Lamport balance, owner program, data, executable flag

---

## Database & ClickHouse Terms

### Columnar Storage
Data organization that stores columns together instead of rows.

| Storage Type | Best For | Example |
|--------------|----------|---------|
| **Row** (PostgreSQL) | OLTP, full row access | User profiles |
| **Columnar** (ClickHouse) | Analytics, aggregations | Blockchain analytics |

**Why columnar for analytics:**
- Only read columns needed for query
- Better compression (similar values together)
- Efficient aggregations (SUM, AVG, COUNT)

### OLAP (Online Analytical Processing)
Database workload pattern for analytical queries.

| OLAP | OLTP |
|------|------|
| Complex aggregations | Simple CRUD operations |
| Read-heavy | Write-heavy |
| Large scans | Point lookups |
| Historical analysis | Current state |

### MergeTree Engine
ClickHouse's primary table engine. Features:
- Sorted data storage (ORDER BY)
- Background merging of data parts
- Support for partitioning and indexing
- Primary key for efficient filtering

### Partitioning
Dividing table data into separate physical units by a key.

**Example:** `PARTITION BY toYYYYMM(timestamp)` creates monthly partitions.

**Benefits:**
- Query pruning: Skip irrelevant partitions entirely
- Data management: Drop old partitions easily
- Performance: Smaller chunks to process

### Compression Ratio
How much data is reduced by compression.

**Formula:** `(1 - compressed_size / uncompressed_size) × 100%`

**Example:** 1GB uncompressed → 100MB compressed = 90% compression ratio

ClickHouse typically achieves 80-95% compression on blockchain data.

### Data Part
ClickHouse's unit of storage. Each INSERT creates a new part.
- Background threads merge small parts into larger ones
- Query: `SELECT * FROM system.parts WHERE active = 1`

### ReplacingMergeTree
Engine that removes duplicate rows (same sorting key) during background merges.
- Used for maintaining "latest state" tables
- Deduplication is eventual (happens during merges)

### Primary Key vs ORDER BY
In ClickHouse (different from traditional databases):

| Concept | Description |
|---------|-------------|
| **ORDER BY** | Physical sorting of data on disk (required) |
| **PRIMARY KEY** | Columns indexed for fast filtering (defaults to ORDER BY prefix) |

**Important:** PRIMARY KEY does NOT enforce uniqueness in ClickHouse!

---

## Data Engineering Terms

### ETL (Extract, Transform, Load)
Pattern for moving data between systems:

| Stage | Description | Our Implementation |
|-------|-------------|-------------------|
| **Extract** | Pull from source | Fetch from blockchain RPC |
| **Transform** | Convert format | Parse JSON to our schema |
| **Load** | Insert into destination | Write to ClickHouse |

### Data Ingestion
The process of collecting and importing data into a storage system.

| Type | Description | Example |
|------|-------------|---------|
| **Batch** | Periodic scheduled loads | Daily exports |
| **Streaming** | Real-time continuous | Kafka consumers |
| **Micro-batch** | Small frequent batches | Our system (every 5 seconds) |

### Idempotency
Property where an operation produces the same result if executed multiple times.

**Importance:** If a pipeline fails and retries, idempotent operations won't create duplicates.

**Example:** Using UPSERT instead of INSERT

### Backpressure
When a system slows down producers because consumers can't keep up.

**Example:** Our safety limits (time, size) are a form of backpressure - we stop producing data when we've collected enough.

### Rate Limiting
Restricting the number of requests in a time period.

| Strategy | Description |
|----------|-------------|
| **Fixed Window** | X requests per minute |
| **Sliding Window** | X requests in last 60 seconds |
| **Token Bucket** | Tokens replenish over time |
| **Exponential Backoff** | Wait longer after each failure |

Public RPC endpoints typically limit to 10-100 requests/second.

---

## API & Web Terms

### REST API
Architectural style for web services using HTTP methods.

| Method | Purpose | Example |
|--------|---------|---------|
| **GET** | Read data | GET /status |
| **POST** | Create/execute | POST /start |
| **PUT** | Update/replace | PUT /config |
| **DELETE** | Remove | DELETE /data |

### JSON-RPC
Protocol for remote procedure calls using JSON format. Standard for Ethereum and Solana APIs.

**Request format:**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "eth_blockNumber",
    "params": []
}
```

**Response format:**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": "0x1234567"
}
```

### Async/Await
Python syntax for asynchronous programming.

```python
# Synchronous: Blocks while waiting
response = requests.get(url)  # Waits here

# Asynchronous: Can do other work while waiting
response = await session.get(url)  # Yields control
```

**Benefits:** Efficient I/O-bound operations (API calls, database queries)

### FastAPI
Modern Python web framework used for our collector service.

**Features:**
- Async support (async/await)
- Automatic OpenAPI documentation
- Type validation with Pydantic
- High performance

### Streamlit
Python library for creating data apps. Used for our dashboard.

**Key concept:** Re-runs entire script on each interaction. Requires caching for expensive operations.

### WebSocket
Protocol for persistent, two-way communication (not used in this project, but common for real-time blockchain data).

**Comparison:**
- HTTP: Request-response, connection closes
- WebSocket: Persistent connection, server can push updates
