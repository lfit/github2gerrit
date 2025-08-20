#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Submit changes to Gerrit and handle post-submission tasks
set -euo pipefail

# Function to log messages
log() {
    echo "::notice::$1"
}

log_error() {
    echo "::error::$1"
}

# Check required environment variables
required_vars=("PR_NUMBER" "PROJECT_REPO_GITHUB" "GERRIT_SSH_USER_G2G" "GERRIT_SERVER" "PROJECT_REPO_GERRIT")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit 1
    fi
done

submit_to_gerrit() {
    log "Submitting changes to Gerrit"

    # Switch to correct branch if using single commits
    if [[ "${SUBMIT_SINGLE_COMMITS:-false}" == "true" ]]; then
        git checkout tmp_branch
    fi

    # Determine reviewers
    local reviewers="${REVIEWERS_EMAIL:-$GERRIT_SSH_USER_G2G_EMAIL}"
    local topic="GH-$PROJECT_REPO_GITHUB-$PR_NUMBER"

    log "Submitting with topic: $topic, reviewers: $reviewers"

    # Submit to Gerrit
    if git review --yes -t "$topic" --reviewers "$reviewers"; then
        log "Successfully submitted to Gerrit"
    else
        log_error "Failed to submit to Gerrit"
        exit 1
    fi
}

validate_and_extract_change_info() {
    log "Validating and extracting change information"

    # Extract Change-ID from commit if not already available
    if [[ ! -s change-Id.txt ]]; then
        if gerrit_change_id=$(git show HEAD --format=%B -s | grep "Change-Id:" | cut -d " " -f2); then
            if [[ -n "$gerrit_change_id" ]]; then
                echo "$gerrit_change_id" >> change-Id.txt
                log "Extracted Change-ID: $gerrit_change_id"
            else
                log_error "Could not extract Change-ID from commit"
                exit 1
            fi
        else
            log_error "No Change-ID found in commit"
            exit 1
        fi
    fi

    # Set Change-IDs in environment
    if [[ -s change-Id.txt ]]; then
        {
            echo 'GERRIT_CHANGE_ID<<EOF'
            cat change-Id.txt
            echo EOF
        } >> "$GITHUB_ENV"
    fi

    # Query Gerrit for change information
    query_gerrit_changes
}

query_gerrit_changes() {
    log "Querying Gerrit for change information"

    # Initialize output files
    : > change-url.txt
    : > commit-sha.txt
    : > change-request-number.txt
    : > cid-url.txt

    # Query each Change-ID
    while IFS= read -r cid; do
        [[ -n "$cid" ]] || continue

        log "Querying Change-ID: $cid"

        # Query Gerrit via SSH (safely quote variables to prevent command injection)
        safe_project_repo_gerrit=$(printf "%q" "$PROJECT_REPO_GERRIT")
        safe_cid=$(printf "%q" "${cid##* }")
        if ssh -v -n -p "${GERRIT_SERVER_PORT:-29418}" "$GERRIT_SSH_USER_G2G@$GERRIT_SERVER" \
            "gerrit query limit:1 owner:self is:open project:$safe_project_repo_gerrit --current-patch-set --format=JSON $safe_cid" \
            > query_result.txt; then

            # Extract information from query result
            extract_gerrit_query_results "$cid"
        else
            log_error "Failed to query Gerrit for Change-ID: $cid"
            exit 1
        fi
    done < change-Id.txt

    # Set environment variables from results
    set_gerrit_environment_variables
}

extract_gerrit_query_results() {
    local cid="$1"

    # Extract URL
    if url=$(jq -r '.url | select( . != null )' query_result.txt); then
        [[ -n "$url" && "$url" != "null" ]] && echo "$url" >> change-url.txt
    fi

    # Extract change number
    if number=$(jq -r '.number | select( . != null )' query_result.txt); then
        [[ -n "$number" && "$number" != "null" ]] && echo "$number" >> change-request-number.txt
    fi

    # Extract commit SHA
    if sha=$(jq -r '.currentPatchSet.revision | select( . != null )' query_result.txt); then
        [[ -n "$sha" && "$sha" != "null" ]] && echo "$sha" >> commit-sha.txt
    fi

    # Create markdown link
    if [[ -n "$url" && "$url" != "null" ]]; then
        echo "[$cid]($url)" >> cid-url.txt
    fi
}

set_gerrit_environment_variables() {
    # Set Gerrit URLs
    if [[ -s change-url.txt ]]; then
        {
            echo 'GERRIT_CHANGE_REQUEST_URL<<EOF'
            cat change-url.txt
            echo EOF
        } >> "$GITHUB_ENV"
    fi

    # Set commit SHAs
    if [[ -s commit-sha.txt ]]; then
        {
            echo 'GERRIT_COMMIT_SHA<<EOF'
            cat commit-sha.txt
            echo EOF
        } >> "$GITHUB_ENV"
    fi

    # Set change numbers
    if [[ -s change-request-number.txt ]]; then
        {
            echo 'GERRIT_CHANGE_REQUEST_NUM<<EOF'
            cat change-request-number.txt
            echo EOF
        } >> "$GITHUB_ENV"
    fi

    # Set markdown formatted URLs
    if [[ -s cid-url.txt ]]; then
        {
            echo 'GERRIT_CR_URL_CID<<EOF'
            cat cid-url.txt
            echo EOF
        } >> "$GITHUB_ENV"
    fi
}

add_gerrit_comments() {
    log "Adding GitHub PR reference to Gerrit changes"

    if [[ ! -s commit-sha.txt ]]; then
        log "No commit SHAs available, skipping Gerrit comments"
        return
    fi

    # Create reference message
    local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    local pr_path="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/pull/$PR_NUMBER"
    local message
    message=$(printf 'GHPR: %s\nAction-Run: %s\n' "$pr_path" "$run_url")

    # Add comment to each commit
    while IFS= read -r csha; do
        [[ -n "$csha" ]] || continue

        log "Adding comment to commit: ${csha:0:8}"

        # Properly escape all variables for the remote shell
        esc_message=$(printf '%q' "$message")
        esc_branch=$(printf '%q' "$GERRIT_BRANCH")
        esc_project=$(printf '%q' "$PROJECT_REPO_GERRIT")
        esc_csha=$(printf '%q' "$csha")

        if ssh -v -n -p "${GERRIT_SERVER_PORT:-29418}" "$GERRIT_SSH_USER_G2G@$GERRIT_SERVER" \
            "gerrit review -m $esc_message --branch $esc_branch --project $esc_project $esc_csha"; then
            log "Comment added successfully"
        else
            log_error "Failed to add comment to commit: $csha"
        fi
    done < commit-sha.txt
}

# Main execution
log "Starting Gerrit submission process"

submit_to_gerrit
validate_and_extract_change_info
add_gerrit_comments

log "Gerrit submission completed successfully"
