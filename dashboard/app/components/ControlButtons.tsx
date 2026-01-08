'use client'

import { useState } from 'react'

interface ControlButtonsProps {
  isRunning: boolean
  onStart: () => Promise<void>
  onStop: () => Promise<void>
}

export default function ControlButtons({
  isRunning,
  onStart,
  onStop,
}: ControlButtonsProps) {
  const [isStarting, setIsStarting] = useState(false)
  const [isStopping, setIsStopping] = useState(false)

  const handleStart = async () => {
    setIsStarting(true)
    try {
      await onStart()
    } finally {
      setIsStarting(false)
    }
  }

  const handleStop = async () => {
    setIsStopping(true)
    try {
      await onStop()
    } finally {
      setIsStopping(false)
    }
  }

  return (
    <div className="flex gap-3 justify-center md:justify-end">
      <button
        onClick={handleStart}
        disabled={isRunning || isStarting}
        aria-label="Start blockchain data collection"
        className="px-6 py-2 bg-green-600 text-white rounded-md font-medium hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
      >
        {isStarting ? 'Starting...' : 'Start Collection'}
      </button>
      <button
        onClick={handleStop}
        disabled={!isRunning || isStopping}
        aria-label="Stop blockchain data collection"
        className="px-6 py-2 bg-red-600 text-white rounded-md font-medium hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
      >
        {isStopping ? 'Stopping...' : 'Stop Collection'}
      </button>
    </div>
  )
}
