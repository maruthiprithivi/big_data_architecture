@echo off
REM ========================================
REM Blockchain Data Architecture Cleanup Script
REM Batch Version for Windows
REM ========================================
REM
REM This script removes all deployed resources
REM WARNING: This will DELETE ALL collected data!
REM
REM For more features, use the PowerShell version: cleanup.ps1
REM
REM ========================================

setlocal enabledelayedexpansion

REM Detect project root directory
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

if exist "%SCRIPT_DIR%\docker-compose.yml" (
    set "PROJECT_ROOT=%SCRIPT_DIR%"
) else if exist "%SCRIPT_DIR%\..\docker-compose.yml" (
    pushd "%SCRIPT_DIR%\.."
    set "PROJECT_ROOT=!CD!"
    popd
) else (
    echo ERROR: Could not find docker-compose.yml
    echo Please ensure you're running this from the project directory or scripts\ subdirectory
    pause
    exit /b 1
)

REM Change to project root
cd /d "%PROJECT_ROOT%"

REM Determine Docker Compose command
docker compose version >nul 2>&1
if %errorlevel% equ 0 (
    set "DOCKER_COMPOSE_CMD=docker compose"
) else (
    docker-compose version >nul 2>&1
    if %errorlevel% equ 0 (
        set "DOCKER_COMPOSE_CMD=docker-compose"
    ) else (
        echo ERROR: Neither 'docker compose' nor 'docker-compose' found.
        echo Please install Docker Desktop for Windows.
        pause
        exit /b 1
    )
)

echo.
echo ========================================
echo  CLEANUP CONFIRMATION
echo ========================================
echo.
echo WARNING: This script will DELETE ALL deployed resources including:
echo   - Docker containers
echo   - Docker volumes (all collected blockchain data)
echo   - Docker networks
echo   - Local data directories
echo.
echo This action is IRREVERSIBLE!
echo.

set /p "CONFIRM1=Are you sure you want to continue? (type 'yes' to confirm): "
if /i not "%CONFIRM1%"=="yes" (
    echo Cleanup cancelled.
    pause
    exit /b 0
)

echo.
set /p "CONFIRM2=This will delete ALL collected data. Type 'DELETE' to confirm: "
if not "%CONFIRM2%"=="DELETE" (
    echo Cleanup cancelled.
    pause
    exit /b 0
)

echo.
echo ========================================
echo  Starting Cleanup Process
echo ========================================
echo.

REM Step 1: Stop and remove containers
echo Step 1: Stopping and Removing Containers...
%DOCKER_COMPOSE_CMD% stop 2>nul
%DOCKER_COMPOSE_CMD% rm -f 2>nul
echo   [OK] Containers removed
echo.

REM Step 2: Remove volumes
echo Step 2: Removing Docker Volumes...
for /f "tokens=*" %%v in ('docker volume ls -q 2^>nul ^| findstr /i "big_data_architecture blockchain"') do (
    docker volume rm %%v 2>nul
)
echo   [OK] Volumes removed
echo.

REM Step 3: Remove networks
echo Step 3: Removing Docker Networks...
docker network rm blockchain-network 2>nul
echo   [OK] Networks removed
echo.

REM Step 4: Remove local data directories
echo Step 4: Cleaning Local Data Directories...
if exist "data\clickhouse" (
    rmdir /s /q "data\clickhouse" 2>nul
)
echo   [OK] Local data removed
echo.

REM Step 5: Optional - Remove Docker images
echo Step 5: Docker Images (Optional)
set /p "REMOVE_IMAGES=Remove Docker images? This requires rebuild on restart (y/N): "
if /i "%REMOVE_IMAGES%"=="y" (
    echo Removing project Docker images...
    for /f "tokens=3" %%i in ('docker images ^| findstr "big_data_architecture"') do (
        docker rmi -f %%i 2>nul
    )
    echo   [OK] Images removed
) else (
    echo   [SKIP] Keeping Docker images
)
echo.

REM Step 6: Clean up orphaned resources
echo Step 6: Cleaning Orphaned Resources...
docker container prune -f >nul 2>&1
docker volume prune -f >nul 2>&1
docker network prune -f >nul 2>&1
docker image prune -f >nul 2>&1
echo   [OK] Orphaned resources cleaned
echo.

echo ========================================
echo  Cleanup Complete!
echo ========================================
echo.
echo Summary of what was removed:
echo   [OK] Docker containers
echo   [OK] Docker volumes (all collected data)
echo   [OK] Docker networks
echo   [OK] Local data directories
echo.
echo To restart the project, run:
echo   start.bat
echo   OR
echo   %DOCKER_COMPOSE_CMD% up -d --build
echo.
echo NOTE: You will start with a fresh database.
echo.
pause
