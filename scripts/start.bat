@echo off
REM ========================================
REM Blockchain Data Architecture Start Script
REM Batch Version for Windows
REM ========================================
REM
REM This script starts the Blockchain Data Ingestion System
REM Just double-click to run, or run from Command Prompt
REM
REM For more features, use the PowerShell version: start.ps1
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
    echo ERROR: Docker is not running!
    echo.
    echo Please start Docker Desktop first:
    echo   1. Open Docker Desktop from the Start menu
    echo   2. Wait for it to fully start
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

REM Start services
echo Starting Docker containers...
echo.

%DOCKER_COMPOSE_CMD% up --build -d

if errorlevel 1 (
    echo.
    echo ERROR: Failed to start services!
    echo Check the error messages above and see docs\TROUBLESHOOTING.md
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  SUCCESS: Services starting...
echo ========================================
echo.
echo Service URLs:
echo   Dashboard:   http://localhost:3001
echo   API:         http://localhost:8000
echo   ClickHouse:  http://localhost:8123
echo.
echo Useful commands:
echo   View logs:   %DOCKER_COMPOSE_CMD% logs -f
echo   Stop:        %DOCKER_COMPOSE_CMD% down
echo.

REM Ask if user wants to open dashboard
set /p "OPEN_BROWSER=Open dashboard in browser? (Y/n): "
if /i not "%OPEN_BROWSER%"=="n" (
    timeout /t 3 /nobreak >nul
    start http://localhost:3001
)

echo.
pause
