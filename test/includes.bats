#!/usr/bin/env bats

# Unit tests for includes.sh functions (base features present in main)
# Run with: bats test/

setup() {
    # Source the real includes.sh relative to this test file
    . "$BATS_TEST_DIRNAME/../scripts/includes.sh"
}

@test "color function outputs message" {
    result=$(color red "test")
    [[ "$result" == *"test"* ]]
}

@test "get_env reads from environment variable" {
    export TEST_VAR="hello"
    get_env TEST_VAR
    [[ "${TEST_VAR}" == "hello" ]]
}

@test "get_env reads from _FILE secret" {
    export TEST_SECRET_FILE="${BATS_TEST_TMPDIR}/test_secret"
    echo "secret_value" > "${BATS_TEST_TMPDIR}/test_secret"
    unset TEST_SECRET
    get_env TEST_SECRET
    [[ "${TEST_SECRET}" == "secret_value" ]]
}

@test "get_env prefers env var over _FILE" {
    export TEST_PRIORITY="from_env"
    export TEST_PRIORITY_FILE="${BATS_TEST_TMPDIR}/test_priority_file"
    echo "from_file" > "${BATS_TEST_TMPDIR}/test_priority_file"
    get_env TEST_PRIORITY
    [[ "${TEST_PRIORITY}" == "from_env" ]]
}
