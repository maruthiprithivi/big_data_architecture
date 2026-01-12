'use client'

import { useEffect, useCallback, useState } from 'react'
import { useCollectorStatus } from './hooks/useCollectorStatus'
import { useBlockchainData } from './hooks/useBlockchainData'
import {
  useBitcoinBlocksPreview,
  useBitcoinTransactionsPreview,
  useSolanaBlocksPreview,
  useSolanaTransactionsPreview
} from './hooks/usePreviewData'
import StatusCard from './components/StatusCard'
import ControlButtons from './components/ControlButtons'
import CountdownTimer from './components/CountdownTimer'
import MetricsGrid from './components/MetricsGrid'
import BlockchainChart from './components/BlockchainChart'
import DataTable from './components/DataTable'
import PreviewTable from './components/PreviewTable'

export default function DashboardPage() {
  const { status, isLoading: statusLoading, isError: statusError, mutate: refreshStatus } = useCollectorStatus()
  const { data, isLoading: dataLoading, isError: dataError } = useBlockchainData()

  // Fetch preview data for tables
  const bitcoinBlocks = useBitcoinBlocksPreview()
  const bitcoinTransactions = useBitcoinTransactionsPreview()
  const solanaBlocks = useSolanaBlocksPreview()
  const solanaTransactions = useSolanaTransactionsPreview()

  // State for auto-stop notification
  const [autoStopMessage, setAutoStopMessage] = useState<string | null>(null)

  // Get max collection time from environment (fallback to 10 minutes)
  const maxMinutes = parseInt(process.env.NEXT_PUBLIC_MAX_COLLECTION_TIME_MINUTES || '10')
  const maxSizeGB = parseInt(process.env.NEXT_PUBLIC_MAX_DATA_SIZE_GB || '5')

  const handleStart = useCallback(async () => {
    const res = await fetch('/api/start', { method: 'POST' })
    if (res.ok) {
      await refreshStatus()
    } else {
      const error = await res.json()
      // Refresh status even on error to sync UI with actual state
      await refreshStatus()
      alert(error.error || 'Failed to start collection')
    }
  }, [refreshStatus])

  const handleStop = useCallback(async () => {
    const res = await fetch('/api/stop', { method: 'POST' })
    if (res.ok) {
      await refreshStatus()
    } else {
      const error = await res.json()
      // Refresh status even on error to sync UI with actual state
      await refreshStatus()

      // Don't show error alert if:
      // 1. Collection not running (400 error)
      // 2. Auto-stop message is set (indicates auto-stop triggered this)
      const isAutoStop = autoStopMessage !== null
      const isNotRunning = res.status === 400 || error.error?.includes('not running')

      if (!isAutoStop && !isNotRunning) {
        alert(error.error || 'Failed to stop collection')
      }
    }
  }, [refreshStatus, autoStopMessage])

  // Get total_size_bytes directly
  const dataSizeBytes = status?.total_size_bytes || 0

  // Auto-stop when timer expires
  useEffect(() => {
    if (!status?.is_running || !status?.started_at) return

    const checkTimer = () => {
      if (!status.started_at) return

      const started = new Date(status.started_at).getTime()
      const now = Date.now()
      const elapsedMinutes = (now - started) / (1000 * 60)

      // VALIDATION: Only auto-stop if timestamp is valid and recent
      const isValidTimestamp = elapsedMinutes >= 0 && elapsedMinutes <= maxMinutes * 2

      if (!isValidTimestamp) {
        console.warn('Skipping auto-stop check: stale timestamp detected')
        return
      }

      if (elapsedMinutes >= maxMinutes) {
        // Timer expired, stop collection automatically
        // Set message before stopping to indicate auto-stop
        setAutoStopMessage('Collection stopped automatically (time limit reached)')
        handleStop()
      }
    }

    // Check immediately and then every 1 second for more responsive auto-stop
    checkTimer()
    const interval = setInterval(checkTimer, 1000)

    return () => clearInterval(interval)
  }, [status?.is_running, status?.started_at, maxMinutes, handleStop])

  if (statusLoading || dataLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-xl text-gray-600">Loading dashboard...</div>
      </div>
    )
  }

  if (statusError) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen gap-4">
        <div className="text-xl text-danger">Error connecting to collector service</div>
        <button
          onClick={() => window.location.reload()}
          className="px-4 py-2 bg-primary text-white rounded-md hover:bg-blue-700"
        >
          Retry
        </button>
      </div>
    )
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">
          Blockchain Data Ingestion Dashboard
        </h1>
        <p className="text-gray-600">
          Real-time monitoring and control for blockchain data collection
        </p>
      </div>

      {/* Control Panel */}
      <div className="bg-white rounded-lg shadow p-6 mb-6 border border-gray-200">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 items-center">
          <StatusCard isRunning={status?.is_running || false} />
          <CountdownTimer
            startedAt={status?.started_at || null}
            isRunning={status?.is_running || false}
            maxMinutes={maxMinutes}
          />
          <ControlButtons
            isRunning={status?.is_running || false}
            onStart={handleStart}
            onStop={handleStop}
          />
        </div>
      </div>

      {/* Auto-Stop Notification Banner */}
      {autoStopMessage && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
          <div className="flex items-center">
            <div className="text-green-600 mr-3 text-2xl">✓</div>
            <div className="flex-1">
              <p className="text-green-800 font-medium">{autoStopMessage}</p>
              <p className="text-green-600 text-sm mt-1">
                You can start a new collection session anytime.
              </p>
            </div>
            <button
              onClick={() => setAutoStopMessage(null)}
              className="ml-4 text-green-600 hover:text-green-800 text-2xl font-bold"
              aria-label="Dismiss notification"
            >
              ×
            </button>
          </div>
        </div>
      )}

      {/* Metrics Grid */}
      <div className="mb-6">
        <MetricsGrid
          totalRecords={data?.total_records || 0}
          dataSizeBytes={dataSizeBytes}
          recordsPerSecond={status?.records_per_second || 0}
          bitcoinBlocks={data?.bitcoin_blocks || 0}
          bitcoinTransactions={data?.bitcoin_transactions || 0}
          solanaBlocks={data?.solana_blocks || 0}
          solanaTransactions={data?.solana_transactions || 0}
        />
      </div>

      {/* Chart and Table */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <BlockchainChart
          bitcoinBlocks={data?.bitcoin_blocks || 0}
          bitcoinTransactions={data?.bitcoin_transactions || 0}
          solanaBlocks={data?.solana_blocks || 0}
          solanaTransactions={data?.solana_transactions || 0}
        />
        <DataTable
          bitcoinBlocks={data?.bitcoin_blocks || 0}
          bitcoinTransactions={data?.bitcoin_transactions || 0}
          solanaBlocks={data?.solana_blocks || 0}
          solanaTransactions={data?.solana_transactions || 0}
          totalRecords={data?.total_records || 0}
        />
      </div>

      {/* Data Preview Section */}
      <div className="mt-8 space-y-6">
        <h2 className="text-2xl font-bold text-gray-900">Data Preview</h2>
        <p className="text-gray-600 mb-4">
          Preview of the latest 550 records from each blockchain table (updates every 10 seconds)
        </p>

        {/* Bitcoin Blocks Preview */}
        <PreviewTable
          title="Bitcoin Blocks"
          data={bitcoinBlocks.data || []}
          columns={[
            { key: 'block_height', label: 'Height' },
            {
              key: 'block_hash',
              label: 'Block Hash',
              format: (val) => {
                const str = String(val || '')
                if (str.length <= 20) return str
                return `${str.slice(0, 12)}...${str.slice(-8)}`
              }
            },
            {
              key: 'timestamp',
              label: 'Timestamp',
              format: (val) => new Date(val).toLocaleString()
            },
            { key: 'transaction_count', label: 'Txs' },
            {
              key: 'difficulty',
              label: 'Difficulty',
              format: (val) => parseInt(val).toLocaleString()
            },
            {
              key: 'size',
              label: 'Size',
              format: (val) => `${(val / 1024).toFixed(2)} KB`
            },
          ]}
        />

        {/* Bitcoin Transactions Preview */}
        <PreviewTable
          title="Bitcoin Transactions"
          data={bitcoinTransactions.data || []}
          columns={[
            {
              key: 'tx_hash',
              label: 'Tx Hash',
              format: (val) => {
                const str = String(val || '')
                if (str.length <= 20) return str
                return `${str.slice(0, 12)}...${str.slice(-8)}`
              }
            },
            { key: 'block_height', label: 'Block' },
            {
              key: 'timestamp',
              label: 'Timestamp',
              format: (val) => new Date(val).toLocaleString()
            },
            {
              key: 'fee',
              label: 'Fee (sats)',
              format: (val) => parseInt(val).toLocaleString()
            },
            { key: 'input_count', label: 'Inputs' },
            { key: 'output_count', label: 'Outputs' },
          ]}
        />

        {/* Solana Blocks Preview */}
        <PreviewTable
          title="Solana Blocks"
          data={solanaBlocks.data || []}
          columns={[
            { key: 'slot', label: 'Slot' },
            { key: 'block_height', label: 'Height' },
            {
              key: 'block_hash',
              label: 'Block Hash',
              format: (val) => {
                const str = String(val || '')
                if (str.length <= 20) return str
                return `${str.slice(0, 12)}...${str.slice(-8)}`
              }
            },
            {
              key: 'timestamp',
              label: 'Timestamp',
              format: (val) => new Date(val).toLocaleString()
            },
            { key: 'parent_slot', label: 'Parent Slot' },
            { key: 'transaction_count', label: 'Txs' },
          ]}
        />

        {/* Solana Transactions Preview */}
        <PreviewTable
          title="Solana Transactions"
          data={solanaTransactions.data || []}
          columns={[
            {
              key: 'signature',
              label: 'Signature',
              format: (val) => {
                const str = String(val || '')
                if (str.length <= 20) return str
                return `${str.slice(0, 12)}...${str.slice(-8)}`
              }
            },
            { key: 'slot', label: 'Slot' },
            {
              key: 'timestamp',
              label: 'Timestamp',
              format: (val) => new Date(val).toLocaleString()
            },
            {
              key: 'fee',
              label: 'Fee (lamports)',
              format: (val) => parseInt(val).toLocaleString()
            },
            { key: 'status', label: 'Status' },
          ]}
        />
      </div>

      {/* Footer */}
      <div className="mt-8 text-center text-sm text-gray-500">
        <p>Auto-refreshes every 5 seconds</p>
        <p className="mt-1">
          Max collection time: {maxMinutes} minutes | Max data size:{' '}
          {maxSizeGB} GB
        </p>
      </div>
    </div>
  )
}
