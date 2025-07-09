# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-07-09
### Added
- Comprehensive version checking with `lib/version_check.sh` for dependencies like bash and openssl.
- Centralized input validation in `lib/validation.sh` covering file paths, hostnames, and more.
- Configuration loading and validation with `lib/config_validator.sh` for integrity checks and schema upgrades.
- A full test suite using `bats-core`, covering version checks, validation logic, and configuration management.
- Improved dry-run functionality for safer execution of operations with preview capability.

### Security
- Enhanced input validation to prevent potential injection attacks.
- Strengthened integrity checks on configuration files.
- Improved error handling to ensure no sensitive information is exposed.

### Breaking Changes
- Configuration files from versions prior to 2.0 may require manual upgrade steps provided in the upgrade notes.

### Migration Notes
- Ensure all configuration files are validated with the new schema.
- Re-run the installation with the updated scripts to ensure latest security and feature enhancements.

## [2.0.1] - 2025-07-09
### Fixed
- Improved backup and restore functionality with better error handling
- Fixed directory structure creation during installation
- Enhanced security measures in lib/security.sh

### Added
- Uninstall script for clean removal of the application

## [2.0.0] - Initial Release
- Initial version of SSH Vault Manager

