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

@test "get_env fails when the _FILE secret is missing" {
    unset TEST_MISSING
    export TEST_MISSING_FILE="${BATS_TEST_TMPDIR}/does_not_exist"
    run get_env TEST_MISSING
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"TEST_MISSING_FILE: cannot read"* ]]
}

@test "init_env fails with a non-numeric BACKUP_KEEP_DAYS" {
    export BACKUP_KEEP_DAYS="7d"
    run init_env
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"BACKUP_KEEP_DAYS must be a number"* ]]
}

@test "check_rclone_connection fails when any remote is not configured" {
    rclone() {
        case "$1" in
            listremotes) printf 'first:\n' ;;
            *) return 0 ;;
        esac
    }
    RCLONE_GLOBAL_FLAG=""
    RCLONE_REMOTE_LIST=("first:/backups" "second:/backups")
    run check_rclone_connection all
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"[second]"* ]]
}

@test "healthcheck is healthy before the first backup" {
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "no backup has run yet" ]]
}

@test "healthcheck follows the last backup" {
    echo "ok: the last backup finished at today" > "${BATS_TEST_TMPDIR}/last-backup"
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 0 ]]

    echo "failed: the last backup failed at today, check the logs" > "${BATS_TEST_TMPDIR}/last-backup"
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 1 ]]
    [[ "$output" == "failed: the last backup failed at today, check the logs" ]]
}

@test "healthcheck is unhealthy when a backup is overdue" {
    printf 'start=%s\nmax_hours=26\n' "$(( $(date +%s) - 27 * 3600 ))" > "${BATS_TEST_TMPDIR}/health"
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no successful backup in the last 26 hours"* ]]

    printf 'ok: the last backup finished at today\nlast_success=%s\n' "$(( $(date +%s) - 3600 ))" > "${BATS_TEST_TMPDIR}/last-backup"
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 0 ]]

    # a recent start gives the first backup time to run
    printf 'start=%s\nmax_hours=26\n' "$(date +%s)" > "${BATS_TEST_TMPDIR}/health"
    printf 'ok: the last backup finished long ago\nlast_success=1\n' > "${BATS_TEST_TMPDIR}/last-backup"
    HOME="${BATS_TEST_TMPDIR}" run "$BATS_TEST_DIRNAME/../scripts/healthcheck.sh"
    [[ "$status" -eq 0 ]]
}

@test "cron_runs_daily tells daily schedules from rarer ones" {
    cron_runs_daily "0 0 * * *"
    cron_runs_daily "*/15 2-4 * * ?"
    cron_runs_daily "@hourly"
    cron_runs_daily "0 0 3 * * * *"
    ! cron_runs_daily "0 0 * * 0"
    ! cron_runs_daily "0 0 1 * *"
    ! cron_runs_daily "@weekly"
    ! cron_runs_daily "0 0 * * * 2027"
}

@test "init_env sets HEALTHCHECK_MAX_HOURS from CRON" {
    export ACTUAL_BUDGET_URL="https://actual" ACTUAL_BUDGET_SYNC_ID="id"
    result=$(init_env > /dev/null; echo "${HEALTHCHECK_MAX_HOURS}")
    [[ "$result" == "26" ]]
    result=$(CRON="0 0 * * 0" init_env > /dev/null; echo "${HEALTHCHECK_MAX_HOURS}")
    [[ "$result" == "0" ]]
    result=$(export CRON="0 0 * * 0" HEALTHCHECK_MAX_HOURS=170; init_env > /dev/null; echo "${HEALTHCHECK_MAX_HOURS}")
    [[ "$result" == "170" ]]
}

@test "file names have the time by default, the old variables keep the date" {
    export ACTUAL_BUDGET_URL="https://actual" ACTUAL_BUDGET_SYNC_ID="id"
    result=$(init_env > /dev/null; echo "${BACKUP_FILE_DATE_FORMAT}")
    [[ "$result" == "%Y%m%d_%H%M%S" ]]
    result=$(BACKUP_FILE_DATE_SUFFIX="-x" init_env > /dev/null; echo "${BACKUP_FILE_DATE_FORMAT}")
    [[ "$result" == "%Y%m%d-x" ]]
    result=$(BACKUP_FILE_SUFFIX="%Y/%m" BACKUP_FILE_DATE="%d" init_env > /dev/null; echo "${BACKUP_FILE_DATE_FORMAT}")
    [[ "$result" == "%Y%m" ]]
}

@test "send_shoutrrr sends warnings to failure subscribers" {
    shoutrrr() { echo "called"; }
    NOTIFICATION_URL_LIST=("generic://example.com")
    NOTIFICATION_ON="failure"
    [[ "$(send_shoutrrr warning "subject" "content")" == *"warning notification has been sent"* ]]
    NOTIFICATION_ON="success"
    [[ -z "$(send_shoutrrr warning "subject" "content")" ]]
    NOTIFICATION_ON="warning"
    [[ "$(send_shoutrrr warning "subject" "content")" == *"warning notification has been sent"* ]]
}

@test "check_rclone_connection warn continues when a remote is down" {
    rclone() {
        case "$1" in
            listremotes) printf 'first:\n' ;;
            lsd|mkdir) return 1 ;;
            *) return 0 ;;
        esac
    }
    RCLONE_GLOBAL_FLAG=""
    RCLONE_REMOTE_LIST=("first:/backups")
    run check_rclone_connection warn
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"the scheduled backup will try again"* ]]
}

@test "unexport_secrets keeps secrets from child processes" {
    export ZIP_PASSWORD="zip" ACTUAL_BUDGET_E2E_PASSWORD_1="e2e" DOTENV_X="x" RCLONE_CONFIG_A_TYPE="local"
    unexport_secrets
    [[ "${ZIP_PASSWORD}" == "zip" ]]
    [[ -z "$(bash -c 'echo "${ZIP_PASSWORD}${ACTUAL_BUDGET_E2E_PASSWORD_1}${DOTENV_X}"')" ]]
    [[ "$(bash -c 'echo "${RCLONE_CONFIG_A_TYPE}"')" == "local" ]]
}

@test "version_lt compares versions numerically" {
    version_lt 26.3.0 26.10.0
    version_lt 26.10.0 26.11.0
    version_lt 25.12.9 26.0.0
    version_lt v26.10.0 26.11.0
    version_lt 26.10 26.10.1
    ! version_lt 26.11.0 26.11.0
    ! version_lt 26.11.0-nightly.20261021 26.11.0
    ! version_lt 26.12.0 26.11.0
    ! version_lt unknown 26.11.0
}

@test "cron_runs_daily accepts full ranges and tells hourly schedules" {
    cron_runs_daily "0 3 * * 0-6"
    cron_runs_daily "0 3 * * sun-sat"
    cron_runs_daily "0 3 1-31 JAN-DEC 0-7"
    ! cron_runs_daily "0 3 * * MON-SUN"
    ! cron_runs_daily "0 3 * * 1-5"
    ! cron_runs_daily "0 3 1-12 * *"
    cron_runs_daily "@hourly" hourly
    cron_runs_daily "15 * * * *" hourly
    cron_runs_daily "0 15 0-23 * * * *" hourly
    ! cron_runs_daily "@daily" hourly
    ! cron_runs_daily "0 */2 * * *" hourly
    result=$(export ACTUAL_BUDGET_URL="https://actual" ACTUAL_BUDGET_SYNC_ID="id" CRON="5 * * * *"; init_env > /dev/null; echo "${HEALTHCHECK_MAX_HOURS}")
    [[ "$result" == "3" ]]
}

@test "export_env_file ends a double-quoted value at its closing quote" {
    ENV_FILE="${BATS_TEST_TMPDIR}/.env"
    cat > "${ENV_FILE}" <<'ENV'
A="x" # "y"
B="a\"b" # c
C="a\$b\`c"
ENV
    export_env_file > /dev/null
    [[ "${DOTENV_A}" == "x" ]]
    [[ "${DOTENV_B}" == 'a"b' ]]
    [[ "${DOTENV_C}" == 'a$b`c' ]]
}

@test "send_ping passes the text as is to options and encoded in the URL, the URL on stdin" {
    curl() { printf '[%s]' "$@"; echo; cat; }
    PING_URL='https://hc/ping?s=%{subject}&c=%{content}'
    PING_URL_CURL_OPTIONS='-d "%{content}" -H "Title: %{subject}"'
    result=$(send_ping completion "Backup Success" 'x $(echo INJECTED) "q" +0530 & é')
    [[ "$result" == *'[-d][x $(echo INJECTED) "q" +0530 & é][-H][Title: Backup Success][-K][-]'* ]]
    [[ "$result" == *'url = "https://hc/ping?s=Backup%20Success&c=x%20%24%28echo%20INJECTED%29%20%22q%22%20%2B0530%20%26%20%C3%A9"'* ]]
    [[ "$result" != *"https://hc"*"[-K]"* ]]
}

@test "clear_history deletes only old backups and warns when that fails" {
    eval "$(sed -n '/^function clear_history/,/^}/p' "$BATS_TEST_DIRNAME/../scripts/backup.sh")"
    rclone() { echo "rclone $*"; [[ "$2" != bad:* ]]; }
    send_notification() { echo "notify $1: $2"; }
    FAILED_COUNT=0 BACKUP_KEEP_DAYS=7 RCLONE_GLOBAL_FLAG=""
    RCLONE_REMOTE_LIST=("good:/b" "bad:/b")
    result=$(clear_history)
    [[ "$result" == *"rclone delete good:/b --max-depth 1 --include backup.*.{zip,7z,tar} --min-age 7d -v"* ]]
    [[ "$result" == *"notify warning: Old backups could not be deleted from: bad:/b."* ]]
    [[ "$result" != *"from: good"* ]]

    FAILED_COUNT=1
    [[ "$(clear_history)" != *"rclone delete"* ]]
}

########################################
# Stubs for running backup.sh: an actual whose download waits for the file
# named in STUB_WAIT, and an rclone with one remote "e2e".
########################################
function stub_backup_tools() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat > "${BATS_TEST_TMPDIR}/bin/actual" <<'STUB'
#!/bin/bash
case "$*" in
    --version) echo 26.11.0 ;;
    *"server version"*) echo '{"version": "26.11.0"}' ;;
    *download*) touch "${STUB_DIR}/downloading"; sleep 2; exit 1 ;;
esac
STUB
    cat > "${BATS_TEST_TMPDIR}/bin/rclone" <<'STUB'
#!/bin/bash
[[ "$1" == listremotes ]] && echo "e2e:"
exit 0
STUB
    chmod +x "${BATS_TEST_TMPDIR}/bin/"*
}

function run_stubbed_backup() {
    # exec, so a backgrounded call's PID is backup.sh itself
    exec env HOME="${BATS_TEST_TMPDIR}" PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" STUB_DIR="${BATS_TEST_TMPDIR}" \
        ACTUAL_BUDGET_URL="http://actual" ACTUAL_BUDGET_SYNC_ID="id" RCLONE_REMOTE_NAME="e2e" \
        bash "$BATS_TEST_DIRNAME/../scripts/backup.sh"
}

@test "a backup stopped by SIGTERM is reported as stopped, not as a success" {
    stub_backup_tools
    (run_stubbed_backup) > "${BATS_TEST_TMPDIR}/log" 2>&1 &
    local PID=$!
    for _ in $(seq 50); do [[ -f "${BATS_TEST_TMPDIR}/downloading" ]] && break; sleep 0.1; done
    kill -TERM "${PID}"
    local STATUS=0
    wait "${PID}" || STATUS=$?
    [[ ${STATUS} -eq 143 ]]
    grep -q "^failed: the last backup was stopped" "${BATS_TEST_TMPDIR}/last-backup"
}

@test "a second backup with the same settings is skipped while one runs" {
    stub_backup_tools
    exec 8>> "${BATS_TEST_TMPDIR}/last-backup.lock"
    flock -n 8
    run run_stubbed_backup
    exec 8>&-
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"another backup with this configuration is running"* ]]
    [[ ! -e "${BATS_TEST_TMPDIR}/last-backup" ]]
    [[ ! -e "${BATS_TEST_TMPDIR}/downloading" ]]
}
