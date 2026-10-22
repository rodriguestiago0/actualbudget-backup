#!/bin/bash

# shellcheck source=scripts/includes.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/includes.sh"

BACKUP_DIR="backup"
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

    if [[ -n "${ZIP_PASSWORD}" ]]; then
        PASSWORD_FLAG=("-p${ZIP_PASSWORD}")
    fi

    if [[ "${ZIP_TYPE}" == "7z" ]]; then
        [[ -n "${ZIP_PASSWORD}" ]] && PASSWORD_FLAG+=("-mhe=on")
        (cd "${SOURCE_DIR}" && 7z a -bso0 -bsp0 -t7z -m0=lzma2 -mx=9 "${PASSWORD_FLAG[@]}" "${ARCHIVE}" "${FILES[@]}")
    else
        (cd "${SOURCE_DIR}" && 7z a -bso0 -bsp0 -tzip -mx=9 "${PASSWORD_FLAG[@]}" "${ARCHIVE}" "${FILES[@]}")
    fi
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

    DATA_DIR="$(mktemp -d)"
    backup_file_name "${SYNC_ID}"
    color blue "downloading budget $(color yellow "[${SYNC_ID} -> ${BACKUP_FILE_ZIP}]")"

    # pass secrets through the environment so they don't show up in `ps`
    if ! ACTUAL_SERVER_URL="${ACTUAL_BUDGET_URL}" \
        ACTUAL_PASSWORD="${ACTUAL_BUDGET_PASSWORD}" \
        ACTUAL_ENCRYPTION_PASSWORD="$2" \
        actual --data-dir "${DATA_DIR}" budgets download "${SYNC_ID}" > /dev/null; then
        color red "download failed \"${SYNC_ID}\""
        rm -rf "${DATA_DIR}"
        return 1
    fi

    BUDGET_DIR="$(dirname "$(find "${DATA_DIR}" -mindepth 2 -maxdepth 2 -name db.sqlite | head -n 1)")"
    if [[ ! -f "${BUDGET_DIR}/db.sqlite" ]]; then
        color red "downloaded budget not found in \"${DATA_DIR}\""
        rm -rf "${DATA_DIR}"
        return 1
    fi

    archive_budget "${BUDGET_DIR}" "${BACKUP_FILE_ZIP}"
    local STATUS=$?
    rm -rf "${DATA_DIR}"

    if [[ ${STATUS} -ne 0 || ! -s "${BACKUP_FILE_ZIP}" ]]; then
        color red "archive failed \"${BACKUP_FILE_ZIP}\""
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
        actual server version 2> /dev/null | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"

    if [[ -z "${SERVER_VERSION}" ]]; then
        color yellow "could not determine the Actual server version (Actual CLI ${CLI_VERSION})"
        return
    fi

    color blue "Actual server ${SERVER_VERSION}, Actual CLI ${CLI_VERSION}"

    if version_lt "${SERVER_VERSION}" "${CLI_VERSION}"; then
        color yellow "WARNING: your Actual server (${SERVER_VERSION}) is older than the Actual CLI in this image (${CLI_VERSION})."
        color yellow "WARNING: these backups can only be imported into Actual ${CLI_VERSION} or newer. Upgrade Actual, or use an image release whose bundled CLI is not newer than your server."
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

    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
        do
            color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}]")"

            # shellcheck disable=SC2086
            mapfile -t RCLONE_DELETE_LIST < <(rclone ${RCLONE_GLOBAL_FLAG} lsf "${RCLONE_REMOTE_X}" --min-age "${BACKUP_KEEP_DAYS}d")

            for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"
            do
                color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                # shellcheck disable=SC2086
                if ! rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"; then
                    color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                fi
            done
        done
    fi
}

########################################
# Report the result of the backup, including early exits.
########################################
function on_exit() {
    local STATUS=$?
    local NOW_TEXT
    NOW_TEXT="$(date +"%Y-%m-%d %H:%M:%S %Z")"

    if [[ ${STATUS} -eq 0 ]]; then
        send_notification success "Backup finished at ${NOW_TEXT}. ${UPLOADED_COUNT} budget(s) uploaded to ${#RCLONE_REMOTE_LIST[@]} remote(s)."
    elif [[ "${FAILED_COUNT}" -gt 0 ]]; then
        send_notification failure "Backup finished at ${NOW_TEXT} with ${FAILED_COUNT} error(s). Check the logs for details."
    else
        send_notification failure "Backup failed at ${NOW_TEXT}. Check the logs for details."
    fi
}

trap on_exit EXIT

init_env

# after init_env, so the time is in the configured TIMEZONE
color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

send_notification start "Backup started at $(date +"%Y-%m-%d %H:%M:%S %Z")."

NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"

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
