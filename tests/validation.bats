#!/usr/bin/env bats

load './test_helper.bash'

setup() {
    setup_environment
}

@test "validate_non_empty should fail for empty value" {
    run bash -c 'source lib/validation.sh && validate_non_empty ""'
    [ "$status" -ne 0 ]
    [ "${lines[0]}" = "Error: Input should not be empty." ]
}

@test "validate_file_path should succeed on existing file" {
    touch example.txt
    run bash -c 'source lib/validation.sh && validate_file_path "example.txt"'
    [ "$status" -eq 0 ]
    rm example.txt
}

