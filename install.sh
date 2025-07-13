#!/usr/bin/env sh
# Get script directory and read version
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SVM_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '\n' || echo "unknown")

# ============================================================================
# SSH Vault Manager Installer ${SVM_VERSION}
# ============================================================================
#
# DESCRIPTION:
#   POSIX-compliant installer script for SSH Vault Manager that follows XDG
#   Base Directory Specification. Installs the application files to a user's
#   local directory and creates a convenient wrapper script.
#
# DEPENDENCIES:
#   - sh:     POSIX-compliant shell
#   - mkdir:  Create directories
#   - rm:     Remove files and directories
#   - cp:     Copy files and directories
#   - chmod:  Change file permissions
#   - cat:    Concatenate and print files
#
# USAGE:
#   ./install.sh                        # Default installation
#   ./install.sh --help                 # Show help
#   ./install.sh --install-dir /path    # Custom installation directory
#   ./install.sh --wrapper /path/cmd    # Custom wrapper location
#
# EXAMPLES:
#   ./install.sh
#   ./install.sh --install-dir ~/.apps/svm --wrapper ~/bin/sshvault
#
# ENVIRONMENT VARIABLES:
#   INSTALL_DIR:    Override installation directory
#   WRAPPER_LINK:   Override wrapper script location
#   XDG_DATA_HOME:  User data directory (default: ~/.local/share)
#   XDG_BIN_HOME:   User binary directory (default: ~/.local/bin)
#   HOME:           User home directory
#
# SECURITY CONSIDERATIONS:
#   - Files are installed with current user permissions
#   - Wrapper executable has its execute bit set (chmod +x)
#   - No system-wide changes are made; all changes are user-local
#
# AUTHOR:
#   SSH Vault Manager Team
#   License: MIT (see LICENSE file for details)
#
# ============================================================================

# Exit on error or undefined var
set -eu

# Default XDG locations
: "${XDG_DATA_HOME:=${HOME}/.local/share}"
: "${XDG_BIN_HOME:=${HOME}/.local/bin}"

INSTALL_DIR="${INSTALL_DIR:-$XDG_DATA_HOME/opt/ssh-vault-manager}"
WRAPPER_LINK="${WRAPPER_LINK:-$XDG_BIN_HOME/svm}"
BASE_DIR="${HOME}/.svm"
RESTORE_FROM_BACKUP=false
CUSTOM_BACKUP_PATH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to detect backup directories
find_backups() {
    # Find all svm-backup-* directories in the home directory
    find "$HOME" -maxdepth 1 -type d -name "svm-backup-*" 2>/dev/null | sort -r
}

# Function to validate a backup directory
validate_backup() {
    local backup_dir="$1"
    # Check if this is a valid SVM backup
    if [ -d "$backup_dir/vaults" ] || [ -f "$backup_dir/.vault_registry" ]; then
        return 0  # Valid backup
    else
        return 1  # Invalid backup
    fi
}

# Function to restore from backup
restore_from_backup() {
    local backup_dir="$1"
    local target_dir="$BASE_DIR"
    
    echo "${BLUE}Restoring from backup: $backup_dir${NC}"
    
    # Check if the backup is valid
    if ! validate_backup "$backup_dir"; then
        echo "${RED}❌ Invalid backup directory: $backup_dir${NC}"
        echo "   The directory does not contain valid SVM data."
        return 1
    fi
    
    # Create target directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Check if the target directory already has data
    if [ -d "$target_dir/vaults" ] || [ -f "$target_dir/.vault_registry" ]; then
        echo "${YELLOW}⚠️ Existing data found in $target_dir${NC}"
        printf "${BOLD}Overwrite existing data? [y/N]: ${NC}"
        read -r overwrite
        
        # Convert to lowercase for case-insensitive comparison
        overwrite_lower=$(echo "$overwrite" | tr '[:upper:]' '[:lower:]')
        
        if [ "$overwrite_lower" != "y" ] && [ "$overwrite_lower" != "yes" ]; then
            echo "${YELLOW}Restoration cancelled.${NC}"
            return 1
        fi
        
        echo "Removing existing data..."
    fi
    
    # Clear target directory but keep the directory itself
    rm -rf "$target_dir"/*
    rm -rf "$target_dir"/.[!.]* 2>/dev/null || true
    rm -rf "$target_dir"/..?* 2>/dev/null || true
    
    # Copy backup data
    echo "Copying data from backup..."
    if cp -a "$backup_dir/." "$target_dir" 2>/dev/null; then
        # Set secure permissions
        chmod 700 "$target_dir"
        chmod 700 "$target_dir/logs" 2>/dev/null || true
        chmod 700 "$target_dir/vaults" 2>/dev/null || true
        chmod 600 "$target_dir/logs/.security.log" 2>/dev/null || true
        chmod 600 "$target_dir/.vault_registry" 2>/dev/null || true
        
        echo "${GREEN}✅ Backup restored successfully!${NC}"
        return 0
    else
        echo "${RED}❌ Failed to restore from backup.${NC}"
        return 1
    fi
}

# Function to create a default vault after fresh installation
create_default_vault() {
    local default_vault_name="default"
    local default_vault_path="$BASE_DIR/vaults/$default_vault_name"
    
    echo "${BLUE}Creating default vault...${NC}"
    
    # Create the default vault directory
    mkdir -p "$default_vault_path"
    chmod 700 "$default_vault_path"
    
    # Add to vault registry
    echo "$default_vault_name|$(date '+%Y-%m-%d %H:%M:%S')|$(whoami)" >> "$BASE_DIR/.vault_registry"
    
    # Set as current vault
    echo "$default_vault_name" > "$BASE_DIR/.current_vault"
    chmod 600 "$BASE_DIR/.current_vault"
    
    # Create default configuration file for the vault
    cat > "$default_vault_path/.svm.conf" << 'EOF'
# SVM Configuration File
PBKDF2_ITERATIONS=600000
CIPHER=aes-256-cbc
DIGEST=sha512
VAULT_VERSION=2.0
PASSPHRASE_TIMEOUT=300
MAX_LOGIN_ATTEMPTS=3
CONNECTION_TIMEOUT=30
CACHE_ENABLED=true
LOG_MAX_LINES=1000
VERIFY_INTEGRITY=true
AUTO_BACKUP=true
BACKUP_RETENTION=5
EOF
    chmod 600 "$default_vault_path/.svm.conf"
    
    echo "${GREEN}✅ Default vault '$default_vault_name' created successfully.${NC}"
    echo "${CYAN}You can start adding servers to your vault using the 'svm' command.${NC}"
}

usage() {
  echo "Usage: $0 [--install-dir DIR] [--wrapper PATH]"
  echo
  echo "  --install-dir DIR  where to copy code (default: $INSTALL_DIR)"
  echo "  --wrapper PATH     where to place 'svm' wrapper (default: $WRAPPER_LINK)"
  echo "  -h, --help         show this help and exit"
  exit 1
}

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="$2"; shift 2 ;;
    --wrapper)
      WRAPPER_LINK="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1"; usage ;;
  esac
done

# Check for existing backups
BACKUPS=$(find_backups)
BACKUP_COUNT=$(echo "$BACKUPS" | grep -v "^$" | wc -l)

# Handle backup restoration if backups are found
if [ "$BACKUP_COUNT" -gt 0 ]; then
    echo "${BLUE}${BOLD}=== SSH Vault Manager Installation ===${NC}"
    echo
    echo "${GREEN}Found $BACKUP_COUNT previous backup(s):${NC}"
    
    # List the first 5 backups with their timestamps
    echo "$BACKUPS" | head -5 | while read -r backup_dir; do
        # Extract timestamp from directory name
        timestamp=$(echo "$backup_dir" | grep -o '[0-9]\{8\}-[0-9]\{6\}')
        # Convert timestamp to readable format
        if [ -n "$timestamp" ]; then
            year=$(echo "$timestamp" | cut -c1-4)
            month=$(echo "$timestamp" | cut -c5-6)
            day=$(echo "$timestamp" | cut -c7-8)
            hour=$(echo "$timestamp" | cut -c10-11)
            minute=$(echo "$timestamp" | cut -c12-13)
            second=$(echo "$timestamp" | cut -c14-15)
            readable_date="$year-$month-$day $hour:$minute:$second"
            
            # Check if the backup is valid
            if validate_backup "$backup_dir"; then
                status="${GREEN}(valid)${NC}"
            else
                status="${RED}(invalid)${NC}"
            fi
            
            echo "  • ${CYAN}$backup_dir${NC} [$readable_date] $status"
        else
            echo "  • ${CYAN}$backup_dir${NC} ${YELLOW}(unknown date)${NC}"
        fi
    done
    
    # Show ellipsis if there are more than 5 backups
    if [ "$BACKUP_COUNT" -gt 5 ]; then
        remaining=$((BACKUP_COUNT - 5))
        echo "  ... and $remaining more backup(s)"
    fi
    
    echo
    echo "${BOLD}What would you like to do?${NC}"
    echo "${CYAN}  1. ${NC}Continue with fresh installation (ignore backups)"
    echo "${CYAN}  2. ${NC}Restore from most recent backup"
    echo "${CYAN}  3. ${NC}List all backups and choose one"
    echo "${CYAN}  4. ${NC}Specify a custom backup location"
    printf "${BOLD}Enter option [1-4] (default: 1): ${NC}"
    read -r option_number
    
    case "$option_number" in
        2)
            MOST_RECENT_BACKUP=$(echo "$BACKUPS" | head -1)
            if [ -n "$MOST_RECENT_BACKUP" ]; then
                if restore_from_backup "$MOST_RECENT_BACKUP"; then
                    RESTORE_FROM_BACKUP=true
                fi
            else
                echo "${RED}No valid backup found.${NC}"
            fi
            ;;
        3)
            echo
            echo "${BOLD}Available backups:${NC}"
            backup_index=1
            echo "$BACKUPS" | while read -r backup_dir; do
                if [ -n "$backup_dir" ]; then
                    # Extract timestamp from directory name
                    timestamp=$(echo "$backup_dir" | grep -o '[0-9]\{8\}-[0-9]\{6\}')
                    # Convert timestamp to readable format
                    if [ -n "$timestamp" ]; then
                        year=$(echo "$timestamp" | cut -c1-4)
                        month=$(echo "$timestamp" | cut -c5-6)
                        day=$(echo "$timestamp" | cut -c7-8)
                        hour=$(echo "$timestamp" | cut -c10-11)
                        minute=$(echo "$timestamp" | cut -c12-13)
                        second=$(echo "$timestamp" | cut -c14-15)
                        readable_date="$year-$month-$day $hour:$minute:$second"
                        
                        # Check if the backup is valid
                        if validate_backup "$backup_dir"; then
                            status="${GREEN}(valid)${NC}"
                        else
                            status="${RED}(invalid)${NC}"
                        fi
                        
                        echo "  $backup_index. ${CYAN}$backup_dir${NC} [$readable_date] $status"
                    else
                        echo "  $backup_index. ${CYAN}$backup_dir${NC} ${YELLOW}(unknown date)${NC}"
                    fi
                    backup_index=$((backup_index + 1))
                fi
            done
            
            printf "${BOLD}Enter backup number to restore (or 0 to skip): ${NC}"
            read -r backup_number
            
            if [ "$backup_number" -gt 0 ] 2>/dev/null; then
                selected_backup=$(echo "$BACKUPS" | sed -n "${backup_number}p")
                if [ -n "$selected_backup" ]; then
                    if restore_from_backup "$selected_backup"; then
                        RESTORE_FROM_BACKUP=true
                    fi
                else
                    echo "${RED}Invalid selection.${NC}"
                fi
            else
                echo "${YELLOW}Skipping backup restoration.${NC}"
            fi
            ;;
        4)
            printf "${BOLD}Enter path to backup directory: ${NC}"
            read -r custom_backup
            
            if [ -d "$custom_backup" ]; then
                if restore_from_backup "$custom_backup"; then
                    RESTORE_FROM_BACKUP=true
                fi
            else
                echo "${RED}Directory not found: $custom_backup${NC}"
            fi
            ;;
        *)
            echo "${YELLOW}Proceeding with fresh installation.${NC}"
            ;;
    esac
    
    echo
fi

echo "${BLUE}${BOLD}Installing SSH Vault Manager...${NC}"
echo "  • Installation directory: ${CYAN}$INSTALL_DIR${NC}"
echo "  • Wrapper script: ${CYAN}$WRAPPER_LINK${NC}"

# Ensure bin dir exists and is in PATH
mkdir -p "$XDG_BIN_HOME"
case ":$PATH:" in
  *":$XDG_BIN_HOME:"*) ;;
  *)
    echo "Warning: $XDG_BIN_HOME is not in your PATH."
    echo "  Add to your shell RC: export PATH=\"$XDG_BIN_HOME:\$PATH\""
    ;;
esac

# Mirror project into INSTALL_DIR
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"/*
  rm -rf "$INSTALL_DIR"/.[!.]* 2>/dev/null || :
  rm -rf "$INSTALL_DIR"/..?* 2>/dev/null || :
else
  mkdir -p "$INSTALL_DIR"
fi

# Initialize SVM directory structure (if not restored from backup)
if [ "$RESTORE_FROM_BACKUP" != "true" ]; then
    echo "Creating SVM directory structure at: $BASE_DIR"

    # Create required directories
    mkdir -p "${BASE_DIR}/logs"
    mkdir -p "${BASE_DIR}/vaults"

    # Set secure permissions
    chmod 700 "$BASE_DIR"
    chmod 700 "${BASE_DIR}/logs"
    chmod 700 "${BASE_DIR}/vaults"

    # Create initial security log
    touch "${BASE_DIR}/logs/.security.log"
    chmod 600 "${BASE_DIR}/logs/.security.log"

    # Create vault registry if it doesn't exist
    touch "${BASE_DIR}/.vault_registry"
    chmod 600 "${BASE_DIR}/.vault_registry"

    # Create a default vault for fresh installations
    create_default_vault
else
    echo "${GREEN}Using restored data directory: $BASE_DIR${NC}"
fi

# Copy all files (including hidden, except . and ..)
# 1) regular
cp -R * "$INSTALL_DIR"/
# 2) hidden files
cp -R .[!.]* "$INSTALL_DIR"/ 2>/dev/null || :
cp -R ..?*  "$INSTALL_DIR"/ 2>/dev/null || :

# Create the svm wrapper
cat > "$WRAPPER_LINK" <<EOF
#!/usr/bin/env sh
exec "$INSTALL_DIR/svm.sh" "\$@"
EOF
chmod +x "$WRAPPER_LINK"

# Create the svm-update wrapper
cat > "${XDG_BIN_HOME}/svm-update" <<EOF
#!/usr/bin/env sh
exec "${INSTALL_DIR}/update.sh" "\$@"
EOF
chmod +x "${XDG_BIN_HOME}/svm-update"

# Create the svm-uninstall wrapper
cat > "${XDG_BIN_HOME}/svm-uninstall" <<EOF
#!/usr/bin/env sh
exec "${INSTALL_DIR}/uninstall.sh" "\$@"
EOF
chmod +x "${XDG_BIN_HOME}/svm-uninstall"

echo
echo "${GREEN}${BOLD}✅ Installation complete!${NC}"
echo "   • Code:     ${CYAN}$INSTALL_DIR${NC}"
echo "   • Commands: ${CYAN}$(basename "$WRAPPER_LINK")${NC} (main command)"
echo "              ${CYAN}svm-update${NC} (update utility)"
echo "              ${CYAN}svm-uninstall${NC} (uninstall utility)"
echo "   • Data:     ${CYAN}$BASE_DIR${NC}"

if [ "$RESTORE_FROM_BACKUP" = "true" ]; then
    echo
    echo "${GREEN}Your vault data has been successfully restored.${NC}"
fi

echo
echo "${BLUE}Now you can run:${NC}"
echo "• ${CYAN}$(basename "$WRAPPER_LINK")${NC} - to manage your SSH connections"
echo "• ${CYAN}svm-update${NC} - to update SSH Vault Manager"
echo "• ${CYAN}svm-uninstall${NC} - to safely remove SSH Vault Manager"
