#!/usr/bin/env sh
# ============================================================================
# SSH Vault Manager Updater
# ============================================================================
# This script updates SSH Vault Manager, preserving configurations and data.
# It performs version checks, backup, and provides rollback capabilities.
# Follow secure practices and handle errors gracefully.
# ============================================================================

# Exit on error or undefined var
set -eu

# Default XDG locations
: "${XDG_DATA_HOME:=${HOME}/.local/share}"
: "${XDG_BIN_HOME:=${HOME}/.local/bin}"

INSTALL_DIR="${INSTALL_DIR:-$XDG_DATA_HOME/opt/ssh-vault-manager}"
WRAPPER_LINK="${WRAPPER_LINK:-$XDG_BIN_HOME/svm}"
BACKUP_DIR="$HOME/svm-backup-before-update-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$HOME/svm-update-log-$(date +%Y%m%d-%H%M%S).log"
REPO_URL="https://github.com/ahmadarafaa/ssh-vault-manager.git"

# Mode flags
FORCE_UPDATE=false
QUIET_MODE=false
DRY_RUN=false
UPDATE_SUMMARY=""

# Initialize variables
CURRENT_VERSION=""
LATEST_VERSION=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Log function
log() {
    if [ "$QUIET_MODE" != "true" ]; then
        echo -e "$1" | tee -a "$LOG_FILE"
    else
        echo -e "$1" >> "$LOG_FILE"
    fi
}

# Debug logging
debug_log() {
    if [ "$QUIET_MODE" != "true" ]; then
        echo -e "${CYAN}DEBUG: $1${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "DEBUG: $1" >> "$LOG_FILE"
    fi
}

# Error handling
error_exit() {
    log "${RED}❌ $1${NC}"
    log "See log file: $LOG_FILE"
    exit 1
}

# Add to update summary
add_to_summary() {
    UPDATE_SUMMARY="$UPDATE_SUMMARY\n$1"
}

# Show progress
show_progress() {
    local message="$1"
    printf "${CYAN}⏳ %s...${NC}" "$message"
}

# Clear progress
clear_progress() {
    printf "\r\033[K"  # Clear the line
}

# Compare versions (semantic versioning)
version_gt() {
    # Returns true if version1 > version2
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" != "$1"
}

# Check installation directory
check_installation() {
    if [ ! -d "$INSTALL_DIR" ]; then
        error_exit "Installation directory not found: $INSTALL_DIR"
    fi
    
    if [ ! -f "$INSTALL_DIR/svm.sh" ]; then
        error_exit "Invalid installation: svm.sh not found in $INSTALL_DIR"
    fi
}

# Validate repository URL
validate_repo() {
    show_progress "Validating repository"
    if ! git ls-remote --quiet "$REPO_URL" >/dev/null 2>&1; then
        clear_progress
        error_exit "Invalid repository URL or repository not accessible: $REPO_URL"
    fi
    clear_progress
    log "${GREEN}Repository validated: $REPO_URL${NC}"
}

# Check if update is available
update_available() {
    check_installation
    
    if [ -f "$INSTALL_DIR/version.txt" ]; then
        CURRENT_VERSION=$(cat "$INSTALL_DIR/version.txt")
    else
        error_exit "Cannot determine current version"
    fi

    show_progress "Fetching latest version"
    # Try to get version from tags first
    LATEST_VERSION=$(git ls-remote --tags "$REPO_URL" | grep -v '{}' | awk -F'/' '{print $3}' | sort -V | tail -n1)
    
    # If no tags found, try to get from branches
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(git ls-remote --heads "$REPO_URL" | grep "main\|master" | awk '{print $1}' | head -n1)
        # Use short commit hash if using branch
        if [ -n "$LATEST_VERSION" ]; then
            LATEST_VERSION="${LATEST_VERSION:0:8}"
        fi
    fi
    clear_progress

    if [ -z "$LATEST_VERSION" ]; then
        error_exit "Failed to fetch latest version information"
    fi

    # Clean version strings (remove 'v' prefix if present)
    CURRENT_CLEAN=$(echo "$CURRENT_VERSION" | sed 's/^v//')
    LATEST_CLEAN=$(echo "$LATEST_VERSION" | sed 's/^v//')

    debug_log "Current version (clean): $CURRENT_CLEAN"
    debug_log "Latest version (clean): $LATEST_CLEAN"

    if version_gt "$LATEST_CLEAN" "$CURRENT_CLEAN"; then
        return 0  # Update is available
    else
        return 1  # No update available
    fi
}

# Check current and latest version
check_version() {
    log "${BLUE}Checking current version...${NC}"
    
    if update_available; then
        log "Current version: ${YELLOW}$CURRENT_VERSION${NC}"
        log "Latest version: ${GREEN}$LATEST_VERSION${NC}"
        log "${GREEN}Update available!${NC}"
        add_to_summary "Update from $CURRENT_VERSION to $LATEST_VERSION"
    else
        log "Current version: ${GREEN}$CURRENT_VERSION${NC}"
        log "Latest version: ${GREEN}$LATEST_VERSION${NC}"
        
        if [ "$FORCE_UPDATE" = "true" ]; then
            log "${YELLOW}Force update requested. Continuing despite being at latest version.${NC}"
            add_to_summary "Force update from $CURRENT_VERSION (already latest)"
        else
            log "${GREEN}Already at latest version ($CURRENT_VERSION)${NC}"
            exit 0
        fi
    fi
}

# Backup current installation
backup() {
    log "${BLUE}Creating backup at $BACKUP_DIR...${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}(Dry run) Would create backup at: $BACKUP_DIR${NC}"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    
    # Backup installation
    if [ -d "$INSTALL_DIR" ]; then
        cp -a "$INSTALL_DIR/." "$BACKUP_DIR/install/" || error_exit "Failed to backup installation"
    fi
    
    # Backup configuration and data
    if [ -d "$HOME/.svm" ]; then
        cp -a "$HOME/.svm/." "$BACKUP_DIR/data/" || error_exit "Failed to backup data"
    fi
    
    # Save version information
    echo "$CURRENT_VERSION" > "$BACKUP_DIR/version.txt"
    
    chmod -R 700 "$BACKUP_DIR"
    log "${GREEN}✅ Backup created successfully${NC}"
    add_to_summary "Backup created at: $BACKUP_DIR"
}

# Basic update process
perform_update() {
    log "${BLUE}Starting update process...${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}(Dry run) Would update from version $CURRENT_VERSION to $LATEST_VERSION${NC}"
        return 0
    fi
    
    # Create temporary directory
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
    
    show_progress "Downloading new version"
    git clone --depth 1 --branch "$LATEST_VERSION" "$REPO_URL" "$TMP_DIR" || \
        error_exit "Failed to download update"
    clear_progress
    
    # Verify integrity
    log "${BLUE}Validating update package...${NC}"
    if [ ! -f "$TMP_DIR/svm.sh" ]; then
        error_exit "Invalid update package"
    fi
    
    # Stop running processes
    show_progress "Stopping running processes"
    pkill -f svm.sh 2>/dev/null || true
    clear_progress
    
    # Update files
    show_progress "Updating files"
    rm -rf "$INSTALL_DIR"/*
    cp -R "$TMP_DIR"/* "$INSTALL_DIR"/ || error_exit "Failed to update files"
    clear_progress
    
    # Update permissions
    show_progress "Setting permissions"
    chmod 755 "$INSTALL_DIR/svm.sh"
    chmod 755 "$INSTALL_DIR/install.sh"
    chmod 755 "$INSTALL_DIR/uninstall.sh"
    chmod 755 "$INSTALL_DIR/update.sh"
    clear_progress
    
    echo "$LATEST_VERSION" > "$INSTALL_DIR/version.txt"
    log "${GREEN}✅ Update completed successfully${NC}"
    add_to_summary "Updated to version: $LATEST_VERSION"
}

# Rollback in case of failure
rollback() {
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}(Dry run) No rollback needed as no changes were made${NC}"
        return 0
    fi
    
    log "${YELLOW}⚠️ Error detected! Rolling back to previous version...${NC}"
    if [ ! -d "$BACKUP_DIR" ]; then
        error_exit "Backup directory not found, cannot rollback"
    fi
    
    # Restore installation
    if [ -d "$BACKUP_DIR/install" ]; then
        rm -rf "$INSTALL_DIR"/*
        cp -a "$BACKUP_DIR/install/." "$INSTALL_DIR/" || \
            error_exit "Failed to restore installation"
    fi
    
    # Restore data if needed
    if [ -d "$BACKUP_DIR/data" ] && [ ! -d "$HOME/.svm" ]; then
        cp -a "$BACKUP_DIR/data/." "$HOME/.svm/" || \
            error_exit "Failed to restore data"
    fi
    
    # Restore version
    if [ -f "$BACKUP_DIR/version.txt" ]; then
        cp "$BACKUP_DIR/version.txt" "$INSTALL_DIR/" || \
            error_exit "Failed to restore version information"
    fi
    
    log "${GREEN}✅ Rollback completed successfully${NC}"
    add_to_summary "❌ Update failed - rolled back to version: $CURRENT_VERSION"
}

validate_update() {
    log "${BLUE}Validating update...${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        log "${YELLOW}(Dry run) Would validate update${NC}"
        return 0
    fi
    
    for file in svm.sh install.sh uninstall.sh update.sh; do
        show_progress "Checking $file"
        if [ ! -f "$INSTALL_DIR/$file" ]; then
            clear_progress
            error_exit "Missing required file: $file"
        fi
        clear_progress
    done
    
    show_progress "Checking permissions"
    if [ ! -x "$INSTALL_DIR/svm.sh" ]; then
        clear_progress
        error_exit "Invalid permissions on svm.sh"
    fi
    clear_progress

    show_progress "Checking version information"
    if [ ! -f "$INSTALL_DIR/version.txt" ]; then
        clear_progress
        error_exit "Version information missing"
    fi
    
    NEW_VERSION=$(cat "$INSTALL_DIR/version.txt")
    if [ "$NEW_VERSION" != "$LATEST_VERSION" ]; then
        log "${YELLOW}⚠️ Warning: Version mismatch after update${NC}"
        log "Expected: $LATEST_VERSION, Found: $NEW_VERSION"
    fi
    clear_progress

    log "${GREEN}✅ Update validation successful${NC}"
    add_to_summary "Validation completed successfully"
}

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --install-dir DIR    Specify custom install directory"
    echo "  --repo-url URL       Specify repository URL"
    echo "  -f, --force          Force update even if already at latest version"
    echo "  -q, --quiet          Quiet mode (no output to terminal)"
    echo "  -d, --dry-run        Simulate the update without making changes"
    echo "  -h, --help           Show this help message and exit"
    exit 0
}

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        --install-dir)
            INSTALL_DIR="$2"; shift 2 ;;
        --repo-url)
            REPO_URL="$2"; shift 2 ;;
        -f|--force)
            FORCE_UPDATE=true; shift ;;
        -q|--quiet)
            QUIET_MODE=true; shift ;;
        -d|--dry-run)
            DRY_RUN=true; shift ;;
        -h|--help)
            usage ;;
        *)
            echo "Unknown option: $1" >&2
            usage ;;
    esac
done

# Detect repository URL from git
detect_repo_url() {
    if command -v git >/dev/null 2>&1; then
        REPO_URL=$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || echo "$REPO_URL")
    else
        error_exit "Git is not installed. Cannot proceed with update."
    fi
}

# Check for internet connectivity
check_internet() {
    curl -sSf http://www.google.com >/dev/null 2>&1 || error_exit "No internet connectivity detected. Please check your connection."
}

# Load configurations
load_config() {
    if [ -f "$HOME/.svmconfig" ]; then
        # shellcheck disable=SC1090
        . "$HOME/.svmconfig" || error_exit "Failed to load configuration file"
        log "Using repository URL from configuration"
    fi
}

# Main update logic with error trapping
trap 'rollback' ERR

# Initial checks and configuration
load_config
detect_repo_url
validate_repo
check_internet
check_version
backup
perform_update
validate_update

# Display update summary
if [ -n "$UPDATE_SUMMARY" ]; then
    log "\n${BOLD}${BLUE}=== Update Summary ===${NC}"
    printf "%b\n" "$UPDATE_SUMMARY" | while IFS= read -r line; do
        log "  • $line"
    done
fi

if [ "$DRY_RUN" = "true" ]; then
    log "\n${YELLOW}This was a dry run. No changes were made.${NC}"
fi

log "\n${GREEN}SSH Vault Manager update completed successfully!${NC}"

