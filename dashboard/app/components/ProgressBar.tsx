'use client'

import { useMemo } from 'react'
import { getElapsedSeconds, getTimerColor } from '@/app/lib/utils'

interface ProgressBarProps {
  startedAt: string | null
  isRunning: boolean
  maxMinutes: number
}

export default function ProgressBar({
  startedAt,
  isRunning,
  maxMinutes,
}: ProgressBarProps) {
  const progress = useMemo(() => {
    if (!startedAt || !isRunning) return 0

    const elapsedSeconds = getElapsedSeconds(startedAt)
    const totalSeconds = maxMinutes * 60
    const percentage = Math.min(100, (elapsedSeconds / totalSeconds) * 100)

    return Math.round(percentage)
  }, [startedAt, isRunning, maxMinutes])

  const secondsRemaining = useMemo(() => {
    if (!startedAt || !isRunning) return 0

    const elapsed = getElapsedSeconds(startedAt)
    const total = maxMinutes * 60
    return Math.max(0, total - elapsed)
  }, [startedAt, isRunning, maxMinutes])

  const colorClass = getTimerColor(secondsRemaining)

  return (
    <div className="w-full">
      <div className="flex justify-between items-center mb-2">
        <span className="text-sm font-medium text-gray-700">
          Collection Progress
        </span>
        <span className={`text-sm font-bold ${colorClass}`}>{progress}%</span>
      </div>
      <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
        <div
          className={`h-full transition-all duration-500 ease-linear ${
            colorClass === 'text-success'
              ? 'bg-success'
              : colorClass === 'text-warning'
                ? 'bg-warning'
                : 'bg-danger'
          }`}
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  )
}
