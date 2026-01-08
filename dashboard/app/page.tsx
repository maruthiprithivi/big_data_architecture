'use client'

import { useEffect, useCallback } from 'react'
import { useCollectorStatus } from './hooks/useCollectorStatus'
import { useBlockchainData } from './hooks/useBlockchainData'
import StatusCard from './components/StatusCard'
import ControlButtons from './components/ControlButtons'
import CountdownTimer from './components/CountdownTimer'
import ProgressBar from './components/ProgressBar'
import MetricsGrid from './components/MetricsGrid'
import BlockchainChart from './components/BlockchainChart'
import DataTable from './components/DataTable'

export default function DashboardPage() {
  const { status, isLoading: statusLoading, isError: statusError, mutate: refreshStatus } = useCollectorStatus()
  const { data, isLoading: dataLoading, isError: dataError } = useBlockchainData()

  // Get max collection time from environment (fallback to 10 minutes)
  const maxMinutes = parseInt(process.env.NEXT_PUBLIC_MAX_COLLECTION_TIME_MINUTES || '10')
  const maxSizeGB = parseInt(process.env.NEXT_PUBLIC_MAX_DATA_SIZE_GB || '5')

  const handleStart = useCallback(async () => {
    const res = await fetch('/api/start', { method: 'POST' })
    if (res.ok) {
      await refreshStatus()
    } else {
      const error = await res.json()
      alert(error.error || 'Failed to start collection')
    }
  }, [refreshStatus])

  const handleStop = useCallback(async () => {
    const res = await fetch('/api/stop', { method: 'POST' })
    if (res.ok) {
      await refreshStatus()
    } else {
      const error = await res.json()
      alert(error.error || 'Failed to stop collection')
    }
  }, [refreshStatus])

  // Convert total_size_bytes to GB
  const dataSizeGB = status?.total_size_bytes ? status.total_size_bytes / (1024 * 1024 * 1024) : 0

  // Auto-stop when timer expires
  useEffect(() => {
    if (!status?.is_running || !status?.started_at) return

    const checkTimer = () => {
      if (!status.started_at) return

      const started = new Date(status.started_at).getTime()
      const now = Date.now()
      const elapsed = Math.floor((now - started) / 1000)
      const total = maxMinutes * 60

      if (elapsed >= total) {
        // Timer expired, stop collection automatically
        handleStop()
      }
    }

    // Check immediately and then every 5 seconds
    checkTimer()
    const interval = setInterval(checkTimer, 5000)

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

      {/* Progress Bar */}
      {status?.is_running && (
        <div className="bg-white rounded-lg shadow p-6 mb-6 border border-gray-200">
          <ProgressBar
            startedAt={status.started_at}
            isRunning={status.is_running}
            maxMinutes={maxMinutes}
          />
        </div>
      )}

      {/* Metrics Grid */}
      <div className="mb-6">
        <MetricsGrid
          totalRecords={data?.total_records || 0}
          dataSize={dataSizeGB}
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
