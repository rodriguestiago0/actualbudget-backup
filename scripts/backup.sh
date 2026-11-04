#!/bin/bash

# shellcheck source=scripts/includes.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/includes.sh"

BACKUP_DIR="backup"
# limit for each Actual CLI call, so a hung server can't block later runs
ACTUAL_TIMEOUT_SECONDS=900
# tries per budget download, waiting 15s, then 30s, between them
DOWNLOAD_ATTEMPTS=3
DOWNLOAD_RETRY_SECONDS=15
FAILED_COUNT=0
UPLOADED_COUNT=0

function clear_dir() {
    rm -rf "${BACKUP_DIR}"
}

function backup_file_name() {
    local EXT="${ZIP_TYPE}"
    if [[ "${ZIP_ENABLE}" == "FALSE" ]]; then
        EXT="tar"
    fi

    BACKUP_FILE_ZIP="${BACKUP_DIR}/backup.$1.${NOW}.${EXT}"
}

########################################
# Archive a downloaded budget so it can be imported back into Actual
# (db.sqlite and metadata.json at the archive root).
# Arguments:
#     budget directory
#     archive path
########################################
function archive_budget() {
    local SOURCE_DIR="$1"
    local ARCHIVE="${PWD}/$2"
    local FILES=(db.sqlite metadata.json)
    local PASSWORD_FLAG=()

    if [[ "${ZIP_ENABLE}" == "FALSE" ]]; then
        tar -C "${SOURCE_DIR}" -cf "${ARCHIVE}" "${FILES[@]}"
        return
    fi

    # -p without a value reads the password from stdin, so it doesn't show
    # up in `ps`. Zip uses AES-256, 7z's default ZipCrypto is easily broken.
    if [[ -n "${ZIP_PASSWORD}" && "${ZIP_TYPE}" == "7z" ]]; then
        PASSWORD_FLAG=("-p" "-mhe=on")
    elif [[ -n "${ZIP_PASSWORD}" ]]; then
        PASSWORD_FLAG=("-p" "-mem=AES256")
    fi

    if [[ "${ZIP_TYPE}" == "7z" ]]; then
        (cd "${SOURCE_DIR}" && printf '%s\n' "${ZIP_PASSWORD}" | 7z a -bso0 -bsp0 -t7z -m0=lzma2 -mx=9 "${PASSWORD_FLAG[@]}" "${ARCHIVE}" "${FILES[@]}")
    else
        (cd "${SOURCE_DIR}" && printf '%s\n' "${ZIP_PASSWORD}" | 7z a -bso0 -bsp0 -tzip -mx=9 "${PASSWORD_FLAG[@]}" "${ARCHIVE}" "${FILES[@]}")
    fi
}

########################################
# Check that a downloaded budget database is not corrupt, with the SQLite
# module the Actual CLI uses.
# Arguments:
#     db.sqlite path
# Returns:
#     0 if it is fine or better-sqlite3 is not installed, 1 if it is
#     corrupt, 4 if better-sqlite3 cannot load (a problem of the install or
#     image, not of the budget)
########################################
function check_database() {
    local STATUS=0

    # node_modules of the Actual CLI, next to its .bin
    NODE_MODULES="$(dirname "$(dirname "$(command -v actual)")")" node -e '
        let Database;
        try {
            Database = require("module").createRequire(process.env.NODE_MODULES + "/")("better-sqlite3");
        } catch {
            process.exit(3);
        }
        // the native binding only loads when a database is opened
        try {
            new Database(":memory:").close();
        } catch (error) {
            console.error(error.message);
            process.exit(4);
        }
        let result;
        try {
            const db = new Database(process.argv[1], { readonly: true, fileMustExist: true });
            result = db.pragma("integrity_check", { simple: true });
        } catch (error) {
            result = error.message;
        }
        if (result !== "ok") {
            console.error(result);
            process.exit(1);
        }
    ' "$1" || STATUS=$?

    if [[ ${STATUS} -eq 3 ]]; then
        color yellow "skipping the database check, better-sqlite3 was not found next to the Actual CLI"
        return 0
    fi
    return ${STATUS}
}

########################################
# Check that an archive can be read back, with its password.
# Arguments:
#     archive path
########################################
function check_archive() {
    if [[ "${ZIP_ENABLE}" == "FALSE" ]]; then
        tar -tf "$1" > /dev/null
        return
    fi

    # unlike `7z a`, `7z t -p` doesn't read the password from stdin; without
    # -p it asks for it there when the archive is encrypted
    printf '%s\n' "${ZIP_PASSWORD}" | 7z t -bso0 -bsp0 "$1"
}

########################################
# Download one budget with the Actual CLI and archive it.
# Arguments:
#     sync id
#     e2e password (optional)
########################################
function download_budget() {
    local SYNC_ID="$1"
    local DATA_DIR
    local BUDGET_DIR
    local ATTEMPT

    backup_file_name "${SYNC_ID}"
    color blue "downloading budget $(color yellow "[${SYNC_ID} -> ${BACKUP_FILE_ZIP}]")"

    # a few tries, each in an empty data dir, so a server restart or a proxy
    # error at backup time doesn't lose the backup
    for ATTEMPT in $(seq "${DOWNLOAD_ATTEMPTS}"); do
        DATA_DIR="$(mktemp -d)"
        # pass secrets through the environment so they don't show up in `ps`
        if ACTUAL_SERVER_URL="${ACTUAL_BUDGET_URL}" \
            ACTUAL_PASSWORD="${ACTUAL_BUDGET_PASSWORD}" \
            ACTUAL_ENCRYPTION_PASSWORD="$2" \
            timeout "${ACTUAL_TIMEOUT_SECONDS}" actual --data-dir "${DATA_DIR}" budgets download "${SYNC_ID}" > /dev/null; then
            break
        fi
        rm -rf "${DATA_DIR}"

        if [[ ${ATTEMPT} -eq ${DOWNLOAD_ATTEMPTS} ]]; then
            color red "download failed \"${SYNC_ID}\""
            return 1
        fi
        color yellow "download failed \"${SYNC_ID}\", trying again in $((ATTEMPT * DOWNLOAD_RETRY_SECONDS))s"
        sleep $((ATTEMPT * DOWNLOAD_RETRY_SECONDS))
    done

    BUDGET_DIR="$(dirname "$(find "${DATA_DIR}" -mindepth 2 -maxdepth 2 -name db.sqlite | head -n 1)")"
    if [[ ! -f "${BUDGET_DIR}/db.sqlite" ]]; then
        color red "downloaded budget not found in \"${DATA_DIR}\""
        rm -rf "${DATA_DIR}"
        return 1
    fi

    local STATUS=0
    check_database "${BUDGET_DIR}/db.sqlite" || STATUS=$?
    if [[ ${STATUS} -eq 4 ]]; then
        color red "the database check could not load better-sqlite3, so \"${SYNC_ID}\" could not be checked. This is a problem of the image or install, not of your budget: please report it"
        rm -rf "${DATA_DIR}"
        return 1
    elif [[ ${STATUS} -ne 0 ]]; then
        color red "the downloaded budget is corrupt \"${SYNC_ID}\""
        rm -rf "${DATA_DIR}"
        return 1
    fi

    archive_budget "${BUDGET_DIR}" "${BACKUP_FILE_ZIP}"
    STATUS=$?
    rm -rf "${DATA_DIR}"

    if [[ ${STATUS} -ne 0 || ! -s "${BACKUP_FILE_ZIP}" ]]; then
        color red "archive failed \"${BACKUP_FILE_ZIP}\""
        rm -f "${BACKUP_FILE_ZIP}"
        return 1
    fi

    if ! check_archive "${BACKUP_FILE_ZIP}"; then
        color red "the archive cannot be read back \"${BACKUP_FILE_ZIP}\""
        rm -f "${BACKUP_FILE_ZIP}"
        return 1
    fi
}

########################################
# Warn when the Actual server is older than the bundled CLI. The CLI applies
# its own database migrations, so the backup can only be imported into an
# Actual version at least as new as the CLI.
########################################
function check_server_version() {
    local CLI_VERSION
    local SERVER_VERSION

    CLI_VERSION="$(actual --version 2> /dev/null)"
    SERVER_VERSION="$(ACTUAL_SERVER_URL="${ACTUAL_BUDGET_URL}" \
        ACTUAL_PASSWORD="${ACTUAL_BUDGET_PASSWORD}" \
        timeout "${ACTUAL_TIMEOUT_SECONDS}" actual server version 2> /dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"

    if [[ -z "${SERVER_VERSION}" ]]; then
        color yellow "could not determine the Actual server version (Actual CLI ${CLI_VERSION})"
        return
    fi

    color blue "Actual server ${SERVER_VERSION}, Actual CLI ${CLI_VERSION}"

    if version_lt "${SERVER_VERSION}" "${CLI_VERSION}"; then
        color yellow "WARNING: your Actual server (${SERVER_VERSION}) is older than the Actual CLI in this image (${CLI_VERSION})."
        color yellow "WARNING: these backups can only be imported into Actual ${CLI_VERSION} or newer. Upgrade Actual, or use an image release whose bundled CLI is not newer than your server."
        send_notification warning "Your Actual server (${SERVER_VERSION}) is older than the Actual CLI in this image (${CLI_VERSION}): this backup can only be imported into Actual ${CLI_VERSION} or newer."
    fi
}

function backup() {
    mkdir -p "${BACKUP_DIR}"

    local i
    for i in "${!ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        if ! download_budget "${ACTUAL_BUDGET_SYNC_ID_LIST[$i]}" "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[$i]:-}"; then
            ((FAILED_COUNT++))
        fi
    done

    ls -lah "${BACKUP_DIR}"
}

function upload() {
    local BACKUP_FILES=("${BACKUP_DIR}"/*)

    if [[ ! -e "${BACKUP_FILES[0]}" ]]; then
        color red "Nothing has been backed up!"
        exit 1
    fi

    UPLOADED_COUNT=${#BACKUP_FILES[@]}

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        for BACKUP_FILE in "${BACKUP_FILES[@]}"
        do
            color blue "upload backup file to storage system $(color yellow "[${BACKUP_FILE} -> ${RCLONE_REMOTE_X}]")"

            # shellcheck disable=SC2086 # RCLONE_GLOBAL_FLAG holds multiple flags
            if ! rclone ${RCLONE_GLOBAL_FLAG} copy "${BACKUP_FILE}" "${RCLONE_REMOTE_X}"; then
                color red "upload failed"
                ((FAILED_COUNT++))
            fi
        done
    done
}

function clear_history() {
    if [[ "${FAILED_COUNT}" -gt 0 ]]; then
        color yellow "skip deleting old backup files because this backup had errors"
        return
    fi

    if [[ "${BACKUP_KEEP_DAYS}" -eq 0 ]]; then
        return
    fi

    local RETENTION_ERRORS=()
    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color blue "delete backup files older than ${BACKUP_KEEP_DAYS} days $(color yellow "[${RCLONE_REMOTE_X}]")"

        # one call that lists and deletes in the same folder, and only this
        # tool's backup files, so other files and subfolders are never
        # deleted; -v logs each deleted file
        # shellcheck disable=SC2086
        if ! rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}" --max-depth 1 \
            --include 'backup.*.{zip,7z,tar}' --min-age "${BACKUP_KEEP_DAYS}d" -v; then
            color red "deleting old backup files failed $(color yellow "[${RCLONE_REMOTE_X}]")"
            RETENTION_ERRORS+=("${RCLONE_REMOTE_X}")
        fi
    done

    # the backups themselves worked, so this is only a warning
    if [[ ${#RETENTION_ERRORS[@]} -gt 0 ]]; then
        send_notification warning "Old backups could not be deleted from: ${RETENTION_ERRORS[*]}. Check the logs."
    fi
}

########################################
# Report the result of the backup, including early exits.
########################################
function on_exit() {
    local STATUS=$?
    local NOW_TEXT
    NOW_TEXT="$(date +"%Y-%m-%d %H:%M:%S %Z")"

    if [[ -n "${WORK_DIR:-}" ]]; then
        rm -rf "${WORK_DIR}"
    fi

    # for the health check; writable by all, so a backup run by root (e.g.
    # `docker exec`) doesn't stop the PUID user from updating it. A failed
    # backup keeps the time of the last successful one.
    local RESULT="ok: the last backup finished at ${NOW_TEXT}"
    local LAST_SUCCESS
    LAST_SUCCESS="$(sed -n 's/^last_success=//p' "${LAST_BACKUP_FILE}" 2> /dev/null)"
    if [[ ${STATUS} -ge 128 ]]; then
        RESULT="failed: the last backup was stopped at ${NOW_TEXT} before it finished"
    elif [[ ${STATUS} -ne 0 ]]; then
        RESULT="failed: the last backup failed at ${NOW_TEXT}, check the logs"
    else
        LAST_SUCCESS="$(date +%s)"
    fi
    { printf '%s\n' "${RESULT}" ${LAST_SUCCESS:+"last_success=${LAST_SUCCESS}"} > "${LAST_BACKUP_FILE}" &&
        chmod a+rw "${LAST_BACKUP_FILE}"; } 2> /dev/null

    if [[ ${STATUS} -eq 0 ]]; then
        send_notification success "Backup finished at ${NOW_TEXT}. ${UPLOADED_COUNT} budget(s) uploaded to ${#RCLONE_REMOTE_LIST[@]} remote(s)."
    elif [[ ${STATUS} -ge 128 ]]; then
        send_notification failure "Backup stopped at ${NOW_TEXT} before it finished (signal $((STATUS - 128)))."
    elif [[ "${FAILED_COUNT}" -gt 0 ]]; then
        send_notification failure "Backup finished at ${NOW_TEXT} with ${FAILED_COUNT} error(s). Check the logs for details."
    else
        send_notification failure "Backup failed at ${NOW_TEXT}. Check the logs for details."
    fi
}

trap on_exit EXIT
# Without these, the EXIT trap sees the last command's status (usually 0) when the backup is
# stopped, and reports a backup that never finished as a success.
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP

init_env
unexport_secrets

# after init_env, so the time is in the configured TIMEZONE
color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

send_notification start "Backup started at $(date +"%Y-%m-%d %H:%M:%S %Z")."

NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"

# work in a temporary folder, writable whichever user runs the backup
WORK_DIR="$(mktemp -d)"
cd "${WORK_DIR}" || exit 1

check_rclone_connection any

check_server_version

clear_dir
backup
upload
clear_dir
clear_history

if [[ "${FAILED_COUNT}" -gt 0 ]]; then
    color red "backup finished with ${FAILED_COUNT} error(s)"
    exit 1
fi

color green "backup finished successfully"
