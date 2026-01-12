import { NextResponse } from 'next/server'
import { createClient } from '@clickhouse/client'

export const dynamic = 'force-dynamic'
export const revalidate = 0

/**
 * GET /api/data
 *
 * Returns aggregate counts for all blockchain data tables.
 * This endpoint queries ClickHouse to get the total number of records
 * for each blockchain type (Bitcoin blocks, Bitcoin transactions, etc.)
 */
export async function GET() {
  try {
    // Create ClickHouse client with proper URL format
    const host = process.env.CLICKHOUSE_HOST || 'clickhouse'
    const port = process.env.CLICKHOUSE_PORT || '8123'
    const url = host.startsWith('http') ? host : `http://${host}:${port}`

    const client = createClient({
      url: url,
      username: process.env.CLICKHOUSE_USER || 'default',
      password: process.env.CLICKHOUSE_PASSWORD || 'clickhouse_password',
      database: process.env.CLICKHOUSE_DB || 'blockchain_data',
      request_timeout: 10000,
    })

    // Query counts for all tables
    const resultSet = await client.query({
      query: `
        SELECT
          (SELECT count() FROM bitcoin_blocks) as bitcoin_blocks,
          (SELECT count() FROM bitcoin_transactions) as bitcoin_transactions,
          (SELECT count() FROM solana_blocks) as solana_blocks,
          (SELECT count() FROM solana_transactions) as solana_transactions
      `,
      format: 'JSONEachRow',
    })

    const data = await resultSet.json<{
      bitcoin_blocks: string
      bitcoin_transactions: string
      solana_blocks: string
      solana_transactions: string
    }>()

    await client.close()

    // Parse counts and calculate total
    const counts = data[0] || {
      bitcoin_blocks: '0',
      bitcoin_transactions: '0',
      solana_blocks: '0',
      solana_transactions: '0',
    }

    const bitcoinBlocks = parseInt(counts.bitcoin_blocks) || 0
    const bitcoinTransactions = parseInt(counts.bitcoin_transactions) || 0
    const solanaBlocks = parseInt(counts.solana_blocks) || 0
    const solanaTransactions = parseInt(counts.solana_transactions) || 0

    return NextResponse.json({
      total_records:
        bitcoinBlocks + bitcoinTransactions + solanaBlocks + solanaTransactions,
      bitcoin_blocks: bitcoinBlocks,
      bitcoin_transactions: bitcoinTransactions,
      solana_blocks: solanaBlocks,
      solana_transactions: solanaTransactions,
    })
  } catch (error) {
    console.error('Error fetching data:', error)
    return NextResponse.json(
      {
        error: 'Failed to fetch blockchain data',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
