#!/bin/bash

# --- Ensure script is run with Bash ---
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with Bash. Please use: bash $0" >&2
    exit 1
fi

# ============================================================================
# SSH Vault Manager v2.1.0 - Modular Version
# ============================================================================
#
# DESCRIPTION:
#   A secure command-line tool for managing SSH connection details across
#   multiple encrypted vaults. Provides secure storage, quick access, and
#   automated connection to remote servers with credentials stored in
#   encrypted vaults.
#
# SECURITY FEATURES:
#   - Secure memory handling (no core dumps, cleared command history)
#   - Strong encryption using OpenSSL (AES-256-CBC by default)
#   - Process isolation to prevent side-channel attacks
#   - Secure temporary files with automatic cleanup
#   - Master passphrase used for vault encryption
#   - No plaintext credentials stored on disk
#   - Restrictive file permissions (umask 077)
#   - Comprehensive security event logging
#
# DEPENDENCIES:
#   - bash:     Version 4.0 or higher
#   - openssl:  Version 1.1.0 or higher for encryption
#   - ssh:      For connection to remote servers
#   - scp:      For file transfers (optional)
#   - grep:     For searching capabilities
#   - sed:      For text processing
#
# CONFIGURATION:
#   Environment variables that can be used to customize behavior:
#   - SVM_LAUNCH_DIR:      Directory from which svm was launched
#   - SVM_CONFIG_DIR:      Override configuration directory
#   - SVM_DEFAULT_VAULT:   Set the default vault to use
#   - SVM_EDITOR:          Text editor for editing server details
#   - SVM_LOG_LEVEL:       Control verbosity of logging
#   - SVM_NO_COLOR:        Disable colored output
#
# MODULE SYSTEM:
#   The application uses a modular architecture with separate library files:
#   - config.sh:      Configuration handling and settings
#   - security.sh:    Security features and secure memory handling
#   - utils.sh:       Utility functions and helpers
#   - encryption.sh:  Encryption and decryption functions
#   - vault.sh:       Vault management system
#   - server.sh:      Server operations (add, edit, connect)
#   - menu.sh:        Interactive user interface
#
# USAGE EXAMPLES:
#   svm                         # Start interactive mode
#   svm servername              # Search and connect to a server
#   svm --vault prod servername # Search in a specific vault
#   svm -v staging servername   # Same as above, shorthand version
#
# AUTHOR:
#   SSH Vault Manager Team
#   License: MIT (see LICENSE file for details)
# ============================================================================

# ============================================================================
# SECURITY HARDENING
# ============================================================================

# Disable core dumps and command history for security
ulimit -c 0
set +o history
umask 077

# Enhanced security settings
set -eo pipefail   # Exit on error, pipe failures
IFS=$'\n\t'        # Internal field separator for better security

# ============================================================================
# MODULE LOADING
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source all modules
source "$LIB_DIR/config.sh"
# --- Ensure color variables are set ---
: "${RED:=}"
: "${GREEN:=}"
: "${YELLOW:=}"
: "${BLUE:=}"
: "${MAGENTA:=}"
: "${CYAN:=}"
: "${NC:=}"
source "$LIB_DIR/security.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/encryption.sh"
source "$LIB_DIR/vault.sh"
source "$LIB_DIR/server.sh"
source "$LIB_DIR/menu.sh"

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Initialize secure environment and process isolation
    setup_secure_environment
    setup_process_isolation

    # Prompt for master passphrase at startup
    verify_master_passphrase

    # Initialize variables
    server_name=""
    vault_search_mode=false
    vault_arg=""

    # Enhanced argument parsing for per-vault search
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault|-v)
                vault_search_mode=true
                if [[ -n "$2" && "$2" != -* ]]; then
                    vault_arg="$2"
                    shift 2
                else
                    shift 1
                fi
                ;;
            *)
                server_name="$1"
                shift
                break
                ;;
        esac
    done

    # Initialize vault management system
    init_vault_system

    # If no legacy vault specified, use vault management system
    if [[ -z "$vault" ]]; then
        # Try to load the last selected vault
        if ! load_current_vault; then
            # No vault selected, user will need to use vault management
            echo -e "${YELLOW}Welcome to SSH Vault Manager with Multi-Vault Support!${NC}"
            echo -e "${BLUE}Use 'V' for Vault Management to create or select a vault.${NC}"
        fi
    else
        # Legacy mode: initialize file paths
        init_file_paths
    fi

    # Load configuration if vault is set
    if [[ -n "$vault" ]]; then
        load_config
        save_default_config
    fi

    # Set trap for cleanup
    trap 'cleanup' INT TERM EXIT

    log_event "SESSION_START" "SVM session started with vault management" "PID:$$"
    log_security_event "SESSION_STARTED" "SVM session started" "INFO"

    # Per-vault search mode
    if [[ "$vault_search_mode" == true && -n "$server_name" ]]; then
        # If a vault name was provided, switch to it
        if [[ -n "$vault_arg" ]]; then
            vault_path="$vaults_dir/$vault_arg"
            if [[ -d "$vault_path" ]]; then
                vault="$vault_path"
                current_vault_name="$vault_arg"
                init_file_paths
                load_config
            else
                echo -e "${RED}Vault '$vault_arg' not found.${NC}"
                exit 1
            fi
        fi
        
        # Decrypt vault to temporary file for search
        if [[ -f "$servers_file" ]]; then
            # Set passphrase for decryption (same as global search)
            passphrase="$master_passphrase"
            if ! decrypt_vault "$servers_file" "$tmp_servers_file" 2>/dev/null; then
                echo -e "${YELLOW}No servers found in vault '$current_vault_name'.${NC}"
                echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
                exit 0
            fi
        else
            echo -e "${YELLOW}Vault '$current_vault_name' is empty.${NC}"
            echo -e "${YELLOW}Use 'Add Server' to add your first server.${NC}"
            exit 0
        fi
        
        # Call search_servers with the search term (non-interactive)
        export SEARCH_TERM_CLI="$server_name"
        search_servers --no-prompt
        cleanup
    elif [[ -n "$server_name" ]]; then
        echo -e "${GREEN}Global search mode: searching all vaults for '$server_name'${NC}"
        search_all_vaults "$server_name"
        cleanup
    else
        clear
        banner
        show_menu
    fi
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    : "${SVM_LAUNCH_DIR:=$PWD}"
    export SVM_LAUNCH_DIR
    main "$@"
fi 