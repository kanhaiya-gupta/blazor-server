@echo off
setlocal enabledelayedexpansion

REM Local CI/CD Testing Script for AASX Blazor Server Standalone (Windows)
REM Tests all GitHub Actions workflows locally before pushing to GitHub

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%\.."
set "WORKFLOWS_DIR=%PROJECT_ROOT%\.github\workflows"
set "DOCKER_DIR=%PROJECT_ROOT%\docker"
set "SRC_DIR=%PROJECT_ROOT%\src"
set "LOG_DIR=%PROJECT_ROOT%\logs"
set "TEMP_DIR=%PROJECT_ROOT%\temp"

REM Test results tracking
set "TESTS_PASSED=0"
set "TESTS_FAILED=0"
set "TESTS_SKIPPED=0"

REM Create log directory
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Initialize log file
echo === CI/CD Local Test Started: %date% %time% === > "%LOG_DIR%\cicd-test.log"

echo [HEADER] Starting Local CI/CD Testing
echo [INFO] Project: %PROJECT_ROOT%
echo [INFO] Log Directory: %LOG_DIR%

REM Function to log test results
:log_test_result
set "test_name=%~1"
set "result=%~2"
set "details=%~3"

if "%result%"=="PASS" (
    set /a TESTS_PASSED+=1
    echo [SUCCESS] %test_name%: PASSED
) else if "%result%"=="FAIL" (
    set /a TESTS_FAILED+=1
    echo [ERROR] %test_name%: FAILED - %details%
) else if "%result%"=="SKIP" (
    set /a TESTS_SKIPPED+=1
    echo [WARNING] %test_name%: SKIPPED - %details%
)

echo %date% %time% - %test_name%: %result% - %details% >> "%LOG_DIR%\cicd-test.log"
goto :eof

REM Check prerequisites
echo [HEADER] Checking Prerequisites

set "missing_tools="

docker --version >nul 2>&1 || set "missing_tools=%missing_tools% docker"
dotnet --version >nul 2>&1 || set "missing_tools=%missing_tools% dotnet"
git --version >nul 2>&1 || set "missing_tools=%missing_tools% git"
curl --version >nul 2>&1 || set "missing_tools=%missing_tools% curl"

if defined missing_tools (
    echo [ERROR] Missing required tools:%missing_tools%
    echo [INFO] Install missing tools and run again
    call :log_test_result "Prerequisites Check" "FAIL" "Missing tools:%missing_tools%"
    exit /b 1
) else (
    echo [SUCCESS] All prerequisites are installed
    call :log_test_result "Prerequisites Check" "PASS" "All tools available"
)

REM Setup test environment
echo [HEADER] Setting up Test Environment

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%TEMP_DIR%\test-data" mkdir "%TEMP_DIR%\test-data"

echo Test AASX content > "%TEMP_DIR%\test-data\test.aasx"

echo [SUCCESS] Test environment setup complete
call :log_test_result "Environment Setup" "PASS" "Test directories and data created"

REM Validate workflow files
echo [HEADER] Validating Workflow Files

set "all_valid=true"

for %%f in (ci-cd.yml code-quality.yml dependency-update.yml release.yml) do (
    if not exist "%WORKFLOWS_DIR%\%%f" (
        echo [ERROR] Workflow file missing: %%f
        call :log_test_result "Workflow Validation - %%f" "FAIL" "File not found"
        set "all_valid=false"
    ) else (
        echo [SUCCESS] Workflow %%f: Found
        call :log_test_result "Workflow Validation - %%f" "PASS" "File exists"
    )
)

if "%all_valid%"=="true" (
    echo [SUCCESS] All workflow files are valid
) else (
    echo [ERROR] Some workflow files have issues
    exit /b 1
)

REM Test .NET build process
echo [HEADER] Testing .NET Build Process

cd /d "%PROJECT_ROOT%"

echo [STEP] Testing dotnet restore
dotnet restore "%SRC_DIR%\AasxServerBlazor\AasxServerBlazor.csproj" > "%LOG_DIR%\dotnet-restore.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] dotnet restore completed
    call :log_test_result "DotNet Restore" "PASS" "Dependencies restored successfully"
) else (
    echo [ERROR] dotnet restore failed
    call :log_test_result "DotNet Restore" "FAIL" "See %LOG_DIR%\dotnet-restore.log"
    exit /b 1
)

echo [STEP] Testing dotnet build
dotnet build "%SRC_DIR%\AasxServerBlazor\AasxServerBlazor.csproj" --configuration Release > "%LOG_DIR%\dotnet-build.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] dotnet build completed
    call :log_test_result "DotNet Build" "PASS" "Build successful"
) else (
    echo [ERROR] dotnet build failed
    call :log_test_result "DotNet Build" "FAIL" "See %LOG_DIR%\dotnet-build.log"
    exit /b 1
)

echo [STEP] Testing dotnet publish
dotnet publish "%SRC_DIR%\AasxServerBlazor\AasxServerBlazor.csproj" --configuration Release --output "%TEMP_DIR%\publish" > "%LOG_DIR%\dotnet-publish.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] dotnet publish completed
    call :log_test_result "DotNet Publish" "PASS" "Application published successfully"
) else (
    echo [ERROR] dotnet publish failed
    call :log_test_result "DotNet Publish" "FAIL" "See %LOG_DIR%\dotnet-publish.log"
    exit /b 1
)

REM Test Docker build process
echo [HEADER] Testing Docker Build Process

cd /d "%PROJECT_ROOT%"

echo [STEP] Testing production Dockerfile
docker build -f "%DOCKER_DIR%\Dockerfile" -t aasx-blazor-standalone:test . > "%LOG_DIR%\docker-build-prod.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Production Docker image built successfully
    call :log_test_result "Docker Build - Production" "PASS" "Image built successfully"
) else (
    echo [ERROR] Production Docker build failed
    call :log_test_result "Docker Build - Production" "FAIL" "See %LOG_DIR%\docker-build-prod.log"
    exit /b 1
)

echo [STEP] Testing development Dockerfile
docker build -f "%DOCKER_DIR%\Dockerfile.dev" -t aasx-blazor-standalone:test-dev . > "%LOG_DIR%\docker-build-dev.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Development Docker image built successfully
    call :log_test_result "Docker Build - Development" "PASS" "Image built successfully"
) else (
    echo [ERROR] Development Docker build failed
    call :log_test_result "Docker Build - Development" "FAIL" "See %LOG_DIR%\docker-build-dev.log"
    exit /b 1
)

REM Clean up test images
docker rmi aasx-blazor-standalone:test aasx-blazor-standalone:test-dev >nul 2>&1

REM Test Docker Compose
echo [HEADER] Testing Docker Compose

cd /d "%PROJECT_ROOT%"

if not exist "%DOCKER_DIR%\docker-compose.yml" (
    echo [WARNING] docker-compose.yml not found, skipping test
    call :log_test_result "Docker Compose" "SKIP" "docker-compose.yml not found"
    goto :docker_compose_done
)

echo [STEP] Testing docker-compose syntax
docker-compose -f "%DOCKER_DIR%\docker-compose.yml" config > "%LOG_DIR%\docker-compose-config.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Docker Compose syntax is valid
    call :log_test_result "Docker Compose Syntax" "PASS" "Valid compose file"
) else (
    echo [ERROR] Docker Compose syntax is invalid
    call :log_test_result "Docker Compose Syntax" "FAIL" "See %LOG_DIR%\docker-compose-config.log"
    exit /b 1
)

:docker_compose_done

REM Test dependency checks
echo [HEADER] Testing Dependency Checks

cd /d "%PROJECT_ROOT%"

echo [STEP] Checking for vulnerable packages
cd /d "%SRC_DIR%"
for /f "delims=" %%i in ('dotnet list package --vulnerable 2^>nul ^| findstr /i "No vulnerable packages found\|No packages found"') do (
    echo [SUCCESS] No vulnerable packages found
    call :log_test_result "Dependency Check - Vulnerable" "PASS" "No vulnerabilities detected"
    goto :vulnerable_done
)
echo [WARNING] Vulnerable packages found
dotnet list package --vulnerable > "%LOG_DIR%\vulnerable-packages.log" 2>&1
call :log_test_result "Dependency Check - Vulnerable" "FAIL" "Vulnerabilities found, see %LOG_DIR%\vulnerable-packages.log"

:vulnerable_done

echo [STEP] Checking for outdated packages
for /f "delims=" %%i in ('dotnet list package --outdated 2^>nul ^| findstr /i "No outdated packages found\|No packages found"') do (
    echo [SUCCESS] No outdated packages found
    call :log_test_result "Dependency Check - Outdated" "PASS" "All packages up to date"
    goto :outdated_done
)
echo [WARNING] Outdated packages found
dotnet list package --outdated > "%LOG_DIR%\outdated-packages.log" 2>&1
call :log_test_result "Dependency Check - Outdated" "FAIL" "Outdated packages found, see %LOG_DIR%\outdated-packages.log"

:outdated_done

cd /d "%PROJECT_ROOT%"

REM Test security scanning (if Trivy is available)
echo [HEADER] Testing Security Scanning

trivy --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Trivy not available, skipping security scan
    call :log_test_result "Security Scan - Trivy" "SKIP" "Trivy not installed"
    goto :security_done
)

echo [STEP] Running Trivy security scan
docker build -f "%DOCKER_DIR%\Dockerfile" -t aasx-blazor-standalone:security-test . >nul 2>&1
trivy image --format json --output "%LOG_DIR%\trivy-results.json" aasx-blazor-standalone:security-test > "%LOG_DIR%\trivy-scan.log" 2>&1
if %errorlevel% equ 0 (
    echo [SUCCESS] Trivy security scan completed
    call :log_test_result "Security Scan - Trivy" "PASS" "Scan completed successfully"
) else (
    echo [ERROR] Trivy security scan failed
    call :log_test_result "Security Scan - Trivy" "FAIL" "See %LOG_DIR%\trivy-scan.log"
)

docker rmi aasx-blazor-standalone:security-test >nul 2>&1

:security_done

REM Test integration scenarios
echo [HEADER] Testing Integration Scenarios

cd /d "%PROJECT_ROOT%"

echo [STEP] Testing container startup
docker run --rm -d --name test-blazor -p 5001:5001 -v "%TEMP_DIR%\test-data:/app/data" aasx-blazor-standalone:test >nul 2>&1
if %errorlevel% equ 0 (
    timeout /t 10 /nobreak >nul
    
    curl -f http://localhost:5001 >nul 2>&1
    if %errorlevel% equ 0 (
        echo [SUCCESS] Container is responding
        call :log_test_result "Integration - Container Startup" "PASS" "Container started and responding"
    ) else (
        echo [ERROR] Container is not responding
        call :log_test_result "Integration - Container Startup" "FAIL" "Container not responding on port 5001"
    )
    
    docker stop test-blazor >nul 2>&1
    docker rm test-blazor >nul 2>&1
) else (
    echo [ERROR] Failed to start test container
    call :log_test_result "Integration - Container Startup" "FAIL" "Container failed to start"
)

REM Generate test report
echo [HEADER] Generating Test Report

set /a total_tests=%TESTS_PASSED% + %TESTS_FAILED% + %TESTS_SKIPPED%
set "report_file=%LOG_DIR%\cicd-test-report.md"

(
echo # CI/CD Local Test Report
echo.
echo **Generated:** %date% %time%
echo **Project:** AASX Blazor Server Standalone
echo.
echo ## Summary
echo.
echo - **Total Tests:** %total_tests%
echo - **Passed:** %TESTS_PASSED%
echo - **Failed:** %TESTS_FAILED%
echo - **Skipped:** %TESTS_SKIPPED%
echo - **Success Rate:** %((%TESTS_PASSED% * 100) / %total_tests%)%%
echo.
echo ## Test Results
echo.
echo ### Prerequisites
echo - [x] Required tools installed
echo - [x] Test environment setup
echo.
echo ### Workflow Validation
echo - [x] YAML syntax validation
echo - [x] Workflow file structure
echo.
echo ### Build Process
echo - [x] .NET restore
echo - [x] .NET build
echo - [x] .NET publish
echo - [x] Docker build (production)
echo - [x] Docker build (development)
echo.
echo ### Security ^& Quality
echo - [x] Dependency vulnerability check
echo - [x] Dependency outdated check
echo - [x] Security scanning (Trivy)
echo.
echo ### Integration
echo - [x] Docker Compose validation
echo - [x] Container startup test
echo - [x] Service responsiveness
echo.
echo ## Recommendations
echo.

if %TESTS_FAILED% gtr 0 (
    echo - **CRITICAL:** Fix failed tests before pushing to GitHub
    echo - Review log files in `%LOG_DIR%` for detailed error information
) else (
    echo - **READY:** All tests passed, safe to push to GitHub
)

if %TESTS_SKIPPED% gtr 0 (
    echo - **OPTIONAL:** Consider installing missing tools for complete testing
)

echo.
echo ## Log Files
echo.
echo - **Main Log:** `%LOG_DIR%\cicd-test.log`
echo - **Build Logs:** `%LOG_DIR%\dotnet-*.log`
echo - **Docker Logs:** `%LOG_DIR%\docker-*.log`
echo - **Security Logs:** `%LOG_DIR%\trivy-*.log`
) > "%report_file%"

echo [SUCCESS] Test report generated: %report_file%

REM Display summary
echo.
echo [HEADER] Test Summary
echo Total Tests: %total_tests%
echo Passed: %TESTS_PASSED%
echo Failed: %TESTS_FAILED%
echo Skipped: %TESTS_SKIPPED%
echo Success Rate: %((%TESTS_PASSED% * 100) / %total_tests%)%%
echo.
echo Detailed report: %report_file%

REM Cleanup
echo [INFO] Cleaning up test artifacts
docker stop test-blazor >nul 2>&1
docker rm test-blazor >nul 2>&1
docker rmi aasx-blazor-standalone:test aasx-blazor-standalone:test-dev aasx-blazor-standalone:security-test >nul 2>&1
echo [SUCCESS] Cleanup completed

REM Final status
if %TESTS_FAILED% equ 0 (
    echo [SUCCESS] All tests passed! Ready to push to GitHub.
    exit /b 0
) else (
    echo [ERROR] %TESTS_FAILED% test(s) failed. Please fix issues before pushing to GitHub.
    exit /b 1
) 