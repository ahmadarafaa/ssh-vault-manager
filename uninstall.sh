#!/usr/bin/env sh

# ============================================================================
# SSH Vault Manager Uninstaller
# ============================================================================
# This script safely removes SSH Vault Manager components installed by install.sh
# It removes application files, wrapper scripts, and optionally data files.
# Supports interactive mode with backup options for vault data.
# ============================================================================

# Exit on error or undefined var
set -eu

# Default XDG locations (same as install.sh)
: "${XDG_DATA_HOME:=${HOME}/.local/share}"
: "${XDG_BIN_HOME:=${HOME}/.local/bin}"

# Default paths (same as install.sh)
INSTALL_DIR="${INSTALL_DIR:-$XDG_DATA_HOME/opt/ssh-vault-manager}"
WRAPPER_LINK="${WRAPPER_LINK:-$XDG_BIN_HOME/svm}"
DATA_DIR="${HOME}/.svm"
BACKUP_DIR=""
DEFAULT_BACKUP_DIR="${HOME}/svm-backup-$(date +%Y%m%d-%H%M%S)"

# Number of shred passes for secure deletion
SHRED_PASSES=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color


# Verify master passphrase before proceeding
echo "${BLUE}🔐 Verifying master passphrase${NC}"
echo "${YELLOW}This helps prevent accidental or unauthorized removal of SSH Vault Manager${NC}"
echo

# Self-contained passphrase verification function
verify_uninstall_passphrase() {
    # Check if .master_hash exists
    if [ ! -f "$DATA_DIR/.master_hash" ]; then
        echo "${RED}❌ Master passphrase file not found. Uninstallation requires a valid installation.${NC}"
        return 1
    fi

    # Read the passphrase
    printf "Enter master passphrase to confirm uninstallation: "
    stty -echo
    read -r input_pass
    stty echo
    printf "\n"

    # Hash the input using the same method as the main application
    input_hash=$(printf "%s" "$input_pass" | openssl dgst -sha256 | awk '{print $NF}')
    stored_hash=$(cat "$DATA_DIR/.master_hash")

    # Clear the passphrase from memory
    input_pass=""

    # Compare hashes
    if [ "$input_hash" = "$stored_hash" ]; then
        return 0
    else
        return 1
    fi
}

# Verify the master passphrase
if ! verify_uninstall_passphrase; then
    echo "${RED}❌ Master passphrase verification failed. Uninstallation aborted.${NC}"
    exit 1
fi

echo "${GREEN}✓ Master passphrase verified successfully${NC}"
echo "${YELLOW}Proceeding with uninstallation...${NC}"
echo

# Secure deletion function
secure_delete() {
    local path="$1"
    if [ -d "$path" ]; then
        find "$path" -type f -exec shred -zfu -n "$SHRED_PASSES" {} \; 2>/dev/null || true
        rm -rf "$path"  # Remove empty directories after secure file deletion
    elif [ -f "$path" ]; then
        shred -zfu -n "$SHRED_PASSES" "$path" 2>/dev/null || true
    fi
}

# Backup function
backup_data() {
    local source="$1"
    local destination="$2"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$destination"
    
    # Show what's being backed up
    echo "${BLUE}Backing up data from: $source${NC}"
    if [ -d "$source/vaults" ]; then
        local vault_count=0
        for vault_dir in "$source/vaults"/*; do
            if [ -d "$vault_dir" ]; then
                local vault_name=$(basename "$vault_dir")
                echo "  • Backing up vault: $vault_name"
                vault_count=$((vault_count + 1))
            fi
        done
        echo "${CYAN}Total vaults to backup: $vault_count${NC}"
    fi
    
    # Copy files using cp -a to preserve permissions
    if cp -a "$source/." "$destination" 2>/dev/null; then
        echo "${GREEN}✅ Data successfully backed up to: $destination${NC}"
        
        # Verify backup
        if [ -d "$destination/vaults" ]; then
            local backed_up_count=0
            for vault_dir in "$destination/vaults"/*; do
                if [ -d "$vault_dir" ]; then
                    backed_up_count=$((backed_up_count + 1))
                fi
            done
            echo "${GREEN}✓ Verified: $backed_up_count vault(s) backed up${NC}"
        fi
        
        return 0
    else
        echo "${RED}❌ Failed to backup data to: $destination${NC}"
        return 1
    fi
}

# Print usage
usage() {
  echo "Usage: $0 [--keep-data] [--force] [--backup [DIR]] [--install-dir DIR] [--wrapper PATH]"
  echo
  echo "  --keep-data        Keep user data (vaults and settings)"
  echo "  --force            Skip confirmation prompt"
  echo "  --backup [DIR]     Backup data before removal (to specified dir or default: $DEFAULT_BACKUP_DIR)"
  echo "  --install-dir DIR  Installation directory to remove (default: $INSTALL_DIR)"
  echo "  --wrapper PATH     Wrapper link to remove (default: $WRAPPER_LINK)"
  echo "  -h, --help         Show this help and exit"
  echo
  echo "Without --force, the script runs in interactive mode and guides you through options."
  exit 1
}

# Parse arguments
KEEP_DATA=false
FORCE=false
BACKUP_DATA=false

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-data)
      KEEP_DATA=true; shift ;;
    --force)
      FORCE=true; shift ;;
    --install-dir)
      INSTALL_DIR="$2"; shift 2 ;;
    --wrapper)
      WRAPPER_LINK="$2"; shift 2 ;;
    --backup)
      BACKUP_DATA=true
      if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
        BACKUP_DIR="$2"; shift 2
      else
        BACKUP_DIR="$DEFAULT_BACKUP_DIR"; shift
      fi
      ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1"; usage ;;
  esac
done

# Check if SVM is actually installed
if [ ! -e "$WRAPPER_LINK" ] && [ ! -d "$INSTALL_DIR" ]; then
  echo "${YELLOW}${BOLD}⚠️ SSH Vault Manager does not appear to be installed${NC}"
  echo "Could not find installation at:"
  echo "  • Wrapper script: ${CYAN}$WRAPPER_LINK${NC}"
  echo "  • Installation directory: ${CYAN}$INSTALL_DIR${NC}"
  echo
  echo "If SSH Vault Manager is installed in a non-standard location, please specify:"
  echo "  • ${BOLD}--wrapper PATH${NC} - Path to the wrapper script"
  echo "  • ${BOLD}--install-dir DIR${NC} - Path to the installation directory"
  echo
  echo "${BLUE}Nothing to uninstall. Exiting.${NC}"
  exit 0
fi

# Interactive mode unless --force is used
if [ "$FORCE" != "true" ]; then
  echo "${BOLD}${BLUE}=== SSH Vault Manager Uninstaller ===${NC}"
  echo
  echo "This utility will uninstall SSH Vault Manager from your system."
  echo "${CYAN}Installation details:${NC}"
  echo "  • Installation directory: $INSTALL_DIR"
  echo "  • Wrapper script: $WRAPPER_LINK"
  echo "  • Data directory: $DATA_DIR"
  
  # First prompt - data handling
  if [ "$KEEP_DATA" != "true" ] && [ "$BACKUP_DATA" != "true" ]; then
    echo
    echo "${YELLOW}Your vault data contains sensitive information about your servers.${NC}"
    echo "${BOLD}What would you like to do with your data?${NC}"
    echo "${CYAN}  1. ${NC}Keep data in current location"
    echo "${CYAN}  2. ${NC}Backup data to another location"
    echo "${CYAN}  3. ${NC}Securely delete data"
    printf "${BOLD}Enter option [1-3] (default: 1): ${NC}"
    read -r option_number
    
    case "$option_number" in
      1)
        KEEP_DATA=true
        echo "${GREEN}• Your data will be kept at: $DATA_DIR${NC}"
        ;;
      2)
        BACKUP_DATA=true
        echo
        echo "${CYAN}Backup location options:${NC}"
        echo "  1. Use default location: $DEFAULT_BACKUP_DIR"
        echo "  2. Specify custom location"
        printf "${BOLD}Enter option [1-2] (default: 1): ${NC}"
        read -r backup_option
        
        if [ "$backup_option" = "2" ]; then
          printf "${BOLD}Enter custom backup location: ${NC}"
          read -r backup_location
          if [ -n "$backup_location" ]; then
            BACKUP_DIR="$backup_location"
          else
            echo "${YELLOW}No location specified, using default.${NC}"
            BACKUP_DIR="$DEFAULT_BACKUP_DIR"
          fi
        else
          BACKUP_DIR="$DEFAULT_BACKUP_DIR"
        fi
        echo "${GREEN}• Your data will be backed up to: $BACKUP_DIR${NC}"
        ;;
      3)
        echo "${YELLOW}• Your data will be securely deleted${NC}"
        ;;
      *)
        echo "${GREEN}• Default: Keeping your data for safety${NC}"
        KEEP_DATA=true
        ;;
    esac
  else
    if [ "$KEEP_DATA" = "true" ]; then
      echo "${GREEN}• Your data will be kept at: $DATA_DIR${NC}"
    elif [ "$BACKUP_DATA" = "true" ]; then
      echo "${GREEN}• Your data will be backed up to: $BACKUP_DIR${NC}"
    fi
  fi
  
  # Secure deletion confirmation
  if [ "$KEEP_DATA" != "true" ]; then
    echo
    echo "${YELLOW}Data will be securely erased using shred with $SHRED_PASSES passes.${NC}"
    if [ "$BACKUP_DATA" != "true" ]; then
      echo "${RED}WARNING: This operation is irreversible.${NC}"
    fi
  fi
  
  # Final confirmation
  echo
  echo "${BOLD}Are you ready to continue with uninstallation?${NC}"
  printf "${BOLD}Continue? [y/N]: ${NC}"
  read -r confirm_input
  
  # Convert to lowercase for case-insensitive comparison
  confirm_input_lower=$(echo "$confirm_input" | tr '[:upper:]' '[:lower:]')
  
  if [ "$confirm_input_lower" = "y" ] || [ "$confirm_input_lower" = "yes" ]; then
    echo "${GREEN}Proceeding with uninstallation...${NC}"
  else
    echo "${YELLOW}Uninstallation cancelled.${NC}"
    exit 0
  fi
fi

# Begin uninstallation
echo
echo "${BLUE}${BOLD}Uninstalling SSH Vault Manager...${NC}"
echo

# Backup data if requested
if [ "$BACKUP_DATA" = "true" ] && [ -d "$DATA_DIR" ]; then
  echo "📦 Backing up your data..."
  if backup_data "$DATA_DIR" "$BACKUP_DIR"; then
    # Verification step
    if [ -d "$BACKUP_DIR/vaults" ] || [ -f "$BACKUP_DIR/.vault_registry" ]; then
      echo "${GREEN}✓ Backup verified successfully${NC}"
    else
      echo "${YELLOW}⚠️ Backup completed but verification could not confirm all critical files.${NC}"
      echo "   Please check the backup manually."
      
      echo
      echo "${BOLD}How would you like to proceed?${NC}"
      echo "${CYAN}  1. ${NC}Continue with uninstallation (keep original data)"
      echo "${CYAN}  2. ${NC}Continue with uninstallation (delete original data)"
      echo "${CYAN}  3. ${NC}Cancel uninstallation"
      printf "${BOLD}Enter option [1-3] (default: 1): ${NC}"
      read -r backup_proceed_option
      
      case "$backup_proceed_option" in
        2)
          echo "${YELLOW}Will proceed with deleting original data.${NC}"
          ;;
        3)
          echo "${YELLOW}Uninstallation cancelled.${NC}"
          exit 0
          ;;
        *)
          echo "${GREEN}Will keep original data for safety.${NC}"
          KEEP_DATA=true
          ;;
      esac
    fi
  else
    echo "${RED}Failed to create backup. Aborting data removal for safety.${NC}"
    KEEP_DATA=true
  fi
  echo
fi

# Remove all wrapper scripts
echo "Removing wrapper scripts..."
for wrapper in "${WRAPPER_LINK}" "${XDG_BIN_HOME}/svm-update" "${XDG_BIN_HOME}/svm-uninstall"; do
  if [ -L "$wrapper" ] || [ -f "$wrapper" ]; then
    rm -f "$wrapper"
    echo "✅ Removed wrapper script: $wrapper"
  else
    echo "ℹ️ Wrapper script not found at: $wrapper"
  fi
done

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
  echo "🗑️ Removing installation directory..."
  secure_delete "$INSTALL_DIR"
  echo "✅ Securely removed installation directory: $INSTALL_DIR"
else
  echo "ℹ️ Installation directory not found at: $INSTALL_DIR"
fi

# Handle data directory based on user choice
if [ "$KEEP_DATA" != "true" ]; then
  if [ -d "$DATA_DIR" ]; then
    # Safety check to ensure it's an SVM data directory
    if [ -f "$DATA_DIR/.vault_registry" ] || [ -d "$DATA_DIR/vaults" ]; then
      echo "🗑️ Securely removing user data directory..."
      secure_delete "$DATA_DIR"
      echo "✅ Securely removed user data directory: $DATA_DIR"
    else
      echo "${YELLOW}⚠️ $DATA_DIR doesn't look like an SVM data directory. Not removing.${NC}"
      echo "   To remove it manually, you can use: shred -zfu -n $SHRED_PASSES $DATA_DIR/* && rm -rf $DATA_DIR"
    fi
  else
    echo "ℹ️ User data directory not found at: $DATA_DIR"
  fi
else
  echo "📁 Keeping user data at: $DATA_DIR"
fi

echo
echo "${GREEN}${BOLD}SSH Vault Manager has been uninstalled.${NC}"

# Final status message
if [ "$KEEP_DATA" = "true" ]; then
  echo "📁 Your data has been preserved at: $DATA_DIR"
elif [ "$BACKUP_DATA" = "true" ]; then
  echo "📦 Your data has been backed up to: $BACKUP_DIR"
  if [ -d "$DATA_DIR" ]; then
    echo "${YELLOW}Note: Original data directory still exists at: $DATA_DIR${NC}"
  fi
else
  echo "🔒 Your data has been securely erased."
fi

echo
echo "${BLUE}Thank you for using SSH Vault Manager!${NC}"

