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

@test "export_env_file reads values literally, without running them" {
    ENV_FILE="${BATS_TEST_TMPDIR}/.env"
    cat > "${ENV_FILE}" <<'ENV'
# a comment
PLAIN=abc def # trailing comment
SINGLE='pa$$ "word" #1'
DOUBLE="it's \"quoted\" \$HOME \\ ok"
export EXPORTED="x"
CMD=$(touch ${BATS_TEST_TMPDIR}/ran)
CRLF=value
EMPTY=
ENV
    printf 'CRLF2=dos\r\n' >> "${ENV_FILE}"
    export_env_file > /dev/null
    [[ "${DOTENV_PLAIN}" == "abc def" ]]
    [[ "${DOTENV_SINGLE}" == 'pa$$ "word" #1' ]]
    [[ "${DOTENV_DOUBLE}" == 'it'\''s "quoted" $HOME \ ok' ]]
    [[ "${DOTENV_EXPORTED}" == "x" ]]
    [[ "${DOTENV_CMD}" == '$(touch ${BATS_TEST_TMPDIR}/ran)' ]]
    [[ ! -e "${BATS_TEST_TMPDIR}/ran" ]]
    [[ "${DOTENV_CRLF2}" == "dos" ]]
    [[ -z "${DOTENV_EMPTY}" ]]
}

@test "e2e passwords follow their sync id, with gaps" {
    ACTUAL_BUDGET_SYNC_ID_LIST=("plain" "encrypted" "plain-2")
    ACTUAL_BUDGET_E2E_PASSWORD_0=""
    export ACTUAL_BUDGET_E2E_PASSWORD_1="secret"
    init_actual_e2e_list > /dev/null
    [[ "${#ACTUAL_BUDGET_E2E_PASSWORD_LIST[@]}" -eq 3 ]]
    [[ -z "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[0]}" ]]
    [[ "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[1]}" == "secret" ]]
    [[ -z "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[2]}" ]]
}

@test "init_actual_env fails without ACTUAL_BUDGET_URL" {
    unset ACTUAL_BUDGET_URL
    export ACTUAL_BUDGET_SYNC_ID="id"
    run init_actual_env
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"ACTUAL_BUDGET_URL is not set"* ]]
}
