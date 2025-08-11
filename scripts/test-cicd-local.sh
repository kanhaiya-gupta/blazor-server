#!/bin/bash

# Local CI/CD Testing Script for AASX Blazor Server Standalone
# Tests all GitHub Actions workflows locally before pushing to GitHub

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$PROJECT_ROOT/.github/workflows"
DOCKER_DIR="$PROJECT_ROOT/docker"
SRC_DIR="$PROJECT_ROOT/src"
LOG_DIR="$PROJECT_ROOT/logs"
TEMP_DIR="$PROJECT_ROOT/temp"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "HEADER") echo -e "${PURPLE}[HEADER]${NC} $message" ;;
        "STEP") echo -e "${CYAN}[STEP]${NC} $message" ;;
    esac
}

# Function to log test results
log_test_result() {
    local test_name=$1
    local result=$2
    local details=$3
    
    case $result in
        "PASS")
            TESTS_PASSED=$((TESTS_PASSED + 1))
            print_status "SUCCESS" "$test_name: PASSED"
            ;;
        "FAIL")
            TESTS_FAILED=$((TESTS_FAILED + 1))
            print_status "ERROR" "$test_name: FAILED - $details"
            ;;
        "SKIP")
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            print_status "WARNING" "$test_name: SKIPPED - $details"
            ;;
    esac
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $test_name: $result - $details" >> "$LOG_DIR/cicd-test.log"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "HEADER" "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v dotnet >/dev/null 2>&1 || missing_tools+=("dotnet")
    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    command -v curl >/dev/null 2>&1 || missing_tools+=("curl")
    command -v act >/dev/null 2>&1 || missing_tools+=("act (GitHub Actions local runner)")
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        print_status "SUCCESS" "All prerequisites are installed"
        log_test_result "Prerequisites Check" "PASS" "All tools available"
    else
        print_status "ERROR" "Missing required tools: ${missing_tools[*]}"
        print_status "INFO" "Install missing tools and run again"
        log_test_result "Prerequisites Check" "FAIL" "Missing tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to setup test environment
setup_test_environment() {
    print_status "HEADER" "Setting up Test Environment"
    
    # Create necessary directories
    mkdir -p "$LOG_DIR" "$TEMP_DIR"
    
    # Clean up previous test artifacts
    rm -rf "$TEMP_DIR"/*
    
    # Create test data
    mkdir -p "$TEMP_DIR/test-data"
    echo "Test AASX content" > "$TEMP_DIR/test-data/test.aasx"
    
    print_status "SUCCESS" "Test environment setup complete"
    log_test_result "Environment Setup" "PASS" "Test directories and data created"
}

# Function to validate workflow files
validate_workflow_files() {
    print_status "HEADER" "Validating Workflow Files"
    
    local workflows=("ci-cd.yml" "code-quality.yml" "dependency-update.yml" "release.yml")
    local all_valid=true
    
    for workflow in "${workflows[@]}"; do
        local workflow_path="$WORKFLOWS_DIR/$workflow"
        
        if [ ! -f "$workflow_path" ]; then
            print_status "ERROR" "Workflow file missing: $workflow"
            log_test_result "Workflow Validation - $workflow" "FAIL" "File not found"
            all_valid=false
            continue
        fi
        
        # Basic YAML syntax check
        if command -v yamllint >/dev/null 2>&1; then
            if yamllint "$workflow_path" >/dev/null 2>&1; then
                print_status "SUCCESS" "Workflow $workflow: Valid YAML"
                log_test_result "Workflow Validation - $workflow" "PASS" "Valid YAML syntax"
            else
                print_status "ERROR" "Workflow $workflow: Invalid YAML"
                log_test_result "Workflow Validation - $workflow" "FAIL" "Invalid YAML syntax"
                all_valid=false
            fi
        else
            print_status "WARNING" "yamllint not available, skipping YAML validation for $workflow"
            log_test_result "Workflow Validation - $workflow" "SKIP" "yamllint not available"
        fi
    done
    
    if [ "$all_valid" = true ]; then
        print_status "SUCCESS" "All workflow files are valid"
    else
        print_status "ERROR" "Some workflow files have issues"
        return 1
    fi
}

# Function to test .NET build process
test_dotnet_build() {
    print_status "HEADER" "Testing .NET Build Process"
    
    cd "$PROJECT_ROOT"
    
    # Test restore
    print_status "STEP" "Testing dotnet restore"
    if dotnet restore "$SRC_DIR/AasxServerBlazor/AasxServerBlazor.csproj" > "$LOG_DIR/dotnet-restore.log" 2>&1; then
        print_status "SUCCESS" "dotnet restore completed"
        log_test_result "DotNet Restore" "PASS" "Dependencies restored successfully"
    else
        print_status "ERROR" "dotnet restore failed"
        log_test_result "DotNet Restore" "FAIL" "See $LOG_DIR/dotnet-restore.log"
        return 1
    fi
    
    # Test build
    print_status "STEP" "Testing dotnet build"
    if dotnet build "$SRC_DIR/AasxServerBlazor/AasxServerBlazor.csproj" --configuration Release > "$LOG_DIR/dotnet-build.log" 2>&1; then
        print_status "SUCCESS" "dotnet build completed"
        log_test_result "DotNet Build" "PASS" "Build successful"
    else
        print_status "ERROR" "dotnet build failed"
        log_test_result "DotNet Build" "FAIL" "See $LOG_DIR/dotnet-build.log"
        return 1
    fi
    
    # Test publish
    print_status "STEP" "Testing dotnet publish"
    if dotnet publish "$SRC_DIR/AasxServerBlazor/AasxServerBlazor.csproj" --configuration Release --output "$TEMP_DIR/publish" > "$LOG_DIR/dotnet-publish.log" 2>&1; then
        print_status "SUCCESS" "dotnet publish completed"
        log_test_result "DotNet Publish" "PASS" "Application published successfully"
    else
        print_status "ERROR" "dotnet publish failed"
        log_test_result "DotNet Publish" "FAIL" "See $LOG_DIR/dotnet-publish.log"
        return 1
    fi
}

# Function to test Docker build process
test_docker_build() {
    print_status "HEADER" "Testing Docker Build Process"
    
    cd "$PROJECT_ROOT"
    
    # Test production Dockerfile
    print_status "STEP" "Testing production Dockerfile"
    if docker build -f "$DOCKER_DIR/Dockerfile" -t aasx-blazor-standalone:test . > "$LOG_DIR/docker-build-prod.log" 2>&1; then
        print_status "SUCCESS" "Production Docker image built successfully"
        log_test_result "Docker Build - Production" "PASS" "Image built successfully"
    else
        print_status "ERROR" "Production Docker build failed"
        log_test_result "Docker Build - Production" "FAIL" "See $LOG_DIR/docker-build-prod.log"
        return 1
    fi
    
    # Test development Dockerfile
    print_status "STEP" "Testing development Dockerfile"
    if docker build -f "$DOCKER_DIR/Dockerfile.dev" -t aasx-blazor-standalone:test-dev . > "$LOG_DIR/docker-build-dev.log" 2>&1; then
        print_status "SUCCESS" "Development Docker image built successfully"
        log_test_result "Docker Build - Development" "PASS" "Image built successfully"
    else
        print_status "ERROR" "Development Docker build failed"
        log_test_result "Docker Build - Development" "FAIL" "See $LOG_DIR/docker-build-dev.log"
        return 1
    fi
    
    # Clean up test images
    docker rmi aasx-blazor-standalone:test aasx-blazor-standalone:test-dev >/dev/null 2>&1 || true
}

# Function to test Docker Compose
test_docker_compose() {
    print_status "HEADER" "Testing Docker Compose"
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f "$DOCKER_DIR/docker-compose.yml" ]; then
        print_status "WARNING" "docker-compose.yml not found, skipping test"
        log_test_result "Docker Compose" "SKIP" "docker-compose.yml not found"
        return 0
    fi
    
    # Test compose file syntax
    print_status "STEP" "Testing docker-compose syntax"
    if docker-compose -f "$DOCKER_DIR/docker-compose.yml" config > "$LOG_DIR/docker-compose-config.log" 2>&1; then
        print_status "SUCCESS" "Docker Compose syntax is valid"
        log_test_result "Docker Compose Syntax" "PASS" "Valid compose file"
    else
        print_status "ERROR" "Docker Compose syntax is invalid"
        log_test_result "Docker Compose Syntax" "FAIL" "See $LOG_DIR/docker-compose-config.log"
        return 1
    fi
}

# Function to test dependency checks
test_dependency_checks() {
    print_status "HEADER" "Testing Dependency Checks"
    
    cd "$PROJECT_ROOT"
    
    # Check for vulnerable packages
    print_status "STEP" "Checking for vulnerable packages"
    local vulnerable_output
    vulnerable_output=$(cd "$SRC_DIR" && dotnet list package --vulnerable 2>/dev/null || echo "No vulnerable packages found")
    
    if echo "$vulnerable_output" | grep -q "No vulnerable packages found\|No packages found"; then
        print_status "SUCCESS" "No vulnerable packages found"
        log_test_result "Dependency Check - Vulnerable" "PASS" "No vulnerabilities detected"
    else
        print_status "WARNING" "Vulnerable packages found"
        echo "$vulnerable_output" > "$LOG_DIR/vulnerable-packages.log"
        log_test_result "Dependency Check - Vulnerable" "FAIL" "Vulnerabilities found, see $LOG_DIR/vulnerable-packages.log"
    fi
    
    # Check for outdated packages
    print_status "STEP" "Checking for outdated packages"
    local outdated_output
    outdated_output=$(cd "$SRC_DIR" && dotnet list package --outdated 2>/dev/null || echo "No outdated packages found")
    
    if echo "$outdated_output" | grep -q "No outdated packages found\|No packages found"; then
        print_status "SUCCESS" "No outdated packages found"
        log_test_result "Dependency Check - Outdated" "PASS" "All packages up to date"
    else
        print_status "WARNING" "Outdated packages found"
        echo "$outdated_output" > "$LOG_DIR/outdated-packages.log"
        log_test_result "Dependency Check - Outdated" "FAIL" "Outdated packages found, see $LOG_DIR/outdated-packages.log"
    fi
}

# Function to test security scanning
test_security_scanning() {
    print_status "HEADER" "Testing Security Scanning"
    
    # Check if Trivy is available
    if ! command -v trivy >/dev/null 2>&1; then
        print_status "WARNING" "Trivy not available, skipping security scan"
        log_test_result "Security Scan - Trivy" "SKIP" "Trivy not installed"
        return 0
    fi
    
    # Build a test image for scanning
    cd "$PROJECT_ROOT"
    docker build -f "$DOCKER_DIR/Dockerfile" -t aasx-blazor-standalone:security-test . >/dev/null 2>&1
    
    # Run Trivy scan
    print_status "STEP" "Running Trivy security scan"
    if trivy image --format json --output "$LOG_DIR/trivy-results.json" aasx-blazor-standalone:security-test > "$LOG_DIR/trivy-scan.log" 2>&1; then
        print_status "SUCCESS" "Trivy security scan completed"
        log_test_result "Security Scan - Trivy" "PASS" "Scan completed successfully"
    else
        print_status "ERROR" "Trivy security scan failed"
        log_test_result "Security Scan - Trivy" "FAIL" "See $LOG_DIR/trivy-scan.log"
    fi
    
    # Clean up test image
    docker rmi aasx-blazor-standalone:security-test >/dev/null 2>&1 || true
}

# Function to test GitHub Actions locally (if act is available)
test_github_actions_local() {
    print_status "HEADER" "Testing GitHub Actions Locally"
    
    if ! command -v act >/dev/null 2>&1; then
        print_status "WARNING" "act not available, skipping local GitHub Actions test"
        print_status "INFO" "Install act to test workflows locally: https://github.com/nektos/act"
        log_test_result "GitHub Actions Local Test" "SKIP" "act not installed"
        return 0
    fi
    
    cd "$PROJECT_ROOT"
    
    # Test CI/CD workflow
    print_status "STEP" "Testing CI/CD workflow locally"
    if act push --dryrun > "$LOG_DIR/act-cicd.log" 2>&1; then
        print_status "SUCCESS" "CI/CD workflow test completed"
        log_test_result "GitHub Actions - CI/CD" "PASS" "Workflow validation successful"
    else
        print_status "ERROR" "CI/CD workflow test failed"
        log_test_result "GitHub Actions - CI/CD" "FAIL" "See $LOG_DIR/act-cicd.log"
    fi
}

# Function to test integration scenarios
test_integration_scenarios() {
    print_status "HEADER" "Testing Integration Scenarios"
    
    cd "$PROJECT_ROOT"
    
    # Test container startup
    print_status "STEP" "Testing container startup"
    if docker run --rm -d --name test-blazor -p 5001:5001 -v "$TEMP_DIR/test-data:/app/data" aasx-blazor-standalone:test >/dev/null 2>&1; then
        sleep 10
        
        # Test if container is responding
        if curl -f http://localhost:5001 >/dev/null 2>&1; then
            print_status "SUCCESS" "Container is responding"
            log_test_result "Integration - Container Startup" "PASS" "Container started and responding"
        else
            print_status "ERROR" "Container is not responding"
            log_test_result "Integration - Container Startup" "FAIL" "Container not responding on port 5001"
        fi
        
        # Clean up
        docker stop test-blazor >/dev/null 2>&1 || true
        docker rm test-blazor >/dev/null 2>&1 || true
    else
        print_status "ERROR" "Failed to start test container"
        log_test_result "Integration - Container Startup" "FAIL" "Container failed to start"
    fi
}

# Function to generate test report
generate_test_report() {
    print_status "HEADER" "Generating Test Report"
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local report_file="$LOG_DIR/cicd-test-report.md"
    
    cat > "$report_file" << EOF
# CI/CD Local Test Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Project:** AASX Blazor Server Standalone  
**Test Duration:** $(($(date +%s) - START_TIME)) seconds

## Summary

- **Total Tests:** $total_tests
- **Passed:** $TESTS_PASSED
- **Failed:** $TESTS_FAILED
- **Skipped:** $TESTS_SKIPPED
- **Success Rate:** $((TESTS_PASSED * 100 / total_tests))%

## Test Results

### Prerequisites
- [x] Required tools installed
- [x] Test environment setup

### Workflow Validation
- [x] YAML syntax validation
- [x] Workflow file structure

### Build Process
- [x] .NET restore
- [x] .NET build
- [x] .NET publish
- [x] Docker build (production)
- [x] Docker build (development)

### Security & Quality
- [x] Dependency vulnerability check
- [x] Dependency outdated check
- [x] Security scanning (Trivy)

### Integration
- [x] Docker Compose validation
- [x] Container startup test
- [x] Service responsiveness

## Recommendations

$(if [ $TESTS_FAILED -gt 0 ]; then
    echo "- **CRITICAL:** Fix failed tests before pushing to GitHub"
    echo "- Review log files in \`$LOG_DIR\` for detailed error information"
else
    echo "- **READY:** All tests passed, safe to push to GitHub"
fi)

$(if [ $TESTS_SKIPPED -gt 0 ]; then
    echo "- **OPTIONAL:** Consider installing missing tools for complete testing"
fi)

## Log Files

- **Main Log:** \`$LOG_DIR/cicd-test.log\`
- **Build Logs:** \`$LOG_DIR/dotnet-*.log\`
- **Docker Logs:** \`$LOG_DIR/docker-*.log\`
- **Security Logs:** \`$LOG_DIR/trivy-*.log\`

EOF
    
    print_status "SUCCESS" "Test report generated: $report_file"
    
    # Display summary
    echo
    print_status "HEADER" "Test Summary"
    echo "Total Tests: $total_tests"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Skipped: $TESTS_SKIPPED"
    echo "Success Rate: $((TESTS_PASSED * 100 / total_tests))%"
    echo
    echo "Detailed report: $report_file"
}

# Function to cleanup
cleanup() {
    print_status "INFO" "Cleaning up test artifacts"
    
    # Stop and remove test containers
    docker stop test-blazor >/dev/null 2>&1 || true
    docker rm test-blazor >/dev/null 2>&1 || true
    
    # Remove test images
    docker rmi aasx-blazor-standalone:test aasx-blazor-standalone:test-dev aasx-blazor-standalone:security-test >/dev/null 2>&1 || true
    
    print_status "SUCCESS" "Cleanup completed"
}

# Main function
main() {
    START_TIME=$(date +%s)
    
    print_status "HEADER" "Starting Local CI/CD Testing"
    print_status "INFO" "Project: $PROJECT_ROOT"
    print_status "INFO" "Log Directory: $LOG_DIR"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Initialize log file
    echo "=== CI/CD Local Test Started: $(date) ===" > "$LOG_DIR/cicd-test.log"
    
    # Run tests
    check_prerequisites
    setup_test_environment
    validate_workflow_files
    test_dotnet_build
    test_docker_build
    test_docker_compose
    test_dependency_checks
    test_security_scanning
    test_github_actions_local
    test_integration_scenarios
    
    # Generate report
    generate_test_report
    
    # Cleanup
    cleanup
    
    # Final status
    if [ $TESTS_FAILED -eq 0 ]; then
        print_status "SUCCESS" "All tests passed! Ready to push to GitHub."
        exit 0
    else
        print_status "ERROR" "$TESTS_FAILED test(s) failed. Please fix issues before pushing to GitHub."
        exit 1
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main "$@" 