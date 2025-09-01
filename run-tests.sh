#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

set -euo pipefail

# Local testing script for github2gerrit workflows

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

# Check if act is installed
check_act() {
    if command -v act &> /dev/null; then
        log "act version: $(act --version)"
    elif gh act --version &> /dev/null; then
        log "gh act version: $(gh act --version)"
        # Create alias for act using gh extension
        alias act='gh act'
    else
        error "act is not installed. Please install it first:"
        echo "  gh extension install https://github.com/nektos/gh-act"
        echo "  # or brew install act  # macOS"
        echo "  # or download from https://github.com/nektos/act/releases"
        exit 1
    fi
}

# Create test secrets and environment files
setup_test_env() {
    log "Setting up test environment..."

    # Create secrets file for testing
    cat > .secrets << 'EOF'
# TEST-ONLY FAKE KEY, NOT A REAL PRIVATE KEY
GERRIT_SSH_PRIVKEY_G2G=FAKE-PRIVATE-KEY-BEGIN
fake-test-key-content-for-local-testing-only
FAKE-PRIVATE-KEY-END
EOF

    # Create environment variables file
    cat > .env << 'EOF'
GERRIT_KNOWN_HOSTS=review.test.org ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...
GERRIT_SSH_USER_G2G=test-user
GERRIT_SSH_USER_G2G_EMAIL=test@example.com
ORGANIZATION=test-org
ISSUEID=false
REVIEWERS_EMAIL=reviewers@test.org
EOF

    log "Test environment files created (.secrets, .env)"
}

# Run shell script tests
run_shell_tests() {
    log "Running shell script tests..."
    gh act -j shell-tests --secret-file .secrets --env-file .env
}

# Run matrix tests
run_matrix_tests() {
    log "Running matrix tests..."
    gh act -j matrix-tests --secret-file .secrets --env-file .env
}

# Run integration tests
run_integration_tests() {
    log "Running integration tests..."
    gh act -j integration-tests --secret-file .secrets --env-file .env
}

# Run comprehensive integration tests
run_comprehensive_tests() {
    local test_level="${1:-basic}"
    log "Running comprehensive integration tests (level: $test_level)..."

    gh act workflow_dispatch \
        -W .github/workflows/integration-tests.yaml \
        --input test_level="$test_level" \
        --secret-file .secrets \
        --env-file .env
}

# Test specific workflow
test_workflow() {
    local workflow="${1:-v1}"
    log "Testing $workflow workflow..."

    if [[ "$workflow" == "v1" ]]; then
        # Test V1 (composite action)
        gh act -j compose-github2gerrit \
            -W .github/workflows/github2gerrit.yaml \
            --secret-file .secrets \
            --env-file .env
    elif [[ "$workflow" == "v2" ]]; then
        # Test V2 (reusable workflow)
        gh act workflow_call \
            -W .github/workflows/github2gerrit-v2.yaml \
            --input SUBMIT_SINGLE_COMMITS=false \
            --input USE_PR_AS_COMMIT=false \
            --input FETCH_DEPTH=10 \
            --secret-file .secrets \
            --env-file .env
    else
        error "Unknown workflow: $workflow. Use 'v1' or 'v2'"
        exit 1
    fi
}

# Validate scripts syntax
validate_scripts() {
    log "Validating shell scripts syntax..."

    if [[ -d scripts ]]; then
        find scripts -name "*.sh" -type f | while read -r script; do
            log "Checking syntax: $script"
            bash -n "$script" || error "Syntax error in $script"
        done
    else
        warn "scripts directory not found"
    fi
}


# Clean up test files
cleanup() {
    log "Cleaning up test files..."
    rm -f .secrets .env
    rm -f ./*.txt ./*.json # Remove any test artifacts
}

# Show usage
usage() {
    cat << 'EOF'
Usage: ./run-tests.sh [COMMAND] [OPTIONS]

Commands:
  setup           Setup test environment files (.secrets, .env)
  shell           Run shell script tests
  matrix          Run matrix tests
  integration     Run integration tests
  comprehensive   Run comprehensive integration tests
                  Options: basic, comprehensive, regression
  workflow        Test specific workflow (v1|v2)
  validate        Validate shell script syntax
  all             Run all tests
  cleanup         Remove test environment files

Examples:
  ./run-tests.sh setup
  ./run-tests.sh shell
  ./run-tests.sh comprehensive basic
  ./run-tests.sh comprehensive regression
  ./run-tests.sh workflow v2
  ./run-tests.sh all
  ./run-tests.sh cleanup

EOF
}

# Main execution
main() {
    check_act

    case "${1:-help}" in
        setup)
            setup_test_env
            ;;
        shell)
            setup_test_env
            run_shell_tests
            ;;
        matrix)
            setup_test_env
            run_matrix_tests
            ;;
        integration)
            setup_test_env
            run_integration_tests
            ;;
        comprehensive)
            setup_test_env
            run_comprehensive_tests "${2:-basic}"
            ;;
        workflow)
            setup_test_env
            test_workflow "${2:-v1}"
            ;;
        validate)
            validate_scripts
            ;;
        all)
            setup_test_env
            run_shell_tests
            run_matrix_tests
            run_integration_tests
            log "All basic tests completed!"
            ;;
        cleanup)
            cleanup
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Handle script interruption
trap cleanup EXIT

main "$@"
