/**
 * Format a number with comma separators or abbreviations for large values
 */
export function formatNumber(value: number): string {
  if (value === null || value === undefined || isNaN(value)) {
    return '0'
  }

  // For numbers >= 1 billion
  if (value >= 1_000_000_000) {
    return `${(value / 1_000_000_000).toFixed(2)}B`
  }

  // For numbers >= 1 million
  if (value >= 1_000_000) {
    return `${(value / 1_000_000).toFixed(2)}M`
  }

  // For numbers >= 1 thousand
  if (value >= 1_000) {
    return `${(value / 1_000).toFixed(2)}K`
  }

  // For smaller numbers, use comma separators
  return value.toLocaleString('en-US')
}

/**
 * Format bytes into human-readable data size (B, KB, MB, GB, TB)
 */
export function formatDataSize(bytes: number): string {
  if (bytes === null || bytes === undefined || isNaN(bytes) || bytes === 0) {
    return '0 B'
  }

  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const k = 1024
  const i = Math.floor(Math.log(Math.abs(bytes)) / Math.log(k))

  if (i === 0) {
    return `${bytes} B`
  }

  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`
}

/**
 * Format seconds into MM:SS or HH:MM:SS format
 */
export function formatTime(seconds: number): string {
  if (seconds === null || seconds === undefined || isNaN(seconds) || seconds < 0) {
    return '00:00'
  }

  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const secs = Math.floor(seconds % 60)

  // If less than an hour, return MM:SS
  if (hours === 0) {
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
  }

  // Otherwise return HH:MM:SS
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
}

/**
 * Get CSS color class based on time remaining thresholds
 */
export function getTimerColor(seconds: number): string {
  if (seconds === null || seconds === undefined || isNaN(seconds)) {
    return 'text-gray-400'
  }

  // Green for more than 5 minutes
  if (seconds > 300) {
    return 'text-success'
  }

  // Yellow/warning for 1-5 minutes
  if (seconds > 60) {
    return 'text-warning'
  }

  // Red/danger for less than 1 minute
  return 'text-danger'
}

/**
 * Calculate elapsed seconds from an ISO timestamp to now
 */
export function getElapsedSeconds(startedAt: string): number {
  if (!startedAt) {
    return 0
  }

  try {
    // Normalize timestamp: replace space with 'T' for ISO 8601 format
    const normalizedTimestamp = startedAt.replace(' ', 'T')
    const started = new Date(normalizedTimestamp).getTime()

    // Check if date is valid
    if (isNaN(started)) {
      return 0
    }

    const now = Date.now()
    const elapsedMs = now - started

    // Return 0 if timestamp is in the future
    if (elapsedMs < 0) {
      return 0
    }

    return Math.floor(elapsedMs / 1000)
  } catch (error) {
    return 0
  }
}
