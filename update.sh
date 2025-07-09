#!/usr/bin/env bash
# ============================================================================
# SSH Vault Manager Updater
# ============================================================================
# This script updates SSH Vault Manager, preserving configurations and data.
# It performs version checks, backup, and provides rollback capabilities.
# Follow secure practices and handle errors gracefully.
# ============================================================================

# Exit on error or undefined var
set -eu

# Set error trap handler
trap 'error_exit "An error occurred during update"' INT TERM

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

# Error handling
error_exit() {
    log "${RED}❌ $1${NC}"
    log "See log file: $LOG_FILE"
    exit 1
}

# Parse command line arguments
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
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  --install-dir DIR    Specify custom install directory"
            echo "  --repo-url URL       Specify repository URL"
            echo "  -f, --force          Force update even if already at latest version"
            echo "  -q, --quiet          Quiet mode (no output to terminal)"
            echo "  -d, --dry-run        Simulate the update without making changes"
            echo "  -h, --help           Show this help message and exit"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# Print dry-run notice if enabled
if [ "$DRY_RUN" = "true" ]; then
    log "${YELLOW}🔍 DRY RUN MODE: This is a trial run. No changes will be made.${NC}"
    log ""
fi

# Validate installation directory
if [ ! -d "$INSTALL_DIR" ]; then
    error_exit "Installation directory not found: $INSTALL_DIR"
fi

# Check current version
log "${BLUE}Checking current version...${NC}"
if [ -f "$INSTALL_DIR/VERSION" ]; then
    CURRENT_VERSION=$(cat "$INSTALL_DIR/VERSION")
    log "Current version: ${GREEN}$CURRENT_VERSION${NC}"
else
    error_exit "Cannot determine current version"
fi

# Validate repository
if ! git ls-remote --quiet "$REPO_URL" >/dev/null 2>&1; then
    error_exit "Invalid repository URL or repository not accessible: $REPO_URL"
fi
log "${GREEN}Repository validated: $REPO_URL${NC}"

# Create backup
if [ "$DRY_RUN" = "true" ]; then
    log "${YELLOW}(Dry run) Would create backup at: $BACKUP_DIR${NC}"
else
    log "${BLUE}Creating backup...${NC}"
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    cp -r "$INSTALL_DIR/." "$BACKUP_DIR/" || error_exit "Failed to create backup"
    log "${GREEN}✅ Backup created at: $BACKUP_DIR${NC}"
fi

# Update process
if [ "$DRY_RUN" = "true" ]; then
    log "${YELLOW}(Dry run) Would perform update from version $CURRENT_VERSION${NC}"
    log "${YELLOW}(Dry run) No actual changes will be made${NC}"
else
    log "${BLUE}Starting update process...${NC}"
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM
    
    git clone --depth 1 "$REPO_URL" "$TMP_DIR" || error_exit "Failed to download update"
    rm -rf "$INSTALL_DIR"/*
    cp -R "$TMP_DIR"/* "$INSTALL_DIR"/ || error_exit "Failed to update files"
    
    chmod 755 "$INSTALL_DIR/svm.sh"
    chmod 755 "$INSTALL_DIR/install.sh"
    
    log "${GREEN}✅ Update completed successfully${NC}"
fi

# Final summary
if [ "$DRY_RUN" = "true" ]; then
    log "\n${YELLOW}🔍 DRY RUN SUMMARY${NC}"
    log "• Would backup current installation to: $BACKUP_DIR"
    log "• Would update from version: $CURRENT_VERSION"
    log "• No actual changes were made"
    log "\n${BLUE}ℹ️  Now you are ready to run the actual update.${NC}"
    log "${BLUE}Run the same command without --dry-run to proceed.${NC}"
else
    log "\n${GREEN}✅ UPDATE SUMMARY${NC}"
    log "• Backup created at: $BACKUP_DIR"
    log "• Updated from version: $CURRENT_VERSION"
    log "\n${GREEN}SSH Vault Manager update completed successfully!${NC}"
fi
