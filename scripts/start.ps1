# ========================================
# Blockchain Data Architecture Start Script
# PowerShell Version for Windows
# ========================================
#
# This script starts the Blockchain Data Ingestion System
# Run with: .\start.ps1
# Or: powershell -ExecutionPolicy Bypass -File start.ps1
#
# ========================================

# Detect project root directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path "$ScriptDir\docker-compose.yml") {
    # Script is in root directory
    $ProjectRoot = $ScriptDir
} elseif (Test-Path "$ScriptDir\..\docker-compose.yml") {
    # Script is in scripts/ subdirectory
    $ProjectRoot = (Resolve-Path "$ScriptDir\..").Path
} else {
    Write-Host "ERROR: Could not find docker-compose.yml" -ForegroundColor Red
    Write-Host "Please ensure you're running this from the project directory or scripts/ subdirectory" -ForegroundColor Red
    exit 1
}

# Change to project root
Set-Location $ProjectRoot

Write-Host ""
Write-Host "Starting Blockchain Data Ingestion System..." -ForegroundColor Cyan
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

# Check if Docker is running
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker not running"
    }
} catch {
    Write-Host "ERROR: Docker is not running or unreachable!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Diagnostic information:" -ForegroundColor White
    $dockerInfo | Write-Host -ForegroundColor Gray
    Write-Host ""
    Write-Host "Please start Docker Desktop first:" -ForegroundColor Yellow
    Write-Host "  1. Open Docker Desktop from the Start menu" -ForegroundColor Gray
    Write-Host "  2. Wait for it to fully start (icon stops animating)" -ForegroundColor Gray
    Write-Host "  3. Run this script again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "If Docker Desktop is not installed, see docs/WINDOWS_SETUP.md" -ForegroundColor Yellow
    exit 1
}

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Host "WARNING: .env file not found. Copying from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
    Write-Host "SUCCESS: .env file created. Please review and modify if needed." -ForegroundColor Green
    Write-Host ""
}

# Verify Docker image versions
Write-Host "Verifying Docker image versions..." -ForegroundColor Cyan
$dockerComposeContent = Get-Content "docker-compose.yml" -Raw
if ($dockerComposeContent -match "clickhouse/clickhouse-server:([^\s]+)") {
    $ClickHouseVersion = $Matches[1]
    $ExpectedClickHouse = "25.10-alpine"

    if ($ClickHouseVersion -ne $ExpectedClickHouse) {
        Write-Host "WARNING: ClickHouse version mismatch!" -ForegroundColor Yellow
        Write-Host "   Expected: $ExpectedClickHouse" -ForegroundColor Gray
        Write-Host "   Found:    $ClickHouseVersion" -ForegroundColor Gray
        Write-Host "   Please check docker-compose.yml and docs/DOCKER_VERSIONS.md" -ForegroundColor Gray
        Write-Host ""
    }
}

# Start services
Write-Host "Starting Docker containers..." -ForegroundColor Cyan
Write-Host ""

& $DockerComposeCmd $DockerComposeArgs up --build -d

if ($LASTEXITCODE -eq 0) {
    $LogCmd = "$DockerComposeCmd $($DockerComposeArgs -join ' ') logs -f"
    $StopCmd = "$DockerComposeCmd $($DockerComposeArgs -join ' ') down"

    Write-Host ""
    Write-Host "SUCCESS: Services starting..." -ForegroundColor Green
    Write-Host ""
    Write-Host "Service URLs:" -ForegroundColor Cyan
    Write-Host "  Dashboard:   http://localhost:3001" -ForegroundColor White
    Write-Host "  API:         http://localhost:8000" -ForegroundColor White
    Write-Host "  ClickHouse:  http://localhost:8123" -ForegroundColor White
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor Cyan
    Write-Host "  View logs:   $LogCmd" -ForegroundColor Gray
    Write-Host "  Stop:        $StopCmd" -ForegroundColor Gray
    Write-Host ""

    # Ask if user wants to open dashboard
    $openBrowser = Read-Host "Open dashboard in browser? (Y/n)"
    if ($openBrowser -ne "n" -and $openBrowser -ne "N") {
        Start-Sleep -Seconds 3
        Start-Process "http://localhost:3001"
    }
} else {
    Write-Host ""
    Write-Host "ERROR: Failed to start services!" -ForegroundColor Red
    Write-Host "Check the error messages above and see docs/TROUBLESHOOTING.md" -ForegroundColor Yellow
    exit 1
}
