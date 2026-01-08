import { NextResponse } from 'next/server'

export async function POST() {
  try {
    const collectorUrl = process.env.COLLECTOR_URL || 'http://collector:8000'

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 5000)

    const res = await fetch(`${collectorUrl}/start`, {
      method: 'POST',
      cache: 'no-store',
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    const data = await res.json()

    if (!res.ok) {
      return NextResponse.json(
        { error: data.detail || 'Failed to start collection' },
        { status: res.status }
      )
    }

    return NextResponse.json(data)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    console.error('API /start error:', errorMessage)

    return NextResponse.json(
      { error: `Failed to start collection: ${errorMessage}` },
      { status: 500 }
    )
  }
}
