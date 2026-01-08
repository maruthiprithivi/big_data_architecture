'use client'

import useSWR from 'swr'
import type { CollectorStatus } from '@/app/lib/types'

const fetcher = (url: string) => fetch(url).then((res) => res.json())

export function useCollectorStatus() {
  const { data, error, mutate, isLoading } = useSWR<CollectorStatus>(
    '/api/status',
    fetcher,
    {
      refreshInterval: 5000, // Refresh every 5 seconds
      revalidateOnFocus: true,
      revalidateOnReconnect: true,
      dedupingInterval: 2000, // Prevent duplicate requests within 2 seconds
    }
  )

  return {
    status: data,
    isLoading,
    isError: error,
    mutate, // Manually trigger a refresh
  }
}
