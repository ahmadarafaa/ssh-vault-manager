# 🔐 SSH Vault Manager (SVM)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell%20Script-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](https://en.wikipedia.org/wiki/Linux)
[![Version](https://img.shields.io/badge/Version-2.0.1-green.svg)](https://github.com/ahmadarafaa/ssh-vault-manager/releases)

> **Unlock powerful SSH management with modular architecture, encrypted vaults, and advanced features—including secure, interactive password-based server access for effortless and safe connections.**

This script is designed to securely manage and store SSH passwords. It provides encrypted vault storage and safe, interactive password-based SSH connections—all within a modular, extensible framework.

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [✨ Features](#-features)
- [🚀 Installation](#-installation)
- [📖 Usage](#-usage)
- [🔧 Configuration](#-configuration)
- [📁 Project Structure](#-project-structure)
- [🛡️ Security Features](#-security-features)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

## 🎯 Overview

SSH Vault Manager (SVM) is a comprehensive bash-based tool designed for managing multiple SSH servers with enhanced security features. It provides encrypted vault storage, secure authentication, and a user-friendly interface for server operations.

### What does it do?
- **Secure Server Credential Storage**: Organize and protect SSH credentials for servers across multiple environments
- **Interactive Interface**: Beautiful, intuitive menu-driven interface
- **Advanced Operations**: Connect, search, backup, and manage servers efficiently
- **Modular Architecture**: Clean, maintainable codebase with separated concerns

### Why was it created?
Managing multiple SSH servers with different credentials can be challenging and insecure. Traditional methods like storing passwords in plain text or using SSH keys without proper organization can lead to security vulnerabilities and operational inefficiencies.

## ✨ Features

### 🔐 Security Features
- **AES-256 Encryption**: All vault data is encrypted using industry-standard encryption
- **Password Protection**: Master passphrase required for vault access
- **Secure Credential Storage**: No plain text passwords stored
- **Session Management**: Automatic cleanup and secure session handling

### 🗂️ Vault Management
- **Multiple Vaults**: Create and manage separate vaults for different environments
- **Import/Export**: Secure vault migration and backup capabilities
- **Vault Operations**: Create, delete, rename, and manage vaults

### 🔍 Server Operations
- **Global Search**: Search across all vaults simultaneously
- **Server Information**: Detailed server details and statistics
- **Connection Logging**: Track connection history and usage

### 🎨 User Experience
- **Beautiful Interface**: Color-coded, intuitive menu system
- **Error Handling**: Robust error handling with user-friendly messages
- **Input Validation**: Comprehensive input validation and retry mechanisms
- **Progress Feedback**: Clear status messages and progress indicators

## 🚀 Installation

### Recommended: Automated Installer

Run the provided install script for a portable, user-local installation:

```sh
sh install.sh
```

- By default, this will install all files to `~/.local/share/opt/ssh-vault-manager` and create a wrapper command `svm` in `~/.local/bin`.
- You can customize the install location and wrapper name:
  ```sh
  sh install.sh --install-dir /your/path --wrapper /usr/local/bin/svm
  ```
- After install, you can run `svm` from any directory (ensure `~/.local/bin` is in your PATH).

#### What does install.sh do?
- Copies all project files to your chosen install directory (default: user-local XDG path)
- Creates a lightweight wrapper script (`svm`) in your user bin directory
- Warns if the bin directory is not in your PATH
- Does not require root or sudo (unless you choose a system-wide location)
- Creates all necessary directory structures for SVM operation

### Uninstallation

To cleanly remove SSH Vault Manager, use the provided uninstall script:

```sh
svm-uninstall
```

Alternatively, you can run the uninstall script directly:

```sh
sh ~/.local/share/opt/ssh-vault-manager/uninstall.sh
```

This will:
- Remove all SVM files from your installation directory
- Delete the wrapper script from your bin directory
- Provide an option to keep or remove your vault data
- Thoroughly clean up any temporary or leftover files

### Manual Installation (Advanced)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ahmadarafaa/ssh-vault-manager.git
   cd ssh-vault-manager
   ```
2. **Set execution permissions:**
   ```bash
   chmod +x svm.sh
   chmod +x lib/*.sh
   ```
3. **Run the script:**
   ```bash
   ./svm.sh
   ```

## 📖 Usage

### First Time Setup

1. **Install SVM (recommended):**
   ```sh
   sh install.sh
   ```
   After installation, use the `svm` command from any directory:
   ```sh
   svm
   ```

2. **Create your first vault:**
   - Select "Vault Management" → "Create New Vault"
   - Enter a vault name (e.g., "production-servers")
   - Set a master passphrase

3. **Add your first server:**
   - Select "Server Management" → "Add Server"
   - Enter server details (name, IP, username, password, port)
   - The server will be encrypted and stored securely

### Daily Operations

#### Connecting to Servers
```sh
svm
# Select "Connect to Server" → Choose server → Connect
```

#### Managing Multiple Environments
```sh
svm
# Vault Management → Create New Vault
# - production-vault
# - staging-vault
# - development-vault
```

#### Searching Across All Servers
```sh
svm
# Select "Global Search" → Enter search term
```

### Advanced Usage

#### Importing Existing Server Lists
```sh
svm
# Vault Management → Import Vault → Select file
```

#### Exporting Vaults
```sh
svm
# Vault Management → Export Vault → Choose format
```

## 🔧 Configuration

### Environment Variables
| Variable         | Description                        | Default      |
|------------------|------------------------------------|--------------|
| `SVM_VAULT_DIR`  | Base directory for vaults          | `~/.svm`     |
| `SVM_LOG_LEVEL`  | Logging level                      | `INFO`       |
| `SVM_TIMEOUT`    | Connection timeout (seconds)       | `30`         |

### File Structure
```
~/.svm/
├── vaults/
│   ├── production-vault/
│   │   ├── .vault.enc          # Encrypted server data
│   │   ├── .svm.conf           # Vault configuration
│   │   └── .connection.log     # Connection history
│   └── staging-vault/
├── .master_passphrase          # Encrypted master passphrase
└── .vault_registry             # Vault registry
```

## 📁 Project Structure
```
ssh-vault-manager/
├── svm.sh         # Main orchestrator script (entrypoint, sources all modules)
├── lib/
│   ├── config.sh
│   ├── encryption.sh
│   ├── menu.sh
│   ├── security.sh
│   ├── server.sh
│   ├── utils.sh
│   └── vault.sh
└── install.sh     # Installer script (user-local, portable)
```

## 🛡️ Security Features
- **AES-256-CBC** encryption for all sensitive data
- **PBKDF2** key derivation for master passphrase
- **Random SALT** generation for each encryption operation
- **Secure cleanup** of temporary files
- **Master passphrase** required for vault access
- **Session timeout** for inactive sessions
- **Input validation** to prevent injection attacks
- **Secure deletion** of sensitive data
- **No plain text** passwords stored anywhere
- **Temporary file cleanup** after operations
- **Error handling** without exposing sensitive information
- **Logging** without sensitive data exposure
- **Enhanced backup and restore** functionality with improved error handling
- **Security improvements** in handling sensitive data within `lib/security.sh`

## 🤝 Contributing
We welcome contributions! Here's how you can help:
1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test thoroughly**: Ensure all functionality works as expected
5. **Commit your changes**: `git commit -m 'Add amazing feature'`
6. **Push to the branch**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

### Code Style Guidelines
- **Bash best practices**: Follow shell scripting conventions
- **Error handling**: Implement proper error handling
- **Documentation**: Comment complex functions
- **Security**: Never expose sensitive information

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

<p align="center"><b>Made with ❤️ for the DevOps community</b></p>