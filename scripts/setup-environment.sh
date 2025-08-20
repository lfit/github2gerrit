#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Setup environment variables for github2gerrit workflow
set -euo pipefail

# Function to log messages
log() {
    echo "::notice::$1"
}

log_error() {
    echo "::error::$1"
}

# Function to set environment variable
set_env_var() {
    local name="$1"
    local value="$2"
    echo "${name}=${value}" >> "$GITHUB_ENV"
    log "Set ${name}=${value}"
}

# Set PR number
PR_NUMBER="${GITHUB_EVENT_PULL_REQUEST_NUMBER:-${GITHUB_EVENT_ISSUE_NUMBER:-}}"
if [[ -n "$PR_NUMBER" ]]; then
    set_env_var "PR_NUMBER" "$PR_NUMBER"
else
    log_error "Could not determine PR number"
    exit 1
fi

# Set Gerrit branch
GERRIT_BRANCH="${GITHUB_BASE_REF:-master}"
set_env_var "GERRIT_BRANCH" "$GERRIT_BRANCH"

log "Environment setup completed"
