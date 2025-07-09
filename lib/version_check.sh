#!/usr/bin/env bash

# ============================================================================
# Version Checking Module
# ============================================================================
# This module provides functions to verify the version of critical dependencies
# like bash and openssl and ensure they're up to date with the minimum required
# versions for this script to run smoothly and securely.
#
# AUTHOR:
#   SSH Vault Manager Team
# ============================================================================

# Minimum version constants
MIN_BASH_VERSION="4.0"
MIN_OPENSSL_VERSION="1.1.0"

# Compare two version strings (e.g., 1.1.0 and 1.2.0)
version_ge() {
    # returns 0 if version >= required_version
    local version=$1 required_version=$2
    [ "$(printf '%s\n' "$required_version" "$version" | sort -V | head -n1)" = "$required_version" ]
}

# Check the Bash version
check_bash_version() {
    if ! version_ge "$BASH_VERSION" "$MIN_BASH_VERSION"; then
        echo "Error: Bash version $MIN_BASH_VERSION or higher is required. You have $BASH_VERSION." >&2
        return 1
    fi
}

# Check the OpenSSL version
check_openssl_version() {
    local current_version
    current_version=$(openssl version | awk '{print $2}')
    if ! version_ge "$current_version" "$MIN_OPENSSL_VERSION"; then
        echo "Error: OpenSSL version $MIN_OPENSSL_VERSION or higher is required. You have $current_version." >&2
        return 1
    fi
}

# Main version checking function
verify_versions() {
    check_bash_version || exit 1
    check_openssl_version || exit 1
}

# Execute version checks when this file is sourced
verify_versions

