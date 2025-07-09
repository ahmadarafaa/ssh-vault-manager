#!/usr/bin/env bats

load './test_helper.bash'

setup() {
    setup_environment
}

@test "Validate security level configuration" {
    run bash -c 'source lib/security.sh && check_security_level low'
    [ "$status" -eq 0 ]
    run bash -c 'source lib/security.sh && check_security_level medium'
    [ "$status" -eq 0 ]
    run bash -c 'source lib/security.sh && check_security_level high'
    [ "$status" -eq 0 ]
}

@test "Test memory wiping functionality for low security" {
    export MEMORY_SECURITY_LEVEL=low
    local value="sensitive-data"
    run bash -c 'source lib/security.sh && safe_memory_wipe value'
    [ "$status" -eq 0 ]
    [ -z "${value+x}" ]
}

@test "Test memory wiping functionality for high security" {
    export MEMORY_SECURITY_LEVEL=high
    local value="sensitive-data"
    run bash -c 'source lib/security.sh && safe_memory_wipe value'
    [ "$status" -eq 0 ]
    [ -z "${value+x}" ]
}

@test "Test variable timeout behavior" {
    export MEMORY_SECURITY_LEVEL=medium
    declare -A SENSITIVE_VAR_ACCESS
    touch reward_earnings.txt
    run bash -c 'source lib/security.sh && track_sensitive_vars reward_earnings.txt'
    [ "$status" -eq 0 ]
    rm reward_earnings.txt
}

@test "Test security level performance impact" {
    export MEMORY_SECURITY_LEVEL=high
    local start_time=$(date +%s)
    local iterations=1000
    for ((i=0; i<iterations; i++)); do
        local value="test-data-$i"
        run bash -c 'source lib/security.sh && safe_memory_wipe value'
        [ "$status" -eq 0 ]
    done
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "Duration for ${iterations} iterations: $duration seconds"
}

@test "Test memory protection features" {
    export MEMORY_SECURITY_LEVEL=medium
    # Pretend to read, write variables and ensure no unintended anomalies
    run bash -c 'source lib/security.sh && apply_memory_protection dummy_variable'
    [ "$status" -eq 0 ]
    [ -z "${dummy_variable+x}" ]
}

