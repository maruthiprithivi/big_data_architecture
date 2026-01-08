'use client'

interface StatusCardProps {
  isRunning: boolean
}

export default function StatusCard({ isRunning }: StatusCardProps) {
  return (
    <div className="flex items-center gap-3">
      <div
        className={`w-3 h-3 rounded-full ${isRunning ? 'bg-success animate-pulse' : 'bg-gray-400'}`}
      />
      <div>
        <div className="text-sm text-gray-500">Status</div>
        <div
          className={`text-lg font-bold ${isRunning ? 'text-success' : 'text-gray-700'}`}
        >
          {isRunning ? 'Running' : 'Stopped'}
        </div>
      </div>
    </div>
  )
}
