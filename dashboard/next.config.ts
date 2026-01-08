import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
  // Environment variables that need to be available in the browser
  // Leave empty - we'll use API routes to keep secrets server-side
  env: {},
}

export default nextConfig
