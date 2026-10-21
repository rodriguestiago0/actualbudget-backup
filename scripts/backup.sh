#!/bin/bash

# shellcheck source=scripts/includes.sh
. /app/includes.sh

BACKUP_DIR="backup"
FAILED_COUNT=0

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

color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

init_env

NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"

check_rclone_connection any

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
