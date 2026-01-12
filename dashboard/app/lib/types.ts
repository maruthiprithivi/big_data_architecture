/**
 * Type definitions for blockchain data dashboard
 */

/**
 * Metrics data returned from the /api/data endpoint
 */
export interface MetricsData {
  total_records: number
  bitcoin_blocks: number
  bitcoin_transactions: number
  solana_blocks: number
  solana_transactions: number
}

/**
 * Collector status data
 */
export interface CollectorStatus {
  is_running: boolean
  started_at: string | null
  stopped_at: string | null
  total_records: number
  total_size_bytes: number
  records_per_second: number
}
