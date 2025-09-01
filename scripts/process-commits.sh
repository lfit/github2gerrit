#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Process PR commits for Gerrit submission
set -euo pipefail

# Function to log messages
log() {
    echo "::notice::$1"
}

log_error() {
    echo "::error::$1"
}

log_debug() {
    echo "::debug::$1"
}

# Check required environment variables
required_vars=("PR_NUMBER" "GERRIT_BRANCH" "GITHUB_EVENT_PULL_REQUEST_BASE_SHA" "GITHUB_SHA")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

# Get PR commit count
log "Getting PR commit information"
# Validate PR_NUMBER is numeric to prevent command injection
if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    log_error "Invalid PR_NUMBER: must be numeric"
    exit 1
fi

if ! num_commits=$(gh pr view "$PR_NUMBER" --json commits | jq '.commits | length'); then
    log_error "Failed to get PR commits"
    exit 1
fi

log "Found $num_commits commits in PR #$PR_NUMBER"
echo "PR_COMMITS=$num_commits" >> "$GITHUB_ENV"

# Exit if no commits
if [[ "$num_commits" -eq 0 ]]; then
    log "No commits to process"
    exit 0
fi

process_single_commits() {
    log "Preparing individual commit submission"

    # Get commit SHAs
    if ! commit_shas=$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[] | .oid'); then
        log_error "Failed to get commit SHAs"
        exit 1
    fi

    # Create temporary branch
    git checkout -b tmp_branch "$GITHUB_EVENT_PULL_REQUEST_BASE_SHA"

    # Process each commit
    for csha in $commit_shas; do
        log_debug "Processing commit: $csha"

        git checkout tmp_branch
        if ! git cherry-pick "$csha"; then
            log_error "Failed to cherry-pick commit $csha"
            exit 1
        fi

        # Preserve original author
        author=$(git show -s --pretty=format:"%an <%ae>" "$csha")
        git commit -s -v --no-edit --author "$author" --amend

        # Extract Change-ID
        if change_id=$(git log --format="%(trailers:key=Change-Id,valueonly,separator=%x2C)" -n1); then
            if [[ -n "$change_id" ]]; then
                echo "$change_id" >> change-Id.txt
                log_debug "Captured Change-ID: $change_id"
            else
                log_error "Change-ID not created for commit $csha"
                exit 1
            fi
        fi

        git checkout "$GERRIT_BRANCH"
    done
}

process_squashed_commits() {
    log "Preparing squashed commit submission"

    # Show commit history for debugging
    git --no-pager log --graph --decorate --pretty=oneline -n"$num_commits"

    # Squash all commits into a single commit
    git reset --soft "$GITHUB_SHA"

    # Extract commit information
    extract_commit_metadata

    # Build commit message
    build_commit_message

    # Create the squashed commit
    create_squashed_commit
}

extract_commit_metadata() {
    log "Extracting commit metadata"

    # Extract Change-IDs
    git log -v --format=%B --reverse "HEAD..HEAD@{1}" | grep -E "^(Change-Id)" > change-Id.txt || true

    # Extract Signed-off-by lines
    git log -v --format=%B --reverse "HEAD..HEAD@{1}" | grep -E "^(Signed-off-by)" > signed-off-by.txt || true

    # Extract commit messages (excluding trailers)
    git log -v --format=%B --reverse "HEAD..HEAD@{1}" | grep -Ev "^(Signed-off-by|Change-Id)" > commit-msg.txt

    # Capture author info
    git show -s --pretty=format:"%an <%ae>" "HEAD..HEAD@{1}" > author-info.txt
}

build_commit_message() {
    log "Building commit message"

    local commit_message_files=()

    if [[ -s commit-msg.txt ]]; then
        commit_message_files+=("commit-msg.txt")
    fi

    if [[ -s signed-off-by.txt ]]; then
        sort -u signed-off-by.txt -o signed-off-by-final.txt
        commit_message_files+=("signed-off-by-final.txt")
    fi

    # Handle Change-ID reuse for reopened/synchronized PRs
    handle_change_id_reuse

    if [[ -s change-Id.txt ]]; then
        commit_message_files+=("change-Id.txt")
    fi

    # Join all message files
    if [[ ${#commit_message_files[@]} -gt 0 ]]; then
        cat "${commit_message_files[@]}" > final-commit-msg.txt
    else
        log_error "No commit message content found"
        exit 1
    fi
}

handle_change_id_reuse() {
    # Check if this is a PR update and reuse existing Change-ID
    if [[ "${GITHUB_EVENT_ACTION:-}" == "reopened" || "${GITHUB_EVENT_ACTION:-}" == "synchronize" ]]; then
        if [[ -s "reuse-cids-$PR_NUMBER.txt" ]]; then
            if reuse_cid=$(tail -1 "reuse-cids-$PR_NUMBER.txt" | tr -d '\n'); then
                if [[ -n "$reuse_cid" ]]; then
                    echo "Change-Id: $reuse_cid" > change-Id.txt
                    log "Reusing Change-ID: $reuse_cid"
                fi
            fi
        fi
    fi
}

create_squashed_commit() {
    log "Creating squashed commit"

    # Get author info
    local author=""
    if [[ -s author-info.txt ]]; then
        author=$(cat author-info.txt)
    fi

    # Create commit with Issue-ID if enabled
    if [[ -n "${SET_ISSUE_ID:-}" && "${ISSUEID_ENABLED:-}" == "true" ]]; then
        # Remove YAML document separators
        sed -i -e 's#^[ ]*---##g' -e 's#^[ ]*\.\.\.##g' commit-msg.txt

        git commit -s -v --no-edit --author "$author" \
            -m "$(cat commit-msg.txt)" \
            -m "$SET_ISSUE_ID" \
            -m "$(cat signed-off-by-final.txt)"
    else
        git commit -s -v --no-edit --author "$author" -F final-commit-msg.txt
    fi

    log "Squashed commit created successfully"
    git log -n1 --oneline
}

log "Starting commit processing"

# Process commits based on submission mode
if [[ "${SUBMIT_SINGLE_COMMITS:-false}" == "true" ]]; then
    log "Processing commits individually"
    process_single_commits
else
    log "Processing commits as squashed"
    process_squashed_commits
fi
