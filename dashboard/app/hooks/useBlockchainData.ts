'use client'

import useSWR from 'swr'
import type { MetricsData } from '@/app/lib/types'

const fetcher = (url: string) => fetch(url).then((res) => res.json())

export function useBlockchainData() {
  const { data, error, mutate, isLoading } = useSWR<MetricsData>(
    '/api/data',
    fetcher,
    {
      refreshInterval: 5000, // Refresh every 5 seconds
      revalidateOnFocus: true,
      revalidateOnReconnect: true,
      dedupingInterval: 2000,
    }
  )

  return {
    data,
    isLoading,
    isError: error,
    mutate,
  }
}
