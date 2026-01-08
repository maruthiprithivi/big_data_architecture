#!/bin/bash

echo "🚀 Starting Blockchain Data Ingestion System..."
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Copying from .env.example..."
    cp .env.example .env
    echo "✓ .env file created. Please review and modify if needed."
    echo ""
fi

# Start services
echo "Starting Docker containers..."
docker compose up --build -d

echo ""
echo "✓ Services starting..."
echo ""
echo "📊 Dashboard: http://localhost:3001"
echo "🔌 API: http://localhost:8000"
echo "🗄️  ClickHouse: localhost:8123"
echo ""
echo "To view logs: docker compose logs -f"
echo "To stop: docker compose down"
