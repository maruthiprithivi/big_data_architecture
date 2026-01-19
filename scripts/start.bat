@echo off
REM ========================================
REM Blockchain Data Architecture Start Script
REM Batch Version for Windows
REM ========================================
REM
REM This script starts the Blockchain Data Ingestion System
REM Just double-click to run, or run from Command Prompt
REM
REM Uses Windows-specific Docker Compose overrides for compatibility
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

echo.
echo ========================================
echo  Blockchain Data Ingestion System
echo  Windows Edition
echo ========================================
echo.
echo Working directory: %PROJECT_ROOT%
echo.

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

REM Check if Docker is running
docker info >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker is not running or unreachable!
    echo.
    echo Diagnostic information:
    docker info
    echo.
    echo Please start Docker Desktop first:
    echo   1. Open Docker Desktop from the Start menu
    echo   2. Wait for it to fully start ^(whale icon stops animating^)
    echo   3. Run this script again
    echo.
    echo If Docker Desktop is not installed, see docs\WINDOWS_SETUP.md
    echo.
    pause
    exit /b 1
)

REM Check if .env exists
if not exist ".env" (
    echo WARNING: .env file not found. Copying from .env.example...
    copy ".env.example" ".env" >nul
    echo SUCCESS: .env file created.
    echo.
)

REM Clean up any previous failed containers
echo Cleaning up any stale containers...
%DOCKER_COMPOSE_CMD% down --remove-orphans >nul 2>&1

REM Check if Windows-specific compose file exists
if exist "docker-compose.windows.yml" (
    set "COMPOSE_FILES=-f docker-compose.yml -f docker-compose.windows.yml"
    echo Using Windows-optimized configuration...
) else (
    set "COMPOSE_FILES=-f docker-compose.yml"
    echo Using default configuration...
)

echo.
echo Starting Docker containers...
echo This may take a few minutes on first run...
echo.

%DOCKER_COMPOSE_CMD% %COMPOSE_FILES% up --build -d

if errorlevel 1 (
    echo.
    echo ERROR: Failed to start services!
    echo.
    echo Troubleshooting steps:
    echo   1. Make sure Docker Desktop is running and responsive
    echo   2. Try: docker system prune -f
    echo   3. Check: %DOCKER_COMPOSE_CMD% %COMPOSE_FILES% logs clickhouse
    echo   4. See docs\TROUBLESHOOTING.md for more help
    echo.
    pause
    exit /b 1
)

echo.
echo Waiting for services to become healthy...

REM Wait for ClickHouse to be ready (up to 90 seconds)
set /a "attempts=0"
set /a "max_attempts=18"

:wait_loop
if %attempts% geq %max_attempts% (
    echo.
    echo WARNING: Services took longer than expected to start.
    echo They may still be initializing. Check the dashboard in a moment.
    goto :services_ready
)

%DOCKER_COMPOSE_CMD% %COMPOSE_FILES% ps clickhouse 2>nul | findstr /i "healthy" >nul
if %errorlevel% equ 0 (
    goto :services_ready
)

set /a "attempts+=1"
echo   Waiting for ClickHouse... ^(%attempts%/%max_attempts%^)
timeout /t 5 /nobreak >nul
goto :wait_loop

:services_ready
echo.
echo ========================================
echo  SUCCESS: Services are running!
echo ========================================
echo.
echo Service URLs:
echo   Dashboard:   http://localhost:3001
echo   API:         http://localhost:8000
echo   ClickHouse:  http://localhost:8123
echo.
echo Useful commands:
echo   View logs:   %DOCKER_COMPOSE_CMD% %COMPOSE_FILES% logs -f
echo   Stop:        %DOCKER_COMPOSE_CMD% %COMPOSE_FILES% down
echo   Restart:     %DOCKER_COMPOSE_CMD% %COMPOSE_FILES% restart
echo.

REM Ask if user wants to open dashboard
set /p "OPEN_BROWSER=Open dashboard in browser? (Y/n): "
if /i not "%OPEN_BROWSER%"=="n" (
    timeout /t 2 /nobreak >nul
    start http://localhost:3001
)

echo.
pause
