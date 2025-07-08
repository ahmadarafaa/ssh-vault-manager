#!/usr/bin/env bats

load './test_helper.bash'

setup() {
    setup_environment
}

@test "load_and_validate_config should fail for missing file" {
    run bash -c 'source lib/config_validator.sh && load_and_validate_config "missing.conf"'
    [ "$status" -ne 0 ]
    [ "${lines[0]}" = "Error: Configuration file 'missing.conf' not found." ]
}

@test "load_and_validate_config should succeed for valid file" {
    echo "REQUIRED_CONFIG_KEY=test_value" > valid.conf
    run bash -c 'source lib/config_validator.sh && load_and_validate_config "valid.conf"'
    [ "$status" -eq 0 ]
    rm valid.conf
}

