import { NextResponse } from 'next/server'

export async function GET() {
  try {
    const collectorUrl = process.env.COLLECTOR_URL || 'http://collector:8000'

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 5000)

    const res = await fetch(`${collectorUrl}/status`, {
      cache: 'no-store',
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!res.ok) {
      return NextResponse.json(
        { error: 'Collector service unavailable', status: res.status },
        { status: 503 }
      )
    }

    const data = await res.json()
    return NextResponse.json(data)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    console.error('API /status error:', errorMessage)

    return NextResponse.json(
      { error: `Failed to connect to collector: ${errorMessage}` },
      { status: 500 }
    )
  }
}
