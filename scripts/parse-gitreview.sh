#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Parse .gitreview file and set environment variables
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

# Check if .gitreview exists
if [[ -f ".gitreview" ]]; then
    log "Found .gitreview file, parsing configuration"

    # Extract project name
    if project_repo_gerrit_git=$(grep -E "^project" .gitreview | cut -d "=" -f2 2>/dev/null); then
        # Strip .git suffix
        project_repo_gerrit="${project_repo_gerrit_git%%.git}"
        # Convert '/' to '-' for GitHub repo naming
        project_repo_github="${project_repo_gerrit////-}"

        set_env_var "PROJECT_REPO_GERRIT" "$project_repo_gerrit"
        set_env_var "PROJECT_REPO_GITHUB" "$project_repo_github"
    else
        log_error "Could not find project in .gitreview"
        exit 1
    fi

    # Extract Gerrit server
    if gerrit_server=$(grep -oP -m1 '(?<=host=).*' .gitreview 2>/dev/null); then
        set_env_var "GERRIT_SERVER" "$gerrit_server"
    else
        log_error "Could not find host in .gitreview"
        exit 1
    fi

    # Extract Gerrit port (optional, default to 29418)
    if gerrit_server_port=$(grep -oP -m1 '(?<=port=).*' .gitreview 2>/dev/null); then
        set_env_var "GERRIT_SERVER_PORT" "$gerrit_server_port"
    else
        set_env_var "GERRIT_SERVER_PORT" "29418"
    fi

else
    log "No .gitreview file found, using workflow inputs"

    # Use workflow inputs to derive project information
    project_repo_github="${GITHUB_REPOSITORY}"
    if [[ "$GERRIT_PROJECT_INPUT" != "$project_repo_github" ]]; then
        # Remove repo owner name
        project_repo_github="${project_repo_github#*/}"
        # Change any '-' to '/'
        project_repo_gerrit="${project_repo_github//-//}"

        set_env_var "PROJECT_REPO_GITHUB" "$project_repo_github"
        set_env_var "PROJECT_REPO_GERRIT" "$project_repo_gerrit"
    fi

    # Set Gerrit server from inputs
    if [[ -n "${GERRIT_SERVER_INPUT:-}" ]]; then
        set_env_var "GERRIT_SERVER" "$GERRIT_SERVER_INPUT"
    fi

    if [[ -n "${GERRIT_SERVER_PORT_INPUT:-}" ]]; then
        set_env_var "GERRIT_SERVER_PORT" "$GERRIT_SERVER_PORT_INPUT"
    fi
fi

log "Gitreview parsing completed"
