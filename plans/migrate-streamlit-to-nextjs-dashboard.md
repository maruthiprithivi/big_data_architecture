# Migration Plan: Streamlit to Next.js Containerized Dashboard

## Overview

Replace the current Streamlit-based dashboard with a modern, containerized Next.js application that provides an intuitive interface for monitoring blockchain data collection. The new dashboard will feature a countdown timer, comprehensive stats display, and professional UI while maintaining all current functionality.

## Problem Statement

The current Streamlit dashboard (`dashboard/app.py`) serves its purpose but has limitations for a production-ready educational platform:

- **Technology Stack Mismatch**: Python-based UI when the industry standard for modern dashboards is JavaScript/TypeScript
- **Limited Customization**: Streamlit's opinionated design constrains UI/UX improvements
- **Performance Concerns**: Full-page reruns every 5 seconds are inefficient
- **Scalability**: Not optimized for multiple concurrent users
- **Modern UI Expectations**: Users expect React-based interactive dashboards with smooth real-time updates

## Proposed Solution

Build a Next.js 15 containerized dashboard using the App Router architecture, Server Components for data fetching, and Client Components for interactivity. Deploy in a lightweight Docker container (targeting <120MB) using multi-stage builds and standalone output mode.

### Core Architecture

```
Browser
   ↓
Next.js Dashboard (Port 3000)
   ↓ (API calls via Next.js API routes)
FastAPI Collector (Port 8000)
   ↓
ClickHouse Database (Port 8123)
```

### Technology Stack

- **Framework**: Next.js 15 (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS + shadcn/ui components
- **Charts**: Recharts (lightweight, React-native)
- **State Management**: React Context API + Server Components
- **Real-Time Updates**: Client-side polling with SWR (5-second interval)
- **Container**: Node.js 22 Alpine (multi-stage build)
- **Package Manager**: npm

## Technical Approach

### 1. Project Structure

```
dashboard/
├── app/
│   ├── layout.tsx                    # Root layout with providers
│   ├── page.tsx                      # Main dashboard (Server Component)
│   ├── components/
│   │   ├── StatusCard.tsx            # Collection status display (Client)
│   │   ├── MetricsGrid.tsx           # 4-column metrics display (Client)
│   │   ├── CountdownTimer.tsx        # Time remaining timer (Client)
│   │   ├── ProgressBar.tsx           # Collection progress (Client)
│   │   ├── ControlButtons.tsx        # Start/Stop buttons (Client)
│   │   ├── BlockchainChart.tsx       # Records by source chart (Client)
│   │   ├── DataTable.tsx             # Interactive data table (Client)
│   │   └── ErrorBoundary.tsx         # Error handling wrapper
│   ├── api/
│   │   ├── status/route.ts           # Proxy to collector /status
│   │   ├── start/route.ts            # Proxy to collector /start
│   │   ├── stop/route.ts             # Proxy to collector /stop
│   │   └── data/route.ts             # ClickHouse data queries
│   ├── lib/
│   │   ├── clickhouse.ts             # ClickHouse client setup
│   │   ├── types.ts                  # TypeScript interfaces
│   │   └── utils.ts                  # Utility functions
│   └── hooks/
│       ├── useCollectorStatus.ts     # SWR hook for /status polling
│       └── useBlockchainData.ts      # SWR hook for chart data
├── public/
│   └── logo.png                      # Dashboard branding
├── Dockerfile                        # Multi-stage production build
├── next.config.js                    # Next.js configuration (standalone mode)
├── tailwind.config.ts                # Tailwind CSS configuration
├── tsconfig.json                     # TypeScript configuration
└── package.json                      # Dependencies
```

### 2. Server Components vs Client Components

**Server Components** (data fetching, no interactivity):
- `app/page.tsx` - Main dashboard page, fetches initial data
- `app/api/*` - API route handlers (proxy to collector/ClickHouse)

**Client Components** ('use client' directive):
- All interactive UI: buttons, charts, timers, real-time updates
- Components using React hooks (useState, useEffect, SWR)
- Chart components (Recharts requires browser DOM)

**Pattern**: Server Components fetch data at page load, pass to Client Components for interactivity and real-time updates.

### 3. Real-Time Update Strategy

**Chosen Approach**: Client-side polling with SWR library

**Rationale**:
- Simplest to implement and debug
- No WebSocket infrastructure required
- Auto-revalidation on window focus
- Built-in caching and deduplication
- 5-second interval matches current Streamlit behavior

**Implementation**:

```typescript
// hooks/useCollectorStatus.ts
'use client'

import useSWR from 'swr'

const fetcher = (url: string) => fetch(url).then(res => res.json())

export function useCollectorStatus() {
  const { data, error, mutate } = useSWR('/api/status', fetcher, {
    refreshInterval: 5000, // 5 seconds
    revalidateOnFocus: true,
    revalidateOnReconnect: true,
  })

  return {
    status: data,
    isLoading: !data && !error,
    isError: error,
    refresh: mutate,
  }
}
```

### 4. Data Access Pattern

**Chosen Approach**: Hybrid - API routes proxy to collector, direct ClickHouse for analytics

**Rationale**:
- Collector API handles Start/Stop operations (business logic)
- ClickHouse queries for read-only analytics (performance)
- Next.js API routes provide single endpoint for frontend
- Environment variables stay secure on server-side

**Example API Route**:

```typescript
// app/api/status/route.ts
export async function GET() {
  try {
    const collectorUrl = process.env.COLLECTOR_URL || 'http://collector:8000'
    const res = await fetch(`${collectorUrl}/status`, {
      cache: 'no-store',
      signal: AbortSignal.timeout(5000), // 5-second timeout
    })

    if (!res.ok) {
      return Response.json(
        { error: 'Collector service unavailable' },
        { status: 503 }
      )
    }

    const data = await res.json()
    return Response.json(data)
  } catch (error) {
    return Response.json(
      { error: error.message },
      { status: 500 }
    )
  }
}
```

### 5. Countdown Timer Implementation

**Requirements**:
- Display time remaining until MAX_COLLECTION_TIME_MINUTES limit (10 minutes)
- Format: MM:SS (e.g., "09:45", "02:30")
- Update every second (smooth countdown, not 5-second jumps)
- Color-coded warnings:
  - Green: > 5 minutes remaining
  - Yellow: 2-5 minutes remaining
  - Red: < 2 minutes remaining
- Show elapsed time if collection stopped

**Implementation**:

```typescript
// components/CountdownTimer.tsx
'use client'

import { useState, useEffect } from 'react'

interface CountdownTimerProps {
  startedAt: string | null
  isRunning: boolean
  maxMinutes: number
}

export default function CountdownTimer({ startedAt, isRunning, maxMinutes }: CountdownTimerProps) {
  const [secondsRemaining, setSecondsRemaining] = useState<number>(0)

  useEffect(() => {
    if (!startedAt || !isRunning) {
      setSecondsRemaining(0)
      return
    }

    const calculateRemaining = () => {
      const started = new Date(startedAt).getTime()
      const now = Date.now()
      const elapsed = Math.floor((now - started) / 1000)
      const total = maxMinutes * 60
      return Math.max(0, total - elapsed)
    }

    setSecondsRemaining(calculateRemaining())

    const interval = setInterval(() => {
      setSecondsRemaining(calculateRemaining())
    }, 1000)

    return () => clearInterval(interval)
  }, [startedAt, isRunning, maxMinutes])

  const minutes = Math.floor(secondsRemaining / 60)
  const seconds = secondsRemaining % 60
  const formatted = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`

  const colorClass =
    secondsRemaining > 300 ? 'text-green-600' :
    secondsRemaining > 120 ? 'text-yellow-600' :
    'text-red-600'

  return (
    <div className="text-center">
      <div className={`text-4xl font-mono font-bold ${colorClass}`}>
        {formatted}
      </div>
      <div className="text-sm text-gray-500 mt-1">
        Time Remaining
      </div>
    </div>
  )
}
```

### 6. Comprehensive Stats Display

**Stats Included** (beyond current Streamlit):

1. **Collection Status** (Running/Stopped) - with color indicator
2. **Total Records** - formatted with commas (e.g., "1,234,567")
3. **Data Size** - in GB or MB with 2 decimal precision
4. **Time Remaining** - countdown timer (see above)
5. **Progress Bar** - percentage of max time used (0-100%)
6. **Collection Rate** - records/second (NEW)
7. **Per-Blockchain Breakdown** - 4 separate cards:
   - Bitcoin Blocks (count + percentage)
   - Bitcoin Transactions (count + percentage)
   - Solana Blocks (count + percentage)
   - Solana Transactions (count + percentage)
8. **Last Updated** - timestamp showing data freshness (NEW)
9. **Estimated Time to Size Limit** - based on current growth rate (NEW)

**Layout**: 4-column grid on desktop, stacked on mobile

### 7. Docker Containerization

**Multi-Stage Dockerfile**:

```dockerfile
# Stage 1: Dependencies
FROM node:22-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

# Stage 2: Builder
FROM node:22-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Enable standalone output for smallest container
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# Stage 3: Runner (Production)
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy standalone output
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

CMD ["node", "server.js"]
```

**Expected Image Size**: 80-120MB (vs. ~800MB standard Next.js build)

### 8. Docker Compose Integration

**Changes to docker-compose.yml**:

```yaml
services:
  clickhouse:
    # ... (no changes)

  collector:
    # ... (no changes)

  dashboard:
    build:
      context: ./dashboard
      dockerfile: Dockerfile
    container_name: blockchain-dashboard
    environment:
      - NODE_ENV=production
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=8123
      - CLICKHOUSE_USER=${CLICKHOUSE_USER}
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DB=${CLICKHOUSE_DB}
      - COLLECTOR_URL=http://collector:8000
      - MAX_COLLECTION_TIME_MINUTES=${MAX_COLLECTION_TIME_MINUTES:-10}
      - MAX_DATA_SIZE_GB=${MAX_DATA_SIZE_GB:-5}
    ports:
      - "3000:3000"  # Changed from 8501
    depends_on:
      - clickhouse
      - collector
    networks:
      - blockchain-network
    restart: unless-stopped
```

### 9. Environment Variables

**Required Variables** (all server-side, not exposed to browser):

```env
# ClickHouse Connection
CLICKHOUSE_HOST=clickhouse
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=your_password
CLICKHOUSE_DB=blockchain_data

# Collector Service
COLLECTOR_URL=http://collector:8000

# Collection Limits
MAX_COLLECTION_TIME_MINUTES=10
MAX_DATA_SIZE_GB=5

# Next.js
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
```

**No NEXT_PUBLIC_* variables needed** - all API calls go through Next.js API routes (server-side).

### 10. Error Handling Strategy

**Error Types**:
1. **Network Errors**: Collector/ClickHouse unreachable
2. **API Errors**: 4xx/5xx responses
3. **Timeout Errors**: Request exceeds 5 seconds
4. **Validation Errors**: Malformed API responses

**Handling Approach**:
- **Toast Notifications**: Non-blocking errors (network hiccups)
- **Error Boundary**: Component-level failures
- **Graceful Degradation**: Show cached data + warning banner
- **Retry Logic**: Automatic retry with exponential backoff (via SWR)
- **User Actions**: "Retry" button for failed requests

**Example**:

```typescript
// components/ErrorBoundary.tsx
'use client'

import { useEffect } from 'react'

export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('Dashboard error:', error)
  }, [error])

  return (
    <div className="flex flex-col items-center justify-center min-h-screen p-4">
      <h2 className="text-2xl font-bold text-red-600 mb-4">
        Dashboard Error
      </h2>
      <p className="text-gray-600 mb-4">{error.message}</p>
      <button
        onClick={reset}
        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
      >
        Retry
      </button>
    </div>
  )
}
```

### 11. UI/UX Design

**Design System**: shadcn/ui + Tailwind CSS

**Color Palette**:
- **Primary**: Blue (#3B82F6) for actions, links
- **Success**: Green (#10B981) for running status, >5min timer
- **Warning**: Yellow (#F59E0B) for 2-5min timer
- **Danger**: Red (#EF4444) for <2min timer, errors
- **Bitcoin**: Orange (#F7931A) for Bitcoin data
- **Solana**: Green (#14F195) and Purple (#9945FF) for Solana data
- **Background**: White (#FFFFFF) / Dark (#111827) for dark mode
- **Text**: Gray scale (#111827 to #F9FAFB)

**Typography**:
- **Font**: Inter (sans-serif) for UI, JetBrains Mono for timer/code
- **Sizes**: text-sm (14px), text-base (16px), text-lg (18px), text-4xl (36px) for timer

**Layout**:
- **Desktop (≥1024px)**: 4-column grid for metrics, side-by-side chart + table
- **Tablet (768-1023px)**: 2-column grid, stacked chart then table
- **Mobile (<768px)**: Single column, all stacked

**Components**:
- **Card**: White background, subtle shadow, rounded corners (8px)
- **Button**: Solid primary color, white text, hover state, disabled state
- **Progress Bar**: Thin (8px height), color-coded like timer
- **Table**: Striped rows, hover effect, sticky header
- **Chart**: Responsive container, legend, tooltips on hover

**Animations**:
- **Fade In**: Page load, card entrance
- **Pulse**: Loading states
- **Smooth Transitions**: Color changes, hover states (200ms ease)
- **No motion**: Respect `prefers-reduced-motion` for accessibility

### 12. Accessibility (WCAG 2.1 AA)

**Requirements**:
- All interactive elements keyboard-accessible (Tab navigation)
- Focus indicators visible (2px blue outline)
- Color contrast ratios ≥4.5:1 for text
- ARIA labels on all buttons and icons
- Alt text for charts (describe data trends)
- Semantic HTML (header, main, section, nav)
- Screen reader announcements for status changes
- No auto-playing audio/video

**Implementation**:
```tsx
<button
  onClick={handleStart}
  disabled={isRunning}
  aria-label="Start blockchain data collection"
  className="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50"
>
  Start Collection
</button>
```

## Implementation Phases

### Phase 1: Project Setup & Core Infrastructure (Week 1)

**Tasks**:
- [x] Create new `dashboard` directory (replace existing Streamlit)
- [x] Initialize Next.js 15 project with TypeScript
- [x] Install dependencies: SWR, Recharts, Tailwind, shadcn/ui
- [x] Configure next.config.js with standalone output
- [x] Set up TypeScript interfaces for API responses
- [x] Create Docker multi-stage Dockerfile
- [x] Update docker-compose.yml with new dashboard service
- [x] Configure Tailwind CSS with custom colors (blockchain brands)
- [x] Set up environment variable loading

**Success Criteria**:
- Next.js app runs locally on port 3000
- Docker build succeeds, image size <150MB
- Environment variables load correctly
- TypeScript compilation with no errors

**Files to Create**:
- `dashboard/next.config.js`
- `dashboard/tsconfig.json`
- `dashboard/tailwind.config.ts`
- `dashboard/Dockerfile`
- `dashboard/package.json`
- `dashboard/app/layout.tsx`
- `dashboard/app/page.tsx`
- `dashboard/app/lib/types.ts`

### Phase 2: API Integration & Data Fetching (Week 1-2)

**Tasks**:
- [x] Implement Next.js API routes (status, start, stop, data)
- [x] Set up ClickHouse client in `lib/clickhouse.ts`
- [x] Create SWR hooks for real-time polling
- [x] Implement error handling and retry logic
- [x] Add request timeout (5 seconds)
- [x] Validate API response schemas with Zod
- [x] Test API routes with collector service
- [x] Handle CORS if needed

**Success Criteria**:
- `/api/status` returns collector status
- `/api/start` and `/api/stop` trigger collection
- `/api/data` queries ClickHouse successfully
- SWR auto-refreshes every 5 seconds
- Errors display user-friendly messages

**Files to Create**:
- `dashboard/app/api/status/route.ts`
- `dashboard/app/api/start/route.ts`
- `dashboard/app/api/stop/route.ts`
- `dashboard/app/api/data/route.ts`
- `dashboard/app/lib/clickhouse.ts`
- `dashboard/app/hooks/useCollectorStatus.ts`
- `dashboard/app/hooks/useBlockchainData.ts`

### Phase 3: Core UI Components (Week 2)

**Tasks**:
- [x] Build StatusCard component (Running/Stopped indicator)
- [x] Build MetricsGrid component (4-column layout)
- [x] Build ControlButtons component (Start/Stop)
- [x] Build CountdownTimer component (MM:SS format, color-coded)
- [x] Build ProgressBar component (% of max time)
- [x] Add responsive breakpoints (mobile, tablet, desktop)
- [x] Implement loading skeletons
- [x] Add error boundary wrapper

**Success Criteria**:
- All components render without errors
- Status updates in real-time (5-second polling)
- Countdown timer ticks every second
- Buttons trigger start/stop actions
- Responsive on all screen sizes

**Files to Create**:
- `dashboard/app/components/StatusCard.tsx`
- `dashboard/app/components/MetricsGrid.tsx`
- `dashboard/app/components/ControlButtons.tsx`
- `dashboard/app/components/CountdownTimer.tsx`
- `dashboard/app/components/ProgressBar.tsx`
- `dashboard/app/components/LoadingSkeleton.tsx`
- `dashboard/app/components/ErrorBoundary.tsx`

### Phase 4: Data Visualizations (Week 2-3)

**Tasks**:
- [x] Integrate Recharts library
- [x] Build BlockchainChart component (bar chart, records by source)
- [x] Build DataTable component (interactive table)
- [x] Apply blockchain brand colors (Bitcoin orange, Solana green/purple)
- [x] Add chart tooltips and legends
- [x] Make charts responsive (ResponsiveContainer)
- [x] Handle empty state (no data collected)
- [x] Add thousand-separator formatting

**Success Criteria**:
- Chart displays records by blockchain source
- Colors match current Streamlit (Bitcoin: #F7931A, Solana: #14F195/#9945FF)
- Table shows counts with proper formatting
- Charts and table update every 5 seconds
- Mobile-friendly (stacked layout)

**Files to Create**:
- `dashboard/app/components/BlockchainChart.tsx`
- `dashboard/app/components/DataTable.tsx`
- `dashboard/app/lib/utils.ts` (formatting helpers)

### Phase 5: Comprehensive Stats & Polish (Week 3)

**Tasks**:
- [x] Add collection rate calculation (records/second)
- [x] Add per-blockchain breakdown cards
- [x] Add "Last Updated" timestamp
- [x] Add estimated time to size limit
- [x] Implement toast notifications (success/error)
- [x] Add smooth animations and transitions
- [x] Optimize performance (memoization, code splitting)
- [x] Add dark mode support (optional)
- [x] Accessibility audit (WCAG 2.1 AA)
- [x] Cross-browser testing (Chrome, Firefox, Safari, Edge)

**Success Criteria**:
- All 9 stat categories display correctly
- Per-blockchain cards show percentages
- Toast notifications appear for actions
- Animations smooth (60fps)
- Lighthouse score ≥90 (Performance, Accessibility)
- Works on all major browsers

**Files to Create**:
- `dashboard/app/components/CollectionRate.tsx`
- `dashboard/app/components/BlockchainBreakdown.tsx`
- `dashboard/app/components/ToastNotification.tsx`
- `dashboard/app/components/LastUpdated.tsx`

### Phase 6: Documentation & Deployment (Week 3-4)

**Tasks**:
- [x] Update README.md with Next.js setup instructions
- [x] Update architecture diagram (replace Streamlit with Next.js)
- [x] Update technology stack table
- [x] Document environment variables
- [x] Update start.sh script (port 3000 instead of 8501)
- [x] Add troubleshooting section for Next.js
- [x] Test full Docker Compose deployment
- [x] Create migration guide (Streamlit → Next.js)
- [x] Archive old Streamlit code in `archive/streamlit-dashboard/`

**Success Criteria**:
- README accurately reflects new architecture
- start.sh outputs correct URLs
- Docker Compose `up` succeeds
- All three services (clickhouse, collector, dashboard) healthy
- Documentation clear for new users

**Files to Update**:
- `README.md` (dashboard section, architecture diagram)
- `start.sh` (port and service name)
- `docker-compose.yml` (verified working)
- `EXERCISES.md` (if references to Streamlit UI)

**Files to Create**:
- `archive/streamlit-dashboard/` (move old dashboard/ contents)
- `docs/MIGRATION.md` (Streamlit to Next.js migration notes)

### Phase 7: Testing & Validation (Week 4)

**Tasks**:
- [x] Unit tests for utility functions (formatting, calculations)
- [x] Component tests with React Testing Library
- [x] Integration tests for API routes
- [x] E2E tests for critical flows (start, stop, monitoring)
- [x] Load testing (multiple concurrent users)
- [x] Performance testing (bundle size, load time)
- [x] Accessibility testing (axe-core, manual keyboard nav)
- [x] Cross-device testing (desktop, tablet, mobile)
- [x] User acceptance testing (compare with Streamlit)

**Success Criteria**:
- Test coverage ≥80% for critical code
- All E2E tests pass
- No console errors or warnings
- Load time <2 seconds on 3G
- Bundle size <500KB (gzipped)
- Works on iOS Safari, Android Chrome

**Files to Create**:
- `dashboard/__tests__/utils.test.ts`
- `dashboard/__tests__/components/CountdownTimer.test.tsx`
- `dashboard/__tests__/api/status.test.ts`
- `dashboard/playwright.config.ts` (E2E tests)

## Acceptance Criteria

### Functional Requirements

- [ ] Dashboard loads successfully on port 3000
- [ ] "Start Collection" button initiates data collection via collector API
- [ ] "Stop Collection" button halts data collection via collector API
- [ ] Collection status displays correctly (Running/Stopped) with color indicator
- [ ] Total records count updates every 5 seconds
- [ ] Data size (GB/MB) displays with 2 decimal precision
- [ ] Countdown timer shows MM:SS format, ticks every second
- [ ] Countdown timer color-coded (green >5min, yellow 2-5min, red <2min)
- [ ] Progress bar shows percentage of max time used (0-100%)
- [ ] Bar chart displays records by blockchain source (Bitcoin, Solana)
- [ ] Chart uses correct colors (Bitcoin: #F7931A, Solana: #14F195/#9945FF)
- [ ] Data table shows record counts with thousand separators
- [ ] Auto-refresh every 5 seconds (SWR polling)
- [ ] Collection auto-stops at 10-minute limit
- [ ] Collection auto-stops at 5GB data size limit
- [ ] Error messages display when collector/database unavailable
- [ ] Start button disabled when collection already running
- [ ] Stop button disabled when collection not running
- [ ] Comprehensive stats display (9 categories):
  - Collection status
  - Total records
  - Data size
  - Time remaining
  - Progress bar
  - Collection rate (records/second)
  - Per-blockchain breakdown (4 cards)
  - Last updated timestamp
  - Estimated time to size limit

### Non-Functional Requirements

- [ ] Docker image size <150MB (target: 80-120MB)
- [ ] Page load time <2 seconds on 3G connection
- [ ] Bundle size <500KB gzipped
- [ ] Lighthouse Performance score ≥90
- [ ] Lighthouse Accessibility score ≥90
- [ ] WCAG 2.1 AA compliance (color contrast, keyboard nav, ARIA labels)
- [ ] Responsive on mobile (375px), tablet (768px), desktop (1024px+)
- [ ] Works on Chrome, Firefox, Safari, Edge (latest versions)
- [ ] TypeScript with no errors/warnings
- [ ] No console errors in production build
- [ ] Handles concurrent users (at least 10 simultaneous)
- [ ] Graceful error handling (network failures, API errors)
- [ ] Test coverage ≥80% for critical code

### Quality Gates

- [ ] Code reviewed (if team environment)
- [ ] All tests passing (unit, integration, E2E)
- [ ] Documentation complete and accurate
- [ ] No security vulnerabilities (npm audit)
- [ ] Accessibility audit passed (axe-core)
- [ ] Cross-browser testing complete
- [ ] User acceptance testing complete (feature parity with Streamlit)

## Dependencies & Risks

### External Dependencies

1. **FastAPI Collector Service** (collector:8000)
   - Risk: API contract changes could break integration
   - Mitigation: Document API interfaces with TypeScript types, version control

2. **ClickHouse Database** (clickhouse:8123)
   - Risk: Schema changes could break queries
   - Mitigation: Use parameterized queries, type validation

3. **Docker & Docker Compose**
   - Risk: Version incompatibilities across environments
   - Mitigation: Document required versions in README

4. **Node.js Runtime**
   - Risk: Node version mismatches (local vs. container)
   - Mitigation: Use .nvmrc file, specify exact version in Dockerfile

### Technical Risks

1. **Bundle Size Bloat**
   - Risk: Recharts and dependencies could exceed 500KB target
   - Mitigation: Use tree-shaking, code splitting, analyze bundle with @next/bundle-analyzer

2. **Real-Time Performance**
   - Risk: 10 concurrent users polling every 5 seconds = 120 requests/minute
   - Mitigation: Implement request deduplication with SWR, consider rate limiting

3. **Clock Skew**
   - Risk: Client and server time drift could show incorrect countdown
   - Mitigation: Calculate time remaining server-side, client only displays

4. **State Management Complexity**
   - Risk: Multiple components needing shared state (status, metrics, timer)
   - Mitigation: Use React Context for global state, SWR for data fetching

### Resource Requirements

1. **Development Time**: 3-4 weeks (1 developer)
2. **Server Resources**: Same as current Streamlit (minimal impact)
3. **Build Time**: ~2-3 minutes for Docker multi-stage build
4. **Runtime Memory**: ~50-100MB (vs. ~150MB for Streamlit)

## Success Metrics

### Performance Metrics

- **Initial Load Time**: <2 seconds (Streamlit baseline: ~3 seconds)
- **Time to Interactive**: <3 seconds
- **Bundle Size**: <500KB gzipped (Streamlit N/A)
- **Docker Image Size**: <120MB (Streamlit baseline: ~180MB)
- **API Response Time**: <200ms for /status endpoint
- **Chart Render Time**: <100ms

### User Experience Metrics

- **Error Rate**: <1% of requests fail
- **User Satisfaction**: Positive feedback on UI/UX (survey after migration)
- **Task Completion**: 100% of current Streamlit features replicated
- **Accessibility**: WCAG 2.1 AA compliance (0 critical issues)

### Educational Value Metrics

- **Feature Parity**: All current Streamlit features present
- **Enhanced Stats**: 3 new metrics beyond current (rate, breakdown, estimate)
- **Code Clarity**: TypeScript provides better student code examples
- **Documentation**: Updated docs reflect modern web development practices

## Rollback Plan

If critical issues arise during deployment:

1. **Immediate Rollback** (< 5 minutes):
   - Revert docker-compose.yml to use old Streamlit service
   - Restart containers: `docker compose down && docker compose up -d`
   - Verify Streamlit dashboard accessible on port 8501

2. **Preserve Old Streamlit Code**:
   - Move current dashboard/ to archive/streamlit-dashboard/ before replacement
   - Keep in Git history with tag `v1.0-streamlit`

3. **Rollback Triggers**:
   - Dashboard completely unavailable (connection refused, 500 errors)
   - Critical feature missing (cannot start/stop collection)
   - Data corruption or loss
   - Persistent errors affecting educational use

## Future Considerations

### Phase 2 Enhancements (Post-Migration)

1. **Authentication & Authorization**
   - User login (NextAuth.js)
   - Role-based access (Admin, Viewer)
   - Audit logging (who started/stopped collection)

2. **Advanced Features**
   - Data export (CSV, JSON, PNG charts)
   - Historical runs comparison
   - Custom date range filtering
   - Advanced ClickHouse query builder

3. **Performance Optimizations**
   - WebSocket for true real-time updates
   - Server-Sent Events (SSE) as alternative
   - Redis caching layer
   - GraphQL API (instead of REST)

4. **Educational Enhancements**
   - Interactive tutorials (first-time user onboarding)
   - 5Vs framework visibility in UI
   - Glossary tooltips for technical terms
   - Sample data mode (pre-populated demo)

5. **Monitoring & Observability**
   - Application Performance Monitoring (APM)
   - Error tracking (Sentry)
   - Analytics (dashboard usage patterns)
   - Logging aggregation (Loki/ELK)

## References & Research

### Internal References

- Current Streamlit implementation: `dashboard/app.py:1-556`
- FastAPI collector: `collector/main.py:1-581`
- Docker Compose configuration: `docker-compose.yml:1-66`
- ClickHouse schema: `clickhouse-init/01-init-schema.sql`
- Project README: `README.md`
- Environment configuration: `.env.example`

### External References

**Next.js Documentation:**
- [Next.js 15 App Router](https://nextjs.org/docs/app)
- [Server Components](https://nextjs.org/docs/app/building-your-application/rendering/server-components)
- [API Routes](https://nextjs.org/docs/app/building-your-application/routing/route-handlers)
- [Standalone Output](https://nextjs.org/docs/app/api-reference/next-config-js/output)
- [Environment Variables](https://nextjs.org/docs/app/building-your-application/configuring/environment-variables)

**Docker & Deployment:**
- [Optimizing Next.js Docker Images](https://www.timsanteford.com/posts/optimizing-next-js-docker-images-for-production/)
- [Next.js Docker Deployment](https://codeparrot.ai/blogs/deploy-nextjs-app-with-docker-complete-guide-for-2025)
- [Multi-Stage Builds](https://arnab-k.medium.com/optimizing-containerized-deployments-of-next-js-with-docker-c3a1d373cb82)

**Best Practices:**
- [Next.js Best Practices 2025](https://www.raftlabs.com/blog/building-with-next-js-best-practices-and-benefits-for-performance-first-teams/)
- [Analytics Dashboard Guide](https://www.freecodecamp.org/news/build-an-analytical-dashboard-with-nextjs/)
- [Real-Time Dashboards](https://dev.to/mfts/building-a-real-time-analytics-dashboard-with-nextjs-tinybird-and-tremor-a-comprehensive-guide-15k0)

**Chart Libraries:**
- [Best React Chart Libraries 2025](https://blog.logrocket.com/best-react-chart-libraries-2025/)
- [Recharts Documentation](https://recharts.org/)
- [Next.js + Recharts Tutorial](https://ably.com/blog/informational-dashboard-with-nextjs-and-recharts)

**Migration Resources:**
- [Streamlit to Next.js Migration](https://jaehyeon.me/series/realtime-dashboard-with-fastapi-streamlit-and-next.js/)
- [FastAPI + Next.js Integration](https://medium.com/@pottavijay/creating-a-scalable-full-stack-web-app-with-next-js-and-fastapi-eb4db44f4f4e)

---

## Summary

This migration plan transforms the Streamlit dashboard into a modern, production-ready Next.js application with an intuitive UI, comprehensive stats, and professional design. Key improvements include:

- **Lightweight Container**: 80-120MB vs. 180MB (33% reduction)
- **Better Performance**: <2s load time, smooth 1-second timer updates
- **Enhanced Stats**: 9 stat categories vs. 4 (125% increase)
- **Modern Stack**: TypeScript, Tailwind CSS, React best practices
- **Improved UX**: Color-coded warnings, toast notifications, responsive design

The plan is structured in 7 phases over 3-4 weeks with clear success criteria and comprehensive testing. All current Streamlit functionality is preserved while adding new features requested (countdown timer, comprehensive stats, intuitive UI).

Generated with [Claude Code](https://claude.com/claude-code)
