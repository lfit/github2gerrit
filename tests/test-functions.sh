#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 The Linux Foundation

# Test helper functions for github2gerrit

# Extract functions from main script without executing it
# SCRIPT_DIR="$(dirname "$0")/.." # Unused but kept for future use

# Define the functions locally to avoid sourcing the main script
extract_project() {
    local url="$1"
    local project
    project=$(echo "$url" | sed -E 's#.*/c/([^/]+/[^/]+)/\+.*#\1#')
    echo "$project"
}

extract_change_number() {
    local url="$1"
    local change_number
    change_number=$(echo "$url" | sed -E 's#.*/\+/([0-9]+).*#\1#')
    echo "$change_number"
}

extract_hostname() {
    local url="$1"
    local hostname
    if [[ -z "$url" || ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    hostname=$(echo "$url" | sed -E 's#https?://([^/]+)/.*#\1#')
    echo "$hostname"
}

# Test function: URL parsing
test_url_parsing() {
    local test_urls=(
        "https://git.opendaylight.org/gerrit/c/releng/builder/+/111445,git.opendaylight.org,111445,releng/builder"
        "https://review.opendev.org/c/openstack/nova/+/123456,review.opendev.org,123456,openstack/nova"
        "http://gerrit.example.com/c/project/name/+/999,gerrit.example.com,999,project/name"
    )

    for test_case in "${test_urls[@]}"; do
        IFS=',' read -r url expected_host expected_change expected_project <<< "$test_case"

        echo "Testing URL: $url"

        hostname=$(extract_hostname "$url")
        change_num=$(extract_change_number "$url")
        project=$(extract_project "$url")

        # Validate results
        if [[ "$hostname" != "$expected_host" ]]; then
            echo "FAIL: Hostname mismatch. Expected: $expected_host, Got: $hostname"
            return 1
        fi

        if [[ "$change_num" != "$expected_change" ]]; then
            echo "FAIL: Change number mismatch. Expected: $expected_change, Got: $change_num"
            return 1
        fi

        if [[ "$project" != "$expected_project" ]]; then
            echo "FAIL: Project mismatch. Expected: $expected_project, Got: $project"
            return 1
        fi

        echo "PASS: $url"
    done

    echo "All URL parsing tests passed!"
    return 0
}

# Test function: Edge cases
test_edge_cases() {
    echo "Testing edge cases..."

    # Test empty URL
    local empty_result
    empty_result=$(extract_hostname "" 2>/dev/null || echo "empty")
    if [[ "$empty_result" != "empty" ]]; then
        echo "FAIL: Empty URL should be handled gracefully"
        return 1
    fi

    # Test malformed URL
    local malformed_result
    malformed_result=$(extract_hostname "not-a-url" 2>/dev/null || echo "malformed")
    if [[ "$malformed_result" != "malformed" ]]; then
        echo "FAIL: Malformed URL should be handled gracefully"
        return 1
    fi

    echo "Edge case tests passed!"
    return 0
}

# Test function: JSON parsing
test_json_parsing() {
    echo "Testing JSON parsing..."

    local test_json='{"branch":"main","id":"I1234567890abcdef","url":"https://gerrit.com/123","number":"123"}'

    # Test each field extraction
    local branch
    local id
    local url
    local number

    # Assign variables separately to avoid masking return values
    branch=$(echo "$test_json" | jq -r '.branch | select( . != null )') || return 1
    id=$(echo "$test_json" | jq -r '.id | select( . != null )') || return 1
    url=$(echo "$test_json" | jq -r '.url | select( . != null )') || return 1
    number=$(echo "$test_json" | jq -r '.number | select( . != null )') || return 1

    if [[ "$branch" != "main" ]] || [[ "$id" != "I1234567890abcdef" ]] || [[ "$url" != "https://gerrit.com/123" ]] || [[ "$number" != "123" ]]; then
        echo "FAIL: JSON parsing failed"
        return 1
    fi

    echo "JSON parsing tests passed!"
    return 0
}

# Main test runner
run_all_tests() {
    echo "Running all tests..."

    test_url_parsing || exit 1
    test_edge_cases || exit 1
    test_json_parsing || exit 1

    echo "All tests passed successfully!"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi
