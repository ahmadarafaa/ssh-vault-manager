# Changelog

## v2.1.0 - [2025-07-08]
### Added
- Comprehensive version checking with `lib/version_check.sh` for dependencies like bash and openssl.
- Centralized input validation in `lib/validation.sh` covering file paths, hostnames, and more.
- Configuration loading and validation with `lib/config_validator.sh` for integrity checks and schema upgrades.
- A full test suite using `bats-core`, covering version checks, validation logic, and configuration management.

### Security
- Enhanced input validation to prevent potential injection attacks.
- Strengthened integrity checks on configuration files.
- Improved error handling to ensure no sensitive information is exposed.

### Breaking Changes
- Configuration files from versions prior to 2.0 may require manual upgrade steps provided in the upgrade notes.

### Migration Notes
- Ensure all configuration files are validated with the new schema.
- Re-run the installation with the updated scripts to ensure latest security and feature enhancements.

