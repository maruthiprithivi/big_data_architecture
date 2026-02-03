# Blockchain Data Ingestion with ClickHouse and Next.js

A containerized system for ingesting blockchain data from **Bitcoin** and **Solana** into ClickHouse, with a real-time Next.js monitoring dashboard. Built for teaching data engineering concepts using live blockchain data.

## What It Does

Collects blocks and transactions from Bitcoin and Solana RPC endpoints, stores them in a ClickHouse columnar database optimized for analytics, and provides a web dashboard for monitoring and controlling the pipeline. Demonstrates the 5Vs of Big Data (Volume, Velocity, Variety, Veracity, Value) with real-world blockchain data.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Database | ClickHouse (columnar OLAP) |
| Collector | Python, FastAPI |
| Dashboard | TypeScript, Next.js, React, Tailwind CSS |
| Orchestration | Docker Compose |
| Data Sources | Bitcoin (Blockstream API), Solana (mainnet RPC) |

## Quick Start

```bash
# 1. Clone and configure
git clone git@github.com:maruthiprithivi/big_data_architecture.git
cd big_data_architecture
cp .env.example .env    # defaults work out of the box

# 2. Start all services
docker compose up --build -d

# 3. Open the dashboard
open http://localhost:3001
```

Click **Start Collection** on the dashboard to begin ingesting data. Collection auto-stops after 10 minutes (configurable).

## Repository Structure

```
big_data_architecture/
├── collector/                # FastAPI data collection service
│   ├── main.py               # API orchestration (start/stop/status)
│   ├── collectors/            # Per-chain collector modules
│   ├── Dockerfile
│   └── requirements.txt
├── dashboard/                # Next.js monitoring dashboard
│   ├── app/                   # Pages, components, API routes
│   ├── Dockerfile
│   └── package.json
├── clickhouse-init/          # Database schema initialization
├── clickhouse-config/        # ClickHouse storage configuration
├── bitcoin-core/             # Bitcoin Core node config (advanced)
├── scripts/                  # Operational scripts (start, cleanup, deploy, etc.)
├── docs/                     # Learning materials
│   ├── USAGE_GUIDE.md         # Comprehensive reference (start here)
│   ├── EXERCISES.md           # 9 hands-on exercises
│   ├── GLOSSARY.md            # Blockchain and data engineering terms
│   └── SAMPLE_QUERIES.md     # ClickHouse SQL examples
├── docker-compose.yml        # Service orchestration
├── docker-compose.production.yml
├── .env.example              # Configuration template
└── CONTRIBUTING.md
```

## Documentation

**[docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)** is the single comprehensive reference covering setup, configuration, architecture, deployment (local and production), hybrid architecture with Bitcoin Core, troubleshooting, and maintenance.

## Learning Resources

- **[Exercises](docs/EXERCISES.md)** -- 9 progressive hands-on exercises from basic queries to cross-chain analysis
- **[Glossary](docs/GLOSSARY.md)** -- Blockchain and data engineering terminology
- **[Sample Queries](docs/SAMPLE_QUERIES.md)** -- ClickHouse SQL patterns for blockchain analytics

## Access Points (when running)

| Service | URL |
|---------|-----|
| Dashboard | http://localhost:3001 |
| Collector API | http://localhost:8000 |
| API Docs (Swagger) | http://localhost:8000/docs |
| ClickHouse HTTP | http://localhost:8123 |

## Stopping and Cleanup

```bash
docker compose down          # Stop services (data preserved)
docker compose down -v       # Stop and delete all data
./scripts/cleanup.sh         # Interactive full cleanup
```

## License

This project is provided for educational purposes. Please ensure compliance with the terms of service of any RPC endpoints you use.
