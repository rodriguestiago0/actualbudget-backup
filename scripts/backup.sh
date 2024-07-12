#!/bin/bash

. /app/includes.sh

function clear_dir() {
    rm -rf backup
}

function backup_init() {
    NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"
    # backup zip file
    BACKUP_FILE_ZIP="backup/backup.${NOW}.zip"
}

function download_actual_budget() {
    color blue "Downloading Actual Budger backup"
    color green "Login into Actual Budger"
    local TOKEN="$(curl --location "${ACTUAL_BUDGET_URL}/account/login" --header 'Content-Type: application/json' --data-raw "{\"loginMethod\": \"password\",\"password\": \"${ACTUAL_BUDGET_PASSWORD}\"}"  | jq --raw-output '.data.token'
)"

    color green "Get file id"
    local FILE_ID=$(curl --location "${ACTUAL_BUDGET_URL}/sync/list-user-files" \--header "X-ACTUAL-TOKEN: $TOKEN" | jq --raw-output ".data[] | select( [ .groupId | match(\"$ACTUAL_BUDGET_SYNC_ID\") ] | any) | .fileId")

    color green "Downloading backup files"
    curl --location "${ACTUAL_BUDGET_URL}/sync/download-user-file" --header "X-ACTUAL-TOKEN: $TOKEN" --header "X-ACTUAL-FILE-ID: $FILE_ID" --output "${BACKUP_FILE_ZIP}"
}

function backup() {
    mkdir -p "backup"

    download_actual_budget

    ls -lah "backup"
}


function upload() {
    if !(file "${BACKUP_FILE_ZIP}" | grep -q "Zip archive data" ) ; then
        color red "Error downloading file"

        exit 1
    fi


    # upload
    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color blue "upload backup file to storage system $(color yellow "[${BACKUP_FILE_ZIP} -> ${RCLONE_REMOTE_X}]")"

        rclone ${RCLONE_GLOBAL_FLAG} copy "${BACKUP_FILE_ZIP}" "${RCLONE_REMOTE_X}"
        if [[ $? != 0 ]]; then
            color red "upload failed"
        fi
    done

}

function clear_history() {
    if [[ "${BACKUP_KEEP_DAYS}" -gt 0 ]]; then
        for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
        do
            color blue "delete ${BACKUP_KEEP_DAYS} days ago backup files $(color yellow "[${RCLONE_REMOTE_X}]")"

            mapfile -t RCLONE_DELETE_LIST < <(rclone ${RCLONE_GLOBAL_FLAG} lsf "${RCLONE_REMOTE_X}" --min-age "${BACKUP_KEEP_DAYS}d")

            for RCLONE_DELETE_FILE in "${RCLONE_DELETE_LIST[@]}"
            do
                color yellow "deleting \"${RCLONE_DELETE_FILE}\""

                rclone ${RCLONE_GLOBAL_FLAG} delete "${RCLONE_REMOTE_X}/${RCLONE_DELETE_FILE}"
                if [[ $? != 0 ]]; then
                    color red "delete \"${RCLONE_DELETE_FILE}\" failed"
                fi
            done
        done
    fi
}

color blue "running the backup program at $(date +"%Y-%m-%d %H:%M:%S %Z")"

init_env

check_rclone_connection
#
clear_dir
backup_init
backup
upload
clear_dir
clear_history
color none ""
