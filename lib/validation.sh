#!/usr/bin/env bash

# ============================================================================
# Input Validation Module
# ============================================================================
# This module provides functions for robust input validation and sanitization
# to ensure all inputs conform to expected formats and are securely handled.
#
# AUTHOR:
#   SSH Vault Manager Team
# ============================================================================

# Check if a string is non-empty
validate_non_empty() {
    local input="$1"
    if [ -z "$input" ]; then
        echo "Error: Input should not be empty." >&2
        return 1
    fi
}

# Check if a file path exists and is accessible
validate_file_path() {
    local file_path="$1"
    if [ ! -e "$file_path" ]; then
        echo "Error: File path '$file_path' does not exist." >&2
        return 1
    fi
    if [ ! -r "$file_path" ]; then
        echo "Error: No read permission for file path '$file_path'." >&2
        return 1
    fi
}

# Validate if the input is a valid hostname or IP address
validate_hostname_or_ip() {
    local input="$1"
    if ! [[ "$input" =~ ^[a-zA-Z0-9._-]+$ ]] && ! [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid hostname or IP address '$input'." >&2
        return 1
    fi
}

# Validate if the port number is within the valid range
validate_port_number() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Error: Invalid port number '$port'. Must be between 1 and 65535." >&2
        return 1
    fi
}

# Validate SSH connection string
validate_ssh_conn() {
    local ssh_conn="$1"
    if ! [[ "$ssh_conn" =~ ^[a-zA-Z0-9._%-]+@[a-zA-Z0-9._%-]+(:[0-9]+)?$ ]]; then
        echo "Error: Invalid SSH connection string '$ssh_conn'. Must be in the format user@host[:port]." >&2
        return 1
    fi
}

# Sanitize input by stripping potentially dangerous characters
sanitize_input() {
    local input="$1"
    sanitized_output=$(echo "$input" | sed 's/[^a-zA-Z0-9._-]//g')
    echo "$sanitized_output"
}

