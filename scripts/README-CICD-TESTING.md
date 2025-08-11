# CI/CD Local Testing Scripts

This directory contains scripts to test GitHub Actions workflows locally before pushing to GitHub, ensuring that your CI/CD pipeline will work correctly.

## Overview

The local testing scripts validate all aspects of the CI/CD pipeline including:
- Prerequisites and dependencies
- Workflow file validation
- .NET build process
- Docker build process
- Security scanning
- Integration testing

## Scripts

### Linux/macOS
- `test-cicd-local.sh` - Main testing script for Unix-like systems

### Windows
- `test-cicd-local.bat` - Main testing script for Windows systems

## Prerequisites

### Required Tools

1. **Docker** - Container platform
   ```bash
   # Ubuntu/Debian
   sudo apt-get install docker.io
   
   # macOS
   brew install docker
   
   # Windows
   # Download from https://www.docker.com/products/docker-desktop
   ```

2. **.NET SDK 8.0** - .NET development platform
   ```bash
   # Ubuntu/Debian
   wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
   sudo dpkg -i packages-microsoft-prod.deb
   sudo apt-get update
   sudo apt-get install -y dotnet-sdk-8.0
   
   # macOS
   brew install dotnet
   
   # Windows
   # Download from https://dotnet.microsoft.com/download
   ```

3. **Git** - Version control
   ```bash
   # Ubuntu/Debian
   sudo apt-get install git
   
   # macOS
   brew install git
   
   # Windows
   # Download from https://git-scm.com/download/win
   ```

4. **cURL** - HTTP client
   ```bash
   # Ubuntu/Debian
   sudo apt-get install curl
   
   # macOS
   brew install curl
   
   # Windows
   # Usually pre-installed, or download from https://curl.se/windows/
   ```

5. **jq** - JSON processor
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # macOS
   brew install jq
   
   # Windows (using Chocolatey)
   choco install jq
   
   # Windows (using winget)
   winget install jqlang.jq
   
   # Windows (manual)
   # Download from https://stedolan.github.io/jq/download/
   ```

### Optional Tools

1. **act** - GitHub Actions local runner
   ```bash
   # Linux/macOS
   curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
   
   # Windows
   # Download from https://github.com/nektos/act/releases
   ```

2. **Trivy** - Security scanner
   ```bash
   # Linux/macOS
   curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
   
   # Windows
   # Download from https://github.com/aquasecurity/trivy/releases
   ```

3. **yamllint** - YAML linter
   ```bash
   # Ubuntu/Debian
   sudo apt-get install yamllint
   
   # macOS
   brew install yamllint
   
   # Windows
   pip install yamllint
   ```

## Usage

### Running the Tests

#### Linux/macOS
```bash
# Make script executable (first time only)
chmod +x scripts/test-cicd-local.sh

# Run the tests
./scripts/test-cicd-local.sh
```

#### Windows
```cmd
# Run the tests
scripts\test-cicd-local.bat
```

### What the Script Tests

1. **Prerequisites Check**
   - Verifies all required tools are installed
   - Checks tool versions and availability

2. **Environment Setup**
   - Creates necessary test directories
   - Sets up test data

3. **Workflow Validation**
   - Validates YAML syntax of workflow files
   - Checks for required workflow files

4. **Build Process Testing**
   - Tests .NET restore, build, and publish
   - Tests Docker build for both production and development images
   - Validates Docker Compose configuration

5. **Security & Quality Checks**
   - Checks for vulnerable packages
   - Checks for outdated packages
   - Runs Trivy security scans (if available)

6. **Integration Testing**
   - Tests container startup and responsiveness
   - Validates service endpoints

7. **GitHub Actions Local Testing**
   - Uses `act` to test workflows locally (if available)

## Output

### Console Output
The script provides colored, real-time feedback:
- `[SUCCESS]` - Tests that passed
- `[ERROR]` - Tests that failed
- `[WARNING]` - Tests that were skipped
- `[INFO]` - General information
- `[STEP]` - Current test step

### Log Files
All test results are logged to the `logs/` directory:
- `cicd-test.log` - Main test log
- `dotnet-*.log` - .NET build logs
- `docker-*.log` - Docker build logs
- `trivy-*.log` - Security scan logs
- `cicd-test-report.md` - Detailed test report

### Test Report
A comprehensive Markdown report is generated with:
- Test summary and statistics
- Detailed results for each test category
- Recommendations for fixing issues
- Links to relevant log files

## Exit Codes

- `0` - All tests passed, ready to push to GitHub
- `1` - Some tests failed, fix issues before pushing

## Troubleshooting

### Common Issues

1. **Missing jq on Windows**
   ```cmd
   # Install using Chocolatey
   choco install jq
   
   # Or download manually from https://stedolan.github.io/jq/download/
   ```

2. **Docker not running**
   ```bash
   # Start Docker service
   sudo systemctl start docker  # Linux
   # Or start Docker Desktop on Windows/macOS
   ```

3. **Permission denied on script**
   ```bash
   chmod +x scripts/test-cicd-local.sh
   ```

4. **Port 5001 already in use**
   ```bash
   # Find and stop the process using port 5001
   lsof -ti:5001 | xargs kill -9  # Linux/macOS
   netstat -ano | findstr :5001   # Windows
   ```

### Getting Help

1. Check the log files in `logs/` directory for detailed error information
2. Review the test report at `logs/cicd-test-report.md`
3. Ensure all prerequisites are installed correctly
4. Verify Docker is running and accessible

## Integration with Development Workflow

### Pre-commit Testing
Add to your development workflow:
```bash
# Before committing changes
./scripts/test-cicd-local.sh
if [ $? -eq 0 ]; then
    git add .
    git commit -m "Your commit message"
else
    echo "CI/CD tests failed. Fix issues before committing."
    exit 1
fi
```

### Pre-push Testing
Add to your `.git/hooks/pre-push`:
```bash
#!/bin/bash
./scripts/test-cicd-local.sh
if [ $? -ne 0 ]; then
    echo "CI/CD tests failed. Fix issues before pushing."
    exit 1
fi
```

## Customization

### Adding New Tests
To add new tests, modify the script and add new test functions:

```bash
# Add new test function
test_new_feature() {
    print_status "HEADER" "Testing New Feature"
    
    # Your test logic here
    if [ condition ]; then
        log_test_result "New Feature Test" "PASS" "Feature working correctly"
    else
        log_test_result "New Feature Test" "FAIL" "Feature not working"
    fi
}

# Call in main function
test_new_feature
```

### Modifying Test Parameters
Edit the configuration section at the top of the script:
```bash
# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Add your custom parameters here
```

## Best Practices

1. **Run tests before every push** to GitHub
2. **Fix issues immediately** when tests fail
3. **Keep dependencies updated** to avoid security issues
4. **Review test reports** to understand what was tested
5. **Add new tests** when adding new features or workflows

## Contributing

When adding new CI/CD workflows or modifying existing ones:
1. Update the test scripts to cover new functionality
2. Test locally before pushing changes
3. Update this README if new prerequisites are added
4. Ensure backward compatibility with existing tests 