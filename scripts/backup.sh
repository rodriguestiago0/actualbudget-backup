#!/bin/bash

. /app/includes.sh

function clear_dir() {
    rm -rf backup
}

function backup_file_name () {
    # backup zip file
    BACKUP_FILE_ZIP="backup/backup.$1.${NOW}.zip"
    color blue "file name \"${BACKUP_FILE_ZIP}\""
}

function prepare_login_json() {
    (printf '%s\0%s\0' "loginMethod" "password" && printf '%s\0%s\0' "password" "${ACTUAL_BUDGET_PASSWORD}") | jq -Rs 'split("\u0000") | . as $a 
                  | reduce range(0; 2) as $i 
                  ({}; . + {($a[2*$i]): ($a[2*$i + 1])})' > /tmp/login.json
}

# ==========================================================
# 🧩 NEW download_actual_budget() using @actual-app/api
# ==========================================================
function download_actual_budget() {
    color blue "Downloading Actual Budget backup using @actual-app/api"

    # Parameters:
    API_VERSION=${ACTUAL_API_VERSION:-latest}
    API_DOWNLOAD_PATH=${ACTUAL_API_DOWNLOAD_PATH:-/tmp/actual-download}

    # Clean and prepare folders
    mkdir -p "${API_DOWNLOAD_PATH}"
    mkdir -p "backup"

    color green "Installing @actual-app/api@$API_VERSION (if needed)..."
    if ! [ -d "/app/node_modules/@actual-app/api" ]; then
        echo "Installing @actual-app/api@$API_VERSION..."
        npm install --prefix /app "@actual-app/api@$API_VERSION" --unsafe-perm
    else
        color green "@actual-app/api@$API_VERSION already installed."
    fi

    # Convert arrays to comma-separated strings
    SYNC_IDS="$(IFS=, ; echo "${ACTUAL_BUDGET_SYNC_ID_LIST[*]}")"
    E2E_PASSWORDS="$(IFS=, ; echo "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[*]}")"

    export NODE_PATH=/app/node_modules

    # Run Node with arguments instead of relying on environment variable export
    node "/app/download-actual-budget.js" \
        --syncIds="$SYNC_IDS" \
        --e2ePasswords="$E2E_PASSWORDS" \
        --dataDir="$API_DOWNLOAD_PATH" \
        --destDir="$(pwd)/backup" \
        --serverURL="$ACTUAL_BUDGET_URL" \
        --password="$ACTUAL_BUDGET_PASSWORD" \
        --now="$NOW"
}

# ==========================================================

function backup() {
    mkdir -p "backup"

    download_actual_budget

    ls -lah "backup"
}


function upload() {
    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        backup_file_name $ACTUAL_BUDGET_SYNC_ID_X
		if !(file "${BACKUP_FILE_ZIP}" | grep -q "data" ) ; then
            color red "File not found \"${BACKUP_FILE_ZIP}\""
			color red "Nothing has been backed up!"
            exit 1
        fi
    done
    
    # upload
    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
        do
            backup_file_name $ACTUAL_BUDGET_SYNC_ID_X
            color blue "upload backup file to storage system $(color yellow "[${BACKUP_FILE_ZIP} -> ${RCLONE_REMOTE_X}]")"

            rclone ${RCLONE_GLOBAL_FLAG} copy "${BACKUP_FILE_ZIP}" "${RCLONE_REMOTE_X}"
            if [[ $? != 0 ]]; then
                color red "upload failed"
            fi
        done
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

NOW="$(date +"${BACKUP_FILE_DATE_FORMAT}")"

check_rclone_connection

clear_dir
backup
upload
clear_dir
clear_history
color none ""
