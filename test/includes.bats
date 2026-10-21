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

@test "send_shoutrrr skips events not in NOTIFICATION_ON" {
    shoutrrr() { echo "called"; }
    NOTIFICATION_URL_LIST=("generic://example.com")
    NOTIFICATION_ON="success,failure"
    result=$(send_shoutrrr start "subject" "content")
    [[ -z "$result" ]]
}

@test "send_shoutrrr sends to every URL even if one fails" {
    shoutrrr() { [[ "$3" != fail* ]]; }
    NOTIFICATION_URL_LIST=("fail://a" "generic://b")
    NOTIFICATION_ON="failure"
    result=$(send_shoutrrr failure "subject" "content")
    [[ "$result" == *"fail failure notification sending has failed"* ]]
    [[ "$result" == *"generic failure notification has been sent successfully"* ]]
}

@test "send_shoutrrr masks URL credentials in errors" {
    shoutrrr() { echo "Post https://api/bot123:SECRETTOKEN/send failed"; return 1; }
    NOTIFICATION_URL_LIST=("telegram://123:SECRETTOKEN@telegram?chats=1")
    NOTIFICATION_ON="failure"
    result=$(send_shoutrrr failure "subject" "content")
    [[ "$result" == *"has failed"* ]]
    [[ "$result" != *"SECRETTOKEN"* ]]
}

@test "init_env_notification drops invalid URLs" {
    shoutrrr() { [[ "$3" != bad* ]]; }
    export NOTIFICATION_URLS="generic://a
    bad://b   ntfy://c"
    result=$(init_env_notification; echo "${NOTIFICATION_URL_LIST[*]}")
    [[ "$result" == *"ignoring invalid bad URL"* ]]
    [[ "$result" == *"generic://a ntfy://c" ]]
}
