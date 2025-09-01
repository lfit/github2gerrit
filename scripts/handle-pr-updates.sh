#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Handle PR updates and Change-ID reuse
set -euo pipefail

# Function to log messages
log() {
    echo "::notice::$1"
}

log_error() {
    echo "::error::$1"
}

# Check if this is a PR update action
if [[ "${GITHUB_EVENT_ACTION:-}" != "reopened" && "${GITHUB_EVENT_ACTION:-}" != "synchronize" ]]; then
    log "Not a PR update, skipping Change-ID reuse"
    exit 0
fi

# Check required environment variables
required_vars=("PR_NUMBER" "ORGANIZATION" "PROJECT_REPO_GITHUB")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

# Validate PR_NUMBER is numeric to prevent injection
if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    log_error "Invalid PR_NUMBER: must be numeric"
    exit 1
fi

# Validate ORGANIZATION contains only safe characters
if [[ ! "$ORGANIZATION" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    log_error "Invalid ORGANIZATION: contains unsafe characters"
    exit 1
fi

# Validate PROJECT_REPO_GITHUB contains only safe characters
if [[ ! "$PROJECT_REPO_GITHUB" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    log_error "Invalid PROJECT_REPO_GITHUB: contains unsafe characters"
    exit 1
fi

log "Fetching existing Change-IDs from PR comments"

# Query GitHub API for PR comments
# shellcheck disable=SC2016
if ! gh api graphql --paginate \
    -F number="$PR_NUMBER" \
    -F owner="$ORGANIZATION" \
    -F name="$PROJECT_REPO_GITHUB" \
    -f query='query($name: String!, $owner: String!, $number: Int!) {
        repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
                comments(last: 10) {
                    nodes {
                        body
                        author {
                            login
                        }
                    }
                }
            }
        }
    }' > "comments-$PR_NUMBER.json"; then
    log_error "Failed to fetch PR comments"
    exit 1
fi

# Extract Change-IDs from comments
if jq -r -c '.data.repository.pullRequest.comments.nodes[] | select(.body | contains("Change-Id:")) | .body | match("Change-Id: (?\\<id\\>I[a-f0-9]{40})").captures[0].string' \
    "comments-$PR_NUMBER.json" > "reuse-cids-$PR_NUMBER.txt"; then

    change_id_count=$(wc -l < "reuse-cids-$PR_NUMBER.txt")

    if [[ "$change_id_count" -gt 0 ]]; then
        log "Found $change_id_count existing Change-ID(s) for reuse"

        # Show the Change-IDs found
        while IFS= read -r cid; do
            log "Found Change-ID: $cid"
        done < "reuse-cids-$PR_NUMBER.txt"
    else
        log "No existing Change-IDs found in PR comments"
    fi
else
    log_error "Failed to extract Change-IDs from PR comments"
    exit 1
fi

log "Change-ID reuse handling completed"
