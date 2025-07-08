# Shared test helpers

# Source this file in your bats tests with:
# load './test_helper.bash'

setup_environment() {
    # Setup actions before executing tests
    export TEST_ENVIRONMENT="test"
}

