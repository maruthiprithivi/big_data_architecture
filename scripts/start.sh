#!/bin/bash

# ========================================
# Blockchain Data Architecture Start Script
# Shell Version for macOS/Linux
# ========================================
#
# This script starts the Blockchain Data Ingestion System
# Uses macOS-specific Docker Compose overrides for compatibility
#
# ========================================

set -e

# Detect project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    PROJECT_ROOT="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/../docker-compose.yml" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    echo "ERROR: Could not find docker-compose.yml"
    echo "Please ensure you're running this from the project directory or scripts/ subdirectory"
    exit 1
fi

# Change to project root
cd "$PROJECT_ROOT"

echo ""
echo "========================================"
echo " Blockchain Data Ingestion System"
echo " macOS/Linux Edition"
echo "========================================"
echo ""
echo "Working directory: $PROJECT_ROOT"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or unreachable!"
    echo ""
    echo "Please start Docker Desktop first:"
    echo "  1. Open Docker Desktop from Applications"
    echo "  2. Wait for it to fully start"
    echo "  3. Run this script again"
    echo ""
    exit 1
fi

# Check if .env exists
if [ ! -f .env ]; then
    echo "WARNING: .env file not found. Copying from .env.example..."
    cp .env.example .env
    echo "SUCCESS: .env file created."
    echo ""
fi

# Detect OS and set compose files
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
    Darwin*)
        # macOS
        if [ -f "docker-compose.macos.yml" ]; then
            COMPOSE_FILES="-f docker-compose.yml -f docker-compose.macos.yml"
            echo "Using macOS-optimized configuration..."

            # Ensure data directory exists with proper permissions
            mkdir -p ./data/clickhouse
        else
            COMPOSE_FILES="-f docker-compose.yml"
            echo "Using default configuration..."
        fi
        ;;
    Linux*)
        # Linux - use default config (similar to macOS but may need adjustments)
        if [ -f "docker-compose.macos.yml" ]; then
            COMPOSE_FILES="-f docker-compose.yml -f docker-compose.macos.yml"
            echo "Using Linux configuration (similar to macOS)..."
            mkdir -p ./data/clickhouse
        else
            COMPOSE_FILES="-f docker-compose.yml"
            echo "Using default configuration..."
        fi
        ;;
    *)
        COMPOSE_FILES="-f docker-compose.yml"
        echo "Unknown OS ($OS_TYPE), using default configuration..."
        ;;
esac

# Clean up any previous failed containers
echo "Cleaning up any stale containers..."
docker compose $COMPOSE_FILES down --remove-orphans >/dev/null 2>&1 || true

echo ""
echo "Starting Docker containers..."
echo "This may take a few minutes on first run..."
echo ""

docker compose $COMPOSE_FILES up --build -d

if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Failed to start services!"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Make sure Docker Desktop is running"
    echo "  2. Try: docker system prune -f"
    echo "  3. Check: docker compose $COMPOSE_FILES logs clickhouse"
    echo ""
    exit 1
fi

echo ""
echo "Waiting for services to become healthy..."

# Wait for ClickHouse to be ready (up to 90 seconds)
attempts=0
max_attempts=18

while [ $attempts -lt $max_attempts ]; do
    if docker compose $COMPOSE_FILES ps clickhouse 2>/dev/null | grep -qi "healthy"; then
        break
    fi
    attempts=$((attempts + 1))
    echo "  Waiting for ClickHouse... ($attempts/$max_attempts)"
    sleep 5
done

if [ $attempts -ge $max_attempts ]; then
    echo ""
    echo "WARNING: Services took longer than expected to start."
    echo "They may still be initializing. Check the dashboard in a moment."
fi

echo ""
echo "========================================"
echo " SUCCESS: Services are running!"
echo "========================================"
echo ""
echo "Service URLs:"
echo "  Dashboard:   http://localhost:3001"
echo "  API:         http://localhost:8000"
echo "  ClickHouse:  http://localhost:8123"
echo ""
echo "Useful commands:"
echo "  View logs:   docker compose $COMPOSE_FILES logs -f"
echo "  Stop:        docker compose $COMPOSE_FILES down"
echo "  Restart:     docker compose $COMPOSE_FILES restart"
echo ""

# Ask if user wants to open dashboard (macOS only)
if [ "$OS_TYPE" = "Darwin" ]; then
    read -p "Open dashboard in browser? (Y/n): " OPEN_BROWSER
    if [ "$OPEN_BROWSER" != "n" ] && [ "$OPEN_BROWSER" != "N" ]; then
        sleep 2
        open http://localhost:3001
    fi
fi
