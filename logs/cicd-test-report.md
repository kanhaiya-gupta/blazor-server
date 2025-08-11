# CI/CD Local Test Report

**Generated:** 2025-08-04 01:05:24  
**Project:** AASX Blazor Server Standalone  
**Test Duration:** 380 seconds

## Summary

- **Total Tests:** 17
- **Passed:** 10
- **Failed:** 2
- **Skipped:** 5
- **Success Rate:** 58%

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

- **CRITICAL:** Fix failed tests before pushing to GitHub
- Review log files in `/c/Users/kanha/Independent_Research/aas-data-modeling/server/logs` for detailed error information

- **OPTIONAL:** Consider installing missing tools for complete testing

## Log Files

- **Main Log:** `/c/Users/kanha/Independent_Research/aas-data-modeling/server/logs/cicd-test.log`
- **Build Logs:** `/c/Users/kanha/Independent_Research/aas-data-modeling/server/logs/dotnet-*.log`
- **Docker Logs:** `/c/Users/kanha/Independent_Research/aas-data-modeling/server/logs/docker-*.log`
- **Security Logs:** `/c/Users/kanha/Independent_Research/aas-data-modeling/server/logs/trivy-*.log`

