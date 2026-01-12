import { NextResponse } from 'next/server'
import { getSolanaTransactionsPreview } from '@/app/lib/clickhouse'

export const dynamic = 'force-dynamic'
export const revalidate = 0

export async function GET() {
  try {
    const data = await getSolanaTransactionsPreview(550)

    // Ensure data is an array
    if (!Array.isArray(data)) {
      console.error('Invalid data format from ClickHouse:', typeof data)
      return NextResponse.json([], { status: 200 })
    }

    return NextResponse.json(data)
  } catch (error) {
    console.error('Error fetching Solana transactions preview:', error)
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    console.error('Detailed error:', errorMessage)
    return NextResponse.json(
      { error: 'Failed to fetch Solana transactions data', details: errorMessage },
      { status: 500 }
    )
  }
}
