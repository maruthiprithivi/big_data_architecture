import { createClient, ClickHouseClient } from '@clickhouse/client'

// ClickHouse client configuration
const getClickHouseClient = (): ClickHouseClient => {
  const host = process.env.CLICKHOUSE_HOST || 'clickhouse'
  const port = process.env.CLICKHOUSE_PORT || '8123'
  const username = process.env.CLICKHOUSE_USER || 'default'
  const password = process.env.CLICKHOUSE_PASSWORD || 'clickhouse_password'
  const database = process.env.CLICKHOUSE_DB || 'blockchain_data'

  // Construct the URL in the format: http://hostname:port
  const url = host.startsWith('http') ? host : `http://${host}:${port}`

  return createClient({
    url: url,
    username: username,
    password: password,
    database: database,
    request_timeout: 30000, // 30 seconds
    compression: {
      response: true,
      request: false,
    },
  })
}

// Bitcoin Blocks Preview
export interface BitcoinBlock {
  block_height: number
  block_hash: string
  timestamp: string
  previous_block_hash: string
  merkle_root: string
  difficulty: number
  nonce: number
  size: number
  weight: number
  transaction_count: number
  collected_at: string
  source: string
}

export async function getBitcoinBlocksPreview(
  limit: number = 100
): Promise<BitcoinBlock[]> {
  const client = getClickHouseClient()

  try {
    const resultSet = await client.query({
      query: `
        SELECT
          block_height,
          block_hash,
          timestamp,
          previous_block_hash,
          merkle_root,
          difficulty,
          nonce,
          size,
          weight,
          transaction_count,
          collected_at,
          source
        FROM bitcoin_blocks
        ORDER BY timestamp DESC
        LIMIT ${limit}
      `,
      format: 'JSONEachRow',
    })

    const rawData = await resultSet.json<BitcoinBlock>()
    await client.close()

    // Ensure we always return an array
    if (Array.isArray(rawData)) {
      return rawData
    }

    console.warn('ClickHouse returned non-array data:', typeof rawData)
    return []
  } catch (error) {
    await client.close()
    console.error('Error fetching Bitcoin blocks:', error)
    console.error('Error details:', error instanceof Error ? error.message : 'Unknown error')
    throw error
  }
}

// Bitcoin Transactions Preview
export interface BitcoinTransaction {
  tx_hash: string
  block_height: number
  block_hash: string
  size: number
  weight: number
  fee: number
  input_count: number
  output_count: number
  timestamp: string
  collected_at: string
  source: string
}

export async function getBitcoinTransactionsPreview(
  limit: number = 100
): Promise<BitcoinTransaction[]> {
  const client = getClickHouseClient()

  try {
    const resultSet = await client.query({
      query: `
        SELECT
          tx_hash,
          block_height,
          block_hash,
          size,
          weight,
          fee,
          input_count,
          output_count,
          timestamp,
          collected_at,
          source
        FROM bitcoin_transactions
        ORDER BY timestamp DESC
        LIMIT ${limit}
      `,
      format: 'JSONEachRow',
    })

    const rawData = await resultSet.json<BitcoinTransaction>()
    await client.close()

    // Ensure we always return an array
    if (Array.isArray(rawData)) {
      return rawData
    }

    console.warn('ClickHouse returned non-array data:', typeof rawData)
    return []
  } catch (error) {
    await client.close()
    console.error('Error fetching Bitcoin transactions:', error)
    console.error('Error details:', error instanceof Error ? error.message : 'Unknown error')
    throw error
  }
}

// Solana Blocks Preview
export interface SolanaBlock {
  slot: number
  block_height: number
  block_hash: string
  timestamp: string
  parent_slot: number
  previous_block_hash: string
  transaction_count: number
  collected_at: string
  source: string
}

export async function getSolanaBlocksPreview(
  limit: number = 100
): Promise<SolanaBlock[]> {
  const client = getClickHouseClient()

  try {
    const resultSet = await client.query({
      query: `
        SELECT
          slot,
          block_height,
          block_hash,
          timestamp,
          parent_slot,
          previous_block_hash,
          transaction_count,
          collected_at,
          source
        FROM solana_blocks
        ORDER BY timestamp DESC
        LIMIT ${limit}
      `,
      format: 'JSONEachRow',
    })

    const rawData = await resultSet.json<SolanaBlock>()
    await client.close()

    // Ensure we always return an array
    if (Array.isArray(rawData)) {
      return rawData
    }

    console.warn('ClickHouse returned non-array data:', typeof rawData)
    return []
  } catch (error) {
    await client.close()
    console.error('Error fetching Solana blocks:', error)
    console.error('Error details:', error instanceof Error ? error.message : 'Unknown error')
    throw error
  }
}

// Solana Transactions Preview
export interface SolanaTransaction {
  signature: string
  slot: number
  block_hash: string
  fee: number
  status: string
  timestamp: string
  collected_at: string
  source: string
}

export async function getSolanaTransactionsPreview(
  limit: number = 100
): Promise<SolanaTransaction[]> {
  const client = getClickHouseClient()

  try {
    const resultSet = await client.query({
      query: `
        SELECT
          signature,
          slot,
          block_hash,
          fee,
          status,
          timestamp,
          collected_at,
          source
        FROM solana_transactions
        ORDER BY timestamp DESC
        LIMIT ${limit}
      `,
      format: 'JSONEachRow',
    })

    const rawData = await resultSet.json<SolanaTransaction>()
    await client.close()

    // Ensure we always return an array
    if (Array.isArray(rawData)) {
      return rawData
    }

    console.warn('ClickHouse returned non-array data:', typeof rawData)
    return []
  } catch (error) {
    await client.close()
    console.error('Error fetching Solana transactions:', error)
    console.error('Error details:', error instanceof Error ? error.message : 'Unknown error')
    throw error
  }
}
