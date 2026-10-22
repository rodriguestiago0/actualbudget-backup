#!/bin/bash
# End-to-end test of an image against a real Actual server, seeded with the
# budget in budget.json. Each scenario runs the image's `backup` and checks
# what lands in the rclone remote:
#
#   zip         two budgets, one with end-to-end encryption, to two remotes,
#               as AES zips; both are loaded back and compared with the
#               server, and the notification and ping are sent
#   7z, tar     the other archive types
#   retention   BACKUP_KEEP_DAYS deletes only old backup files, and nothing
#               after a failed backup, which sends the failure notification
#               and makes the health check fail
#
# Usage: test/e2e/run.sh [image]   (default: actualbudget-backup:ci)

set -euo pipefail

IMAGE="${1:-actualbudget-backup:ci}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="actualbudget-backup-e2e-$$"
SERVER_URL="http://${NAME}-server:5006"
HOOK_URL="${NAME}-hook:8080"
PASSWORD='e2e-password'
E2E_PASSWORD='budget e2e secret'
# spaces, quotes and a $, to check it reaches 7z intact
ZIP_PASSWORD=' zip pa$$ "word '
WORK="$(mktemp -d)"
CHECKS=0

function cleanup() {
    docker rm -f "${NAME}-server" "${NAME}-hook" > /dev/null 2>&1 || true
    docker network rm "${NAME}" > /dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

function fail() {
    echo "FAIL: $*" >&2
    exit 1
}

function in_image() {
    docker run --rm --network "${NAME}" --user "$(id -u):$(id -g)" \
        -e ACTUAL_SERVER_URL="${SERVER_URL}" -e ACTUAL_PASSWORD="${PASSWORD}" \
        -v "${HERE}:/app/e2e:ro" -v "${WORK}:/work" \
        "$@"
}

function e2e() {
    in_image --entrypoint node "${IMAGE}" /app/e2e/e2e.mjs "$@"
}

function wait_for() {
    local _
    for _ in $(seq 60); do
        if in_image --entrypoint curl "${IMAGE}" -fsS -o /dev/null "$1" 2> /dev/null; then
            return
        fi
        sleep 1
    done
    fail "$1 did not start"
}

########################################
# Run the image's backup of the plain budget to the local remote "e2e".
# Its log and HOME, with the health check's file, are kept by scenario.
# Arguments:
#     scenario name
#     more docker options, which override the ones here
########################################
function run_backup() {
    local LOG="${WORK}/$1.log"
    mkdir -p "${WORK}/home-$1"
    local HOME_DIR="/work/home-$1"
    shift

    echo "  backup: $*" | sed "s/${ZIP_PASSWORD}/<zip password>/g; s/${E2E_PASSWORD}/<e2e password>/g"
    in_image \
        -e ACTUAL_BUDGET_URL="${SERVER_URL}" \
        -e ACTUAL_BUDGET_PASSWORD="${PASSWORD}" \
        -e ACTUAL_BUDGET_SYNC_ID="${PLAIN_ID}" \
        -e RCLONE_CONFIG_E2E_TYPE=local \
        -e RCLONE_REMOTE_NAME=e2e \
        -e HOME="${HOME_DIR}" \
        "$@" "${IMAGE}" backup > "${LOG}" 2>&1
}

########################################
# Check the health check's status after a scenario's backup.
# Arguments:
#     scenario name
#     expected exit status
########################################
function check_health() {
    local STATUS=0
    in_image -e HOME="/work/home-$1" --entrypoint /app/healthcheck.sh "${IMAGE}" > /dev/null || STATUS=$?
    [[ ${STATUS} -eq $2 ]] || fail "the health check after $1 exited with ${STATUS}, expected $2"
}

function show_log() {
    echo "----- $1 log -----" >&2
    cat "${WORK}/$1.log" >&2
}

########################################
# The one backup of a budget in a remote folder.
# Arguments:
#     folder under ${WORK}
#     sync id
#     extension
########################################
function backup_file() {
    local FILES=("${WORK}/$1/backup.$2."*".$3")
    [[ ${#FILES[@]} -eq 1 && -f "${FILES[0]}" ]] || fail "expected one backup.$2.*.$3 in $1, found: $(ls "${WORK}/$1")"
    echo "$1/$(basename "${FILES[0]}")"
}

########################################
# Unpack a backup and check it holds the same budget as the server.
# Arguments:
#     backup file under ${WORK}
#     sync id
#     e2e password of the budget, or empty
########################################
function check_backup() {
    local DIR="check-$((++CHECKS))"
    mkdir "${WORK}/${DIR}"

    case "$1" in
        *.tar) in_image --entrypoint tar "${IMAGE}" -xf "/work/$1" -C "/work/${DIR}" ;;
        *)     in_image --entrypoint 7z "${IMAGE}" x -bso0 -p"${ZIP_PASSWORD}" -o"/work/${DIR}" "/work/$1" ;;
    esac

    e2e snapshot-server "$2" "/work/${DIR}/server.json" "$3" > /dev/null
    e2e snapshot-backup "/work/${DIR}" "/work/${DIR}/backup.json" > /dev/null
    echo -n "  $1: "
    e2e compare /app/e2e/budget.json "/work/${DIR}/server.json" "/work/${DIR}/backup.json"
}

function check_method() {
    in_image --entrypoint 7z "${IMAGE}" l -slt -p"${ZIP_PASSWORD}" "/work/$1" | grep -q "^Method = .*$2" ||
        fail "$1 is not encrypted with $2"
}

function check_hook() {
    grep -qF "$1" "${WORK}/hooks.log" || fail "no request with \"$1\" in: $(cat "${WORK}/hooks.log")"
}

#################### Setup ####################

# the server version that matches the bundled Actual CLI
CLI_VERSION="$(docker run --rm --entrypoint actual "${IMAGE}" --version)"
echo "Actual CLI ${CLI_VERSION}, starting actualbudget/actual-server:${CLI_VERSION}"

docker network create "${NAME}" > /dev/null
docker run -d --name "${NAME}-server" --network "${NAME}" "actualbudget/actual-server:${CLI_VERSION}" > /dev/null

# records every request, for the notification and ping checks
touch "${WORK}/hooks.log"
docker run -d --name "${NAME}-hook" --network "${NAME}" --user "$(id -u):$(id -g)" -v "${WORK}:/work" \
    --entrypoint node "${IMAGE}" -e "
        require('http').createServer((req, res) => {
            let body = '';
            req.on('data', (d) => (body += d));
            req.on('end', () => {
                require('fs').appendFileSync('/work/hooks.log', req.method + ' ' + req.url + ' ' + body + '\n');
                res.end('ok');
            });
        }).listen(8080);" > /dev/null

wait_for "${SERVER_URL}/info"
wait_for "http://${HOOK_URL}/ready"

in_image --entrypoint curl "${IMAGE}" -fsS -o /dev/null -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PASSWORD}\"}" "${SERVER_URL}/account/bootstrap"

echo "seeding the test budgets"
e2e seed /app/e2e/budget.json /work/plain-id "E2E Plain" > /dev/null
e2e seed /app/e2e/budget.json /work/encrypted-id "E2E Encrypted" "${E2E_PASSWORD}" > /dev/null
PLAIN_ID="$(cat "${WORK}/plain-id")"
ENCRYPTED_ID="$(cat "${WORK}/encrypted-id")"

NOTIFY=(
    -e NOTIFICATION_URLS="generic://${HOOK_URL}/notify?disabletls=yes"
    -e PING_URL="http://${HOOK_URL}/ping?subject=%{subject}"
)

#################### zip ####################

echo "zip: two budgets, one encrypted, to two remotes"
run_backup zip \
    -e ACTUAL_BUDGET_SYNC_ID_1="${ENCRYPTED_ID}" \
    -e ACTUAL_BUDGET_E2E_PASSWORD_1="${E2E_PASSWORD}" \
    -e ZIP_PASSWORD="${ZIP_PASSWORD}" \
    -e RCLONE_REMOTE_DIR=/work/zip \
    -e RCLONE_REMOTE_NAME_1=e2e \
    -e RCLONE_REMOTE_DIR_1=/work/zip-copy \
    "${NOTIFY[@]}" || { show_log zip; fail "the zip backup failed"; }

for ID in "${PLAIN_ID}" "${ENCRYPTED_ID}"; do
    FILE="$(backup_file zip "${ID}" zip)"
    cmp -s "${WORK}/${FILE}" "${WORK}/zip-copy/$(basename "${FILE}")" || fail "the second remote has a different ${FILE}"
    check_method "${FILE}" AES-256
done
check_backup "$(backup_file zip "${PLAIN_ID}" zip)" "${PLAIN_ID}" ""
check_backup "$(backup_file zip "${ENCRYPTED_ID}" zip)" "${ENCRYPTED_ID}" "${E2E_PASSWORD}"

check_hook "POST /notify"
check_hook "2 budget(s) uploaded to 2 remote(s)"
check_hook "GET /ping?subject=Actual+Budget+Backup+Success"
echo "  notification and ping sent"

#################### 7z and tar ####################

echo "7z with a password"
run_backup 7z -e ZIP_TYPE=7z -e ZIP_PASSWORD="${ZIP_PASSWORD}" -e RCLONE_REMOTE_DIR=/work/7z ||
    { show_log 7z; fail "the 7z backup failed"; }
FILE="$(backup_file 7z "${PLAIN_ID}" 7z)"
check_method "${FILE}" 7zAES
check_backup "${FILE}" "${PLAIN_ID}" ""

echo "tar"
run_backup tar -e ZIP_ENABLE=FALSE -e RCLONE_REMOTE_DIR=/work/tar ||
    { show_log tar; fail "the tar backup failed"; }
check_backup "$(backup_file tar "${PLAIN_ID}" tar)" "${PLAIN_ID}" ""

#################### retention ####################

echo "retention"
OLD_BACKUP="backup.${PLAIN_ID}.20200101.zip"
mkdir -p "${WORK}/retention/folder"
for FILE in "${OLD_BACKUP}" notes.txt folder/backup.old.zip; do
    echo old > "${WORK}/retention/${FILE}"
    touch -d 2020-01-01 "${WORK}/retention/${FILE}"
done

: > "${WORK}/hooks.log"
if run_backup retention-failed -e ACTUAL_BUDGET_PASSWORD=wrong -e BACKUP_KEEP_DAYS=1 \
    -e RCLONE_REMOTE_DIR=/work/retention "${NOTIFY[@]}"; then
    show_log retention-failed
    fail "a backup with a wrong password succeeded"
fi
[[ -f "${WORK}/retention/${OLD_BACKUP}" ]] || fail "a failed backup deleted ${OLD_BACKUP}"
check_hook "GET /ping?subject=Actual+Budget+Backup+Failed"
check_hook "with 1 error(s)"
check_health retention-failed 1
echo "  a failed backup deletes nothing, sends the failure notification and is unhealthy"

run_backup retention -e BACKUP_KEEP_DAYS=1 -e RCLONE_REMOTE_DIR=/work/retention ||
    { show_log retention; fail "the retention backup failed"; }
[[ ! -e "${WORK}/retention/${OLD_BACKUP}" ]] || fail "${OLD_BACKUP} was not deleted"
[[ -f "${WORK}/retention/notes.txt" ]] || fail "notes.txt, not a backup, was deleted"
[[ -f "${WORK}/retention/folder/backup.old.zip" ]] || fail "a backup in a subfolder was deleted"
backup_file retention "${PLAIN_ID}" zip > /dev/null
check_health retention 0
echo "  only the old backup was deleted, and the next backup is healthy"

echo "all end-to-end checks passed"
