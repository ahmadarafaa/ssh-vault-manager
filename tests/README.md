# SSH Vault Manager Test Suite

This directory contains automated tests for the SSH Vault Manager's core modules. The testing framework uses [bats-core](https://bats-core.readthedocs.io/) for simple and effective Bash testing.

## Getting Started

### Install bats-core

```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

### Run Tests

To run all tests, navigate to this directory and execute:

```bash
bats .
```

## Directory Structure

- `test_helper.bash` - Contains shared functions and setup code used across test files.
- `version_check.bats` - Tests for version checking module.
- `validation.bats` - Tests for input validation module.
- `config_validator.bats` - Tests for configuration validation module.

## Writing Tests

- Write descriptive test cases and use assertions for validation.
- Ensure tests are isolated and do not modify global state.

