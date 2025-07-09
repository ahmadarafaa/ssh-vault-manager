#!/bin/bash

# ============================================================================
# CONFIGURATION MODULE
# ============================================================================

# Get version from VERSION file
read_version_file() {
    local version_file="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/VERSION"
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        echo "2.0.0"  # Default fallback version
    fi
}

# Set SVM version from the central VERSION file
SVM_VERSION=$(read_version_file)

# Default configuration
declare -A CONFIG=(
    [PBKDF2_ITERATIONS]=600000
    [CIPHER]="aes-256-cbc"
    [DIGEST]="sha512"
    [VAULT_VERSION]="${SVM_VERSION%.*}"  # Use major.minor from SVM_VERSION
    [PASSPHRASE_TIMEOUT]=300
    [MAX_LOGIN_ATTEMPTS]=3
    [CONNECTION_TIMEOUT]=30
    [VAULT_NAME]=".vault.enc"
    [CONFIG_NAME]=".svm.conf"
    [LOG_NAME]=".connection.log"
    [BACKUP_PREFIX]="vault_backup"
    [CACHE_ENABLED]=true
    [LOG_MAX_LINES]=1000
    [SEARCH_CACHE_SIZE]=100
    [SHRED_PASSES]=3
    [VERIFY_INTEGRITY]=true
    [AUTO_BACKUP]=true
    [BACKUP_RETENTION]=5
)

# Vault management variables
base_vault_dir="$HOME/.svm"
vaults_dir="$base_vault_dir/vaults"
current_vault_name=""
vault=""
servers_file=""
config_file=""
log_file=""
tmp_servers_file=""
passphrase=""
session_active=false

# Session management
declare -g SESSION_START=$(date +%s)
declare -g PASSPHRASE_TIMESTAMP=0
declare -A VAULT_CACHE=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Statistics
declare -A STATS=(
    [connections_attempted]=0
    [connections_successful]=0
    [connections_failed]=0
    [vault_operations]=0
)

# Master passphrase management
master_hash_file="$base_vault_dir/.master_hash"
master_passphrase=""

# Enhanced temp directory management
SVM_TEMP_DIR="/tmp/.svm-temp"
SVM_TEMP_PREFIX="svm-$(whoami)-"
SVM_TEMP_RETENTION_DAYS=30

# Rate limiting variables
declare -A RATE_LIMITS=(
    [login_attempts]=0
    [last_attempt]=0
    [max_attempts]=5
    [lockout_duration]=300  # 5 minutes
    [search_attempts]=0
    [search_last_attempt]=0
    [max_search_attempts]=10
    [search_lockout_duration]=60  # 1 minute
)

# Performance monitoring
declare -A PERFORMANCE_STATS=(
    [start_time]=$(date +%s)
    [operations]=0
    [cache_hits]=0
    [cache_misses]=0
)

# Command caching for frequently used commands
declare -A COMMAND_CACHE=()
declare -A COMMAND_CACHE_TIMESTAMP=()
CACHE_TIMEOUT=300  # 5 minutes

# Cleanup flag
CLEANED_UP=false 