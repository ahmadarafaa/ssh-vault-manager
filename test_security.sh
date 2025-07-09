#!/bin/bash

# =============================================================================
# SSH Vault Manager - Security Enhancement Test Script
# =============================================================================
# This script tests the security enhancements added to SSH Vault Manager.
# It includes tests for different security levels, memory wiping, variable
# protection, and performance measurements.
# =============================================================================

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test environment setup
TEST_DIR="/tmp/svm_test_$$"
TEST_LOG_DIR="$TEST_DIR/logs"
export SVM_TEST_MODE=true
export base_vault_dir="$TEST_DIR"

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_LOG_DIR"
    chmod 700 "$TEST_DIR" "$TEST_LOG_DIR"
    echo -e "${BLUE}Setting up test environment in:${NC} $TEST_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    echo -e "${BLUE}Cleaning up test environment:${NC} $TEST_DIR"
    rm -rf "$TEST_DIR"
}

# Set up trap for cleanup
trap cleanup_test_env EXIT

# Run setup
setup_test_env

# Load the security module
source "$SCRIPT_DIR/lib/security.sh"

# Test function
run_test() {
    local name="$1"
    local command="$2"
    
    echo -e "${BLUE}Running test:${NC} $name"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Run the command
    eval "$command"
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo -e "  ${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗ FAIL (exit code: $status)${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    return $status
}

# Performance measurement
measure_performance() {
    local name="$1"
    local command="$2"
    local iterations="$3"
    
    echo -e "${BLUE}Performance test:${NC} $name ($iterations iterations)"
    
    local start_time=$(date +%s.%N)
    
    for ((i=0; i<iterations; i++)); do
        eval "$command" > /dev/null 2>&1
    done
    
    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc)
    local per_op=$(echo "scale=6; $elapsed / $iterations" | bc)
    
    echo -e "  Total time: ${YELLOW}$elapsed seconds${NC}"
    echo -e "  Per operation: ${YELLOW}$per_op seconds${NC}"
}

# ==== Security Level Tests ====
echo -e "\n${YELLOW}=== Testing Security Levels ===${NC}"

run_test "Security level - low" "MEMORY_SECURITY_LEVEL=low; [ -n \"\${SECURITY_LEVELS[low]}\" ]"
run_test "Security level - medium" "MEMORY_SECURITY_LEVEL=medium; [ -n \"\${SECURITY_LEVELS[medium]}\" ]"
run_test "Security level - high" "MEMORY_SECURITY_LEVEL=high; [ -n \"\${SECURITY_LEVELS[high]}\" ]"

# ==== Memory Wiping Tests ====
echo -e "\n${YELLOW}=== Testing Memory Wiping ===${NC}"

run_test "Memory wiping - low security" "
    MEMORY_SECURITY_LEVEL=low
    test_var='sensitive-data-low'
    safe_memory_wipe test_var
    [ -z \"\${test_var+x}\" ]
"

run_test "Memory wiping - medium security" "
    MEMORY_SECURITY_LEVEL=medium
    test_var='sensitive-data-medium'
    safe_memory_wipe test_var
    [ -z \"\${test_var+x}\" ]
"

run_test "Memory wiping - high security" "
    MEMORY_SECURITY_LEVEL=high
    test_var='sensitive-data-high'
    safe_memory_wipe test_var
    [ -z \"\${test_var+x}\" ]
"

# ==== Variable Protection Tests ====
echo -e "\n${YELLOW}=== Testing Variable Protection ===${NC}"

run_test "Variable protection - sanitize_memory_on_exit" "
    declare -a vars=('test_var1' 'test_var2')
    test_var1='test-data-1'
    test_var2='test-data-2'
    sanitize_memory_on_exit vars
    [ -z \"\${test_var1+x}\" ] && [ -z \"\${test_var2+x}\" ]
"

# ==== Performance Tests ====
echo -e "\n${YELLOW}=== Performance Measurements ===${NC}"

# Define test iterations
ITERATIONS=1000

# Measure performance for different security levels
MEMORY_SECURITY_LEVEL=low
measure_performance "Memory wiping - LOW security" "
    test_var='performance-test-data'
    safe_memory_wipe test_var
" $ITERATIONS

MEMORY_SECURITY_LEVEL=medium
measure_performance "Memory wiping - MEDIUM security" "
    test_var='performance-test-data'
    safe_memory_wipe test_var
" $ITERATIONS

MEMORY_SECURITY_LEVEL=high
measure_performance "Memory wiping - HIGH security" "
    test_var='performance-test-data'
    safe_memory_wipe test_var
" $ITERATIONS

# ==== Test Report ====
echo -e "\n${YELLOW}=== Test Report ===${NC}"
echo -e "${BLUE}Total tests:${NC} $TESTS_TOTAL"
echo -e "${GREEN}Tests passed:${NC} $TESTS_PASSED"
echo -e "${RED}Tests failed:${NC} $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed.${NC}"
    exit 1
fi

