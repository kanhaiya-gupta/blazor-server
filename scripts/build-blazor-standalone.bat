@echo off
REM AASX Blazor Server Standalone Build Script (Windows)
REM Builds and manages the standalone Blazor server Docker image

setlocal enabledelayedexpansion

REM Configuration
set IMAGE_NAME=aasx-blazor-standalone
set CONTAINER_NAME=aasx-blazor-standalone
set DOCKERFILE_PATH=docker\Dockerfile
set DOCKERFILE_DEV_PATH=docker\Dockerfile.dev
set DOCKER_COMPOSE_PATH=docker\docker-compose.yml
set DATA_DIR=..\data
set PORT=5001

REM Function to print colored output
:print_header
echo.
echo ========================================
echo    AASX Blazor Server Standalone
echo ========================================
echo.
goto :eof

:print_success
echo ✅ %~1
goto :eof

:print_warning
echo ⚠️  %~1
goto :eof

:print_error
echo ❌ %~1
goto :eof

:print_info
echo ℹ️  %~1
goto :eof

REM Function to check prerequisites
:check_prerequisites
call :print_info "Checking prerequisites..."

docker --version >nul 2>&1
if errorlevel 1 (
    call :print_error "Docker is not installed or not in PATH"
    exit /b 1
)

docker-compose --version >nul 2>&1
if errorlevel 1 (
    call :print_error "Docker Compose is not installed or not in PATH"
    exit /b 1
)

if not exist "%DOCKERFILE_PATH%" (
    call :print_error "Dockerfile not found: %DOCKERFILE_PATH%"
    exit /b 1
)

call :print_success "Prerequisites check passed"
goto :eof

REM Function to build the image
:build_image
set dockerfile=%~1
set tag=%~2

call :print_info "Building Docker image: %IMAGE_NAME%:%tag%"
call :print_info "Using Dockerfile: %dockerfile%"

docker build -f "%dockerfile%" -t "%IMAGE_NAME%:%tag%" .

if errorlevel 1 (
    call :print_error "Failed to build image"
    exit /b 1
) else (
    call :print_success "Image built successfully: %IMAGE_NAME%:%tag%"
)
goto :eof

REM Function to run the container
:run_container
set tag=%~1

call :print_info "Starting container: %CONTAINER_NAME%"

REM Stop existing container if running
docker stop "%CONTAINER_NAME%" >nul 2>&1
docker rm "%CONTAINER_NAME%" >nul 2>&1

REM Create data directory if it doesn't exist
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"

REM Run the container
docker run -d ^
    --name "%CONTAINER_NAME%" ^
    -p "%PORT%:5001" ^
    -v "%cd%\%DATA_DIR%:/app/data" ^
    -e AASX_DATA_PATH=./data ^
    -e AASX_SERVER_PORT=5001 ^
    -e ASPNETCORE_ENVIRONMENT=Production ^
    "%IMAGE_NAME%:%tag%"

if errorlevel 1 (
    call :print_error "Failed to start container"
    exit /b 1
) else (
    call :print_success "Container started successfully"
    call :print_info "Access the Blazor server at: http://localhost:%PORT%"
    call :print_info "Container name: %CONTAINER_NAME%"
)
goto :eof

REM Function to stop the container
:stop_container
call :print_info "Stopping container: %CONTAINER_NAME%"

docker stop "%CONTAINER_NAME%" >nul 2>&1
docker rm "%CONTAINER_NAME%" >nul 2>&1

call :print_success "Container stopped and removed"
goto :eof

REM Function to show logs
:show_logs
set follow=%~1

call :print_info "Showing logs for container: %CONTAINER_NAME%"

if "%follow%"=="true" (
    docker logs -f "%CONTAINER_NAME%"
) else (
    docker logs "%CONTAINER_NAME%"
)
goto :eof

REM Function to clean up
:cleanup
call :print_info "Cleaning up Docker resources..."

REM Stop and remove container
call :stop_container

REM Remove images
docker rmi "%IMAGE_NAME%:latest" >nul 2>&1
docker rmi "%IMAGE_NAME%:dev" >nul 2>&1

REM Remove dangling images
docker image prune -f

call :print_success "Cleanup completed"
goto :eof

REM Function to show status
:show_status
call :print_info "Container status:"
docker ps -a --filter "name=%CONTAINER_NAME%" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo.
call :print_info "Image status:"
docker images "%IMAGE_NAME%" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
goto :eof

REM Function to use docker-compose
:use_compose
set action=%~1

call :print_info "Using Docker Compose: %action%"

cd docker
docker-compose %action%
cd ..
goto :eof

REM Function to show help
:show_help
call :print_header
echo Usage: %~nx0 [COMMAND] [OPTIONS]
echo.
echo Commands:
echo   build [dev]     Build the Docker image (dev for development)
echo   run [dev]       Build and run the container (dev for development)
echo   start           Start the container
echo   stop            Stop the container
echo   restart         Restart the container
echo   logs [--follow] Show container logs
echo   status          Show container and image status
echo   clean           Clean up Docker resources
echo   compose [up^|down^|build] Use docker-compose
echo   help            Show this help message
echo.
echo Options:
echo   --follow        Follow logs (use with logs command)
echo   dev             Use development Dockerfile
echo.
echo Examples:
echo   %~nx0 build        # Build production image
echo   %~nx0 build dev    # Build development image
echo   %~nx0 run          # Build and run production container
echo   %~nx0 run dev      # Build and run development container
echo   %~nx0 logs --follow # Show logs with follow
echo   %~nx0 compose up   # Use docker-compose to start services
echo.
goto :eof

REM Main script logic
set command=%1
set option=%2

if "%command%"=="build" (
    call :check_prerequisites
    if "%option%"=="dev" (
        call :build_image "%DOCKERFILE_DEV_PATH%" "dev"
    ) else (
        call :build_image "%DOCKERFILE_PATH%" "latest"
    )
) else if "%command%"=="run" (
    call :check_prerequisites
    if "%option%"=="dev" (
        call :build_image "%DOCKERFILE_DEV_PATH%" "dev"
        call :run_container "dev"
    ) else (
        call :build_image "%DOCKERFILE_PATH%" "latest"
        call :run_container "latest"
    )
) else if "%command%"=="start" (
    call :check_prerequisites
    call :run_container "latest"
) else if "%command%"=="stop" (
    call :stop_container
) else if "%command%"=="restart" (
    call :stop_container
    timeout /t 2 /nobreak >nul
    call :run_container "latest"
) else if "%command%"=="logs" (
    if "%option%"=="--follow" (
        call :show_logs "true"
    ) else (
        call :show_logs "false"
    )
) else if "%command%"=="status" (
    call :show_status
) else if "%command%"=="clean" (
    call :cleanup
) else if "%command%"=="compose" (
    call :use_compose "%option%"
) else if "%command%"=="" (
    call :show_help
) else if "%command%"=="help" (
    call :show_help
) else if "%command%"=="--help" (
    call :show_help
) else if "%command%"=="-h" (
    call :show_help
) else (
    call :print_error "Unknown command: %command%"
    echo.
    call :show_help
    exit /b 1
)

endlocal 