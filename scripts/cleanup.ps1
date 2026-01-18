# ========================================
# Blockchain Data Architecture Cleanup Script
# PowerShell Version for Windows
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
# Run with: .\cleanup.ps1
# Or: powershell -ExecutionPolicy Bypass -File cleanup.ps1
#
# ========================================

# Stop on errors
$ErrorActionPreference = "Stop"

# Detect project root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path "$ScriptDir\docker-compose.yml") {
    $ProjectRoot = $ScriptDir
} elseif (Test-Path "$ScriptDir\..\docker-compose.yml") {
    $ProjectRoot = (Resolve-Path "$ScriptDir\..").Path
} else {
    Write-Host "ERROR: Could not find docker-compose.yml" -ForegroundColor Red
    Write-Host "Please ensure you're running this from the project directory or scripts/ subdirectory" -ForegroundColor Red
    exit 1
}

# Change to project root
Set-Location $ProjectRoot
Write-Host "Working directory: $ProjectRoot" -ForegroundColor Gray
Write-Host ""

# Determine Docker Compose command
$DockerComposeCmd = "docker"
$DockerComposeArgs = @("compose")

try {
    docker compose version 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No docker compose"
    }
} catch {
    try {
        docker-compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $DockerComposeCmd = "docker-compose"
            $DockerComposeArgs = @()
        } else {
            throw "No docker-compose"
        }
    } catch {
        Write-Host "ERROR: Neither 'docker compose' nor 'docker-compose' found." -ForegroundColor Red
        Write-Host "Please install Docker Desktop for Windows." -ForegroundColor Red
        exit 1
    }
}

# Confirmation prompt
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "         CLEANUP CONFIRMATION          " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "WARNING: This script will DELETE ALL deployed resources including:" -ForegroundColor Yellow
Write-Host "  - Docker containers (clickhouse, blockchain-collector, blockchain-dashboard)" -ForegroundColor White
Write-Host "  - Docker volumes (all collected blockchain data)" -ForegroundColor White
Write-Host "  - Docker networks (blockchain-network)" -ForegroundColor White
Write-Host "  - Local data directories (data\clickhouse)" -ForegroundColor White
Write-Host ""
Write-Host "This action is IRREVERSIBLE!" -ForegroundColor Red
Write-Host ""

$confirm1 = Read-Host "Are you sure you want to continue? (type 'yes' to confirm)"
if ($confirm1 -ne "yes") {
    Write-Host "Cleanup cancelled" -ForegroundColor Green
    exit 0
}

# Secondary confirmation
Write-Host ""
$confirm2 = Read-Host "This will delete ALL collected blockchain data. Type 'DELETE' to confirm"
if ($confirm2 -ne "DELETE") {
    Write-Host "Cleanup cancelled" -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     Starting Cleanup Process          " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Stop and remove containers
Write-Host "Step 1: Stopping and Removing Containers" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$containers = & $DockerComposeCmd $DockerComposeArgs ps -q 2>$null
if ($containers) {
    Write-Host "Stopping containers..." -ForegroundColor Gray
    & $DockerComposeCmd $DockerComposeArgs stop 2>$null

    Write-Host "Removing containers..." -ForegroundColor Gray
    & $DockerComposeCmd $DockerComposeArgs rm -f 2>$null

    Write-Host "SUCCESS: Containers removed" -ForegroundColor Green
} else {
    Write-Host "INFO: No running containers found" -ForegroundColor Gray
}
Write-Host ""

# Step 2: Remove volumes
Write-Host "Step 2: Removing Docker Volumes" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$volumes = docker volume ls -q | Where-Object { $_ -match "big_data_architecture|blockchain" }
if ($volumes) {
    Write-Host "Removing Docker volumes..." -ForegroundColor Gray
    foreach ($vol in $volumes) {
        docker volume rm $vol 2>$null
    }
    Write-Host "SUCCESS: Volumes removed" -ForegroundColor Green
} else {
    Write-Host "INFO: No matching volumes found" -ForegroundColor Gray
}
Write-Host ""

# Step 3: Remove networks
Write-Host "Step 3: Removing Docker Networks" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$network = docker network ls -q -f name=blockchain-network 2>$null
if ($network) {
    Write-Host "Removing blockchain-network..." -ForegroundColor Gray
    docker network rm blockchain-network 2>$null
    Write-Host "SUCCESS: Network removed" -ForegroundColor Green
} else {
    Write-Host "INFO: Network not found" -ForegroundColor Gray
}
Write-Host ""

# Step 4: Remove local data directories
Write-Host "Step 4: Cleaning Local Data Directories" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (Test-Path "data\clickhouse") {
    Write-Host "Removing data\clickhouse directory..." -ForegroundColor Gray
    Remove-Item -Recurse -Force "data\clickhouse"
    Write-Host "SUCCESS: Local data directory removed" -ForegroundColor Green
} else {
    Write-Host "INFO: No local data directory found" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Optional - Remove Docker images
Write-Host "Step 5: Docker Images (Optional)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Do you want to remove the Docker images as well?" -ForegroundColor White
Write-Host "This will require rebuilding images on next startup (slower)" -ForegroundColor Gray

$removeImages = Read-Host "Remove images? (y/N)"
if ($removeImages -eq "y" -or $removeImages -eq "Y") {
    Write-Host "Removing project Docker images..." -ForegroundColor Gray
    $images = docker images | Select-String "big_data_architecture" | ForEach-Object { ($_ -split '\s+')[2] }
    foreach ($img in $images) {
        docker rmi -f $img 2>$null
    }
    Write-Host "SUCCESS: Images removed" -ForegroundColor Green
} else {
    Write-Host "INFO: Keeping Docker images (recommended for faster restart)" -ForegroundColor Gray
}
Write-Host ""

# Step 6: Optional - Remove ClickHouse base image
Write-Host "Step 6: ClickHouse Base Image (Optional)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Do you want to remove the ClickHouse base image?" -ForegroundColor White
Write-Host "This is a large download (~800MB) if you need to re-download" -ForegroundColor Gray

$removeClickhouse = Read-Host "Remove ClickHouse image? (y/N)"
if ($removeClickhouse -eq "y" -or $removeClickhouse -eq "Y") {
    Write-Host "Removing ClickHouse base image..." -ForegroundColor Gray
    docker rmi clickhouse/clickhouse-server:25.10-alpine 2>$null
    Write-Host "SUCCESS: ClickHouse image removed" -ForegroundColor Green
} else {
    Write-Host "INFO: Keeping ClickHouse base image" -ForegroundColor Gray
}
Write-Host ""

# Step 7: Clean up orphaned resources
Write-Host "Step 7: Cleaning Orphaned Resources" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Removing orphaned containers..." -ForegroundColor Gray
docker container prune -f 2>$null | Out-Null

Write-Host "Removing orphaned volumes..." -ForegroundColor Gray
docker volume prune -f 2>$null | Out-Null

Write-Host "Removing orphaned networks..." -ForegroundColor Gray
docker network prune -f 2>$null | Out-Null

Write-Host "Removing orphaned images..." -ForegroundColor Gray
docker image prune -f 2>$null | Out-Null

Write-Host "SUCCESS: Orphaned resources cleaned" -ForegroundColor Green
Write-Host ""

# Final summary
Write-Host "========================================" -ForegroundColor Green
Write-Host "         Cleanup Complete!             " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "All resources have been removed successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Summary of what was removed:" -ForegroundColor White
Write-Host "  [OK] Docker containers" -ForegroundColor Gray
Write-Host "  [OK] Docker volumes (all collected data)" -ForegroundColor Gray
Write-Host "  [OK] Docker networks" -ForegroundColor Gray
Write-Host "  [OK] Local data directories" -ForegroundColor Gray
Write-Host ""
Write-Host "To restart the project, run:" -ForegroundColor Cyan
Write-Host "  .\start.ps1" -ForegroundColor White
Write-Host "  OR" -ForegroundColor Gray
Write-Host "  $DockerComposeCmd $($DockerComposeArgs -join ' ') up -d --build" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: You will start with a fresh database and no collected data" -ForegroundColor Yellow
