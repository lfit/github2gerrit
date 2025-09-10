#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Setup git configuration for Gerrit integration
set -euo pipefail

# Function to log messages
log() {
    echo "::notice::$1"
}

log_error() {
    echo "::error::$1"
}

# Validate required environment variables
required_vars=("GERRIT_SSH_USER_G2G" "GERRIT_SSH_USER_G2G_EMAIL" "PROJECT_REPO_GERRIT")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

log "Setting up git configuration for Gerrit"

# Setup global git config required by git-review
git config --global gitreview.username "$GERRIT_SSH_USER_G2G"
git config --global user.name "$GERRIT_SSH_USER_G2G"
git config --global user.email "$GERRIT_SSH_USER_G2G_EMAIL"

# Workaround for git-review failing to copy commit-msg hook to submodules
git config core.hooksPath "$(git rev-parse --show-toplevel)/.git/hooks"

log "Initializing git-review"

# Initialize gerrit repo
if git review -s -v; then
    log "Git-review setup successful"
else
    log_error "Git-review setup failed"
    exit 1
fi

# Print remote settings for debugging
log "Git remotes configured:"
git remote -v

log "Git setup completed"
