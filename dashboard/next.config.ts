import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
  // Environment variables that need to be available in the browser
  // Leave empty - we'll use API routes to keep secrets server-side
  env: {},
  // Disable aggressive caching during development to prevent browser cache issues
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'no-cache, no-store, must-revalidate',
          },
          {
            key: 'Pragma',
            value: 'no-cache',
          },
          {
            key: 'Expires',
            value: '0',
          },
        ],
      },
    ]
  },
}

export default nextConfig
