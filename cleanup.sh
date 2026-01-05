#!/bin/bash

# ========================================
# Blockchain Data Architecture Cleanup Script
# ========================================
#
# This script completely removes all deployed resources:
# - Docker containers
# - Docker volumes (including all collected data)
# - Docker networks
# - Docker images (optional)
# - Local data directories
#
# WARNINGS:
# - This will DELETE ALL collected blockchain data
# - This action is IRREVERSIBLE
# - You will need to restart from scratch after running this
#
# ========================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Check if running in the correct directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in current directory"
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Confirmation prompt
print_section "CLEANUP CONFIRMATION"
print_warning "This script will DELETE ALL deployed resources including:"
echo "  - Docker containers (clickhouse, blockchain-collector, blockchain-dashboard)"
echo "  - Docker volumes (all collected blockchain data)"
echo "  - Docker networks (blockchain-network)"
echo "  - Local data directories (data/clickhouse)"
echo ""
print_warning "This action is IRREVERSIBLE!"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Cleanup cancelled"
    exit 0
fi

# Secondary confirmation for data deletion
echo ""
read -p "This will delete ALL collected blockchain data. Type 'DELETE' to confirm: " -r
echo

if [[ $REPLY != "DELETE" ]]; then
    print_info "Cleanup cancelled"
    exit 0
fi

# Start cleanup
print_section "Starting Cleanup Process"

# Step 1: Stop and remove containers
print_section "Step 1: Stopping and Removing Containers"
if docker compose ps -q 2>/dev/null | grep -q .; then
    print_info "Stopping containers..."
    docker compose stop

    print_info "Removing containers..."
    docker compose rm -f

    print_info "Containers removed successfully"
else
    print_info "No running containers found"
fi

# Step 2: Remove volumes
print_section "Step 2: Removing Docker Volumes"
if docker volume ls -q | grep -q "big_data_architecture\|blockchain"; then
    print_info "Removing Docker volumes..."
    docker volume ls -q | grep "big_data_architecture\|blockchain" | xargs -r docker volume rm 2>/dev/null || true
    print_info "Volumes removed successfully"
else
    print_info "No matching volumes found"
fi

# Step 3: Remove networks
print_section "Step 3: Removing Docker Networks"
if docker network ls -q -f name=blockchain-network | grep -q .; then
    print_info "Removing blockchain-network..."
    docker network rm blockchain-network 2>/dev/null || print_warning "Network may still be in use or already removed"
    print_info "Network removed successfully"
else
    print_info "Network not found"
fi

# Step 4: Remove local data directories
print_section "Step 4: Cleaning Local Data Directories"
if [ -d "data/clickhouse" ]; then
    print_info "Removing data/clickhouse directory..."
    rm -rf data/clickhouse
    print_info "Local data directory removed"
else
    print_info "No local data directory found"
fi

# Step 5: Optional - Remove Docker images
print_section "Step 5: Docker Images (Optional)"
echo "Do you want to remove the Docker images as well?"
echo "This will require rebuilding images on next startup (slower)"
read -p "Remove images? (y/N): " -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Removing project Docker images..."

    # Remove project-specific images
    docker images | grep "big_data_architecture" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

    print_info "Images removed successfully"
else
    print_info "Keeping Docker images (recommended for faster restart)"
fi

# Step 6: Optional - Remove ClickHouse base image
print_section "Step 6: ClickHouse Base Image (Optional)"
echo "Do you want to remove the ClickHouse base image?"
echo "This is a large download (~800MB) if you need to re-download"
read -p "Remove ClickHouse image? (y/N): " -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Removing ClickHouse base image..."
    docker rmi clickhouse/clickhouse-server:latest 2>/dev/null || print_warning "ClickHouse image not found"
    print_info "ClickHouse image removed"
else
    print_info "Keeping ClickHouse base image"
fi

# Step 7: Clean up any orphaned resources
print_section "Step 7: Cleaning Orphaned Resources"
print_info "Removing orphaned containers..."
docker container prune -f 2>/dev/null || true

print_info "Removing orphaned volumes..."
docker volume prune -f 2>/dev/null || true

print_info "Removing orphaned networks..."
docker network prune -f 2>/dev/null || true

print_info "Removing orphaned images..."
docker image prune -f 2>/dev/null || true

# Final summary
print_section "Cleanup Complete!"
echo ""
print_info "All resources have been removed successfully"
echo ""
echo "Summary of what was removed:"
echo "  ✓ Docker containers"
echo "  ✓ Docker volumes (all collected data)"
echo "  ✓ Docker networks"
echo "  ✓ Local data directories"
echo ""
print_info "To restart the project, run:"
echo "  docker compose up -d --build"
echo ""
print_warning "Note: You will start with a fresh database and no collected data"
