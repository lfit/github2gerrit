<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2024 The Linux Foundation
-->

# Testing Strategy for github2gerrit

This document outlines the comprehensive multi-layered testing approach implemented for the github2gerrit repository.

## Testing Architecture

### 1. Shell Script Unit Tests (`shell-tests`)

- **Purpose**: Validate bash script functionality and URL parsing logic
- **Runtime**: 3 minutes
- **Components**:
  - Shellcheck validation for all `.sh` files
  - Unit tests for `gerrit_query_parse.sh` functions:
    - `extract_hostname()` - Parse Gerrit hostnames from URLs
    - `extract_change_number()` - Extract change numbers from URLs
    - `extract_project()` - Extract project names from URLs
  - Input validation testing (malformed URLs, missing arguments)
  - Edge case handling (empty strings, invalid formats)

### 2. Matrix Tests (`matrix-tests`)

- **Purpose**: Cross-platform compatibility testing
- **Runtime**: 5 minutes per matrix combination
- **Matrix Dimensions**:
  - **OS**: `ubuntu-latest`, `ubuntu-22.04`, `ubuntu-20.04`
  - **Action Type**: `composite`, `reusable`
- **Test Cases**:
  - Dependency installation (git-review, jq, python3)
  - Conflicting input validation (`SUBMIT_SINGLE_COMMITS` + `USE_PR_AS_COMMIT`)
  - Missing `.gitreview` file handling
  - Boolean input validation for workflow calls

### 3. Integration Tests (`integration-tests`)

- **Purpose**: End-to-end workflow testing with mock data
- **Runtime**: 8 minutes
- **Test Scenarios**:
  - Valid composite action execution with mock SSH environment
  - Malformed input handling (invalid booleans, empty required fields)
  - SSH connection timeout testing
  - `.gitreview` parsing edge cases
  - Change-ID format validation
  - JSON response parsing with jq

### 4. Dry Run Integration (`dry-run-integration`)

- **Purpose**: Real Gerrit connectivity testing (when secrets available)
- **Runtime**: 10 minutes
- **Conditions**: Only runs in `lfit/github2gerrit` repository
- **Features**:
  - Uses actual repository secrets and variables
  - Tests real SSH connections (with failure tolerance)
  - Validates complete workflow execution
  - Generates test results summary

### 5. Security Validation (`security-validation`)

- **Purpose**: Security and input sanitization testing
- **Runtime**: 3 minutes
- **Checks**:
  - Secret exposure detection in logs
  - Hardcoded credential scanning
  - Input injection testing (command injection, shell injection)
  - Safe handling of malicious inputs

## Test Infrastructure

### Test Files Structure

```text
tests/
├── test-functions.sh          # Unit test runner
├── fixtures/
│   ├── sample-gerrit-response.json  # Mock Gerrit API response
│   └── sample-gitreview            # Sample .gitreview configuration
└── ...
```

### Key Testing Patterns

1. **Continue-on-Error**: All potentially failing tests use `continue-on-error: true`
2. **Timeout Protection**: Every job has explicit timeout limits
3. **Mock Data**: Uses realistic test data without external dependencies
4. **Input Validation**: Comprehensive testing of all input combinations
5. **Cross-Platform**: Matrix testing across Ubuntu LTS versions

## Running Tests

### Locally

```bash
# Run shell script unit tests
./tests/test-functions.sh

# Run shellcheck
shellcheck gerrit_query_parse.sh

# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/testing.yaml'))"
```

### GitHub Actions

Tests run automatically on:

- Push to `main` branch
- Pull requests to `main` branch
- Manual trigger via `workflow_dispatch`

## Test Coverage

### Composite Action (`action.yaml`)

- ✅ Input validation (conflicting options)
- ✅ Dependency installation
- ✅ `.gitreview` file handling
- ✅ SSH environment setup
- ✅ Git operations (clone, commit, review)
- ✅ Error conditions

### Reusable Workflow (`github2gerrit.yaml`)

- ✅ Workflow input validation
- ✅ Boolean parameter handling
- ✅ Secret management
- ✅ Environment variable setup
- ✅ Concurrency control

### Shell Scripts

- ✅ URL parsing functions
- ✅ JSON response handling
- ✅ SSH command construction
- ✅ Error handling and exit codes
- ✅ Input sanitization

## Quality Gates

All tests must pass before:

- Merging pull requests
- Creating releases
- Deploying to production environments

## Continuous Integration

The testing workflow integrates with:

- **Pre-commit hooks**: Syntax and quality validation
- **GitHub Actions**: Automated testing on every change
- **Security scanning**: Credential and injection detection
- **Code quality tools**: shellcheck, yamllint, actionlint

## Future Enhancements

Planned testing improvements:

- Performance benchmarking for large repositories
- Integration with real Gerrit test instances
- Automated dependency vulnerability scanning
- Extended cross-platform support (macOS, Windows)
