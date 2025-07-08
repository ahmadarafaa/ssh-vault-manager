#!/usr/bin/env sh
# ============================================================================
# SSH Vault Manager Installer v2.1.0
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

echo "Installing SSH Vault Manager to: $INSTALL_DIR"
echo "Creating wrapper at:          $WRAPPER_LINK"

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

echo
echo "✅ Installation complete!"
echo "   • Code:    $INSTALL_DIR"
echo "   • Command: $(basename "$WRAPPER_LINK")"
echo
echo "Now run '$(basename "$WRAPPER_LINK")' from any directory."
