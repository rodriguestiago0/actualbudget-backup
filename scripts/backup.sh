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

function download_actual_budget() {
    color blue "Downloading Actual Budget backup"
    color green "Login into Actual Budget" 
    prepare_login_json
    TOKEN="$(curl -s --location "${ACTUAL_BUDGET_URL}/account/login" --header 'Content-Type: application/json' --data @/tmp/login.json  | jq --raw-output '.data.token')"
    rm /tmp/login.json
    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        color green "Get file id for ${ACTUAL_BUDGET_SYNC_ID_X}"
        backup_file_name $ACTUAL_BUDGET_SYNC_ID_X

        #Explicit exports in this file are needed for visibility from python
        export FILE_ID=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/list-user-files" \--header "X-ACTUAL-TOKEN: $TOKEN" | jq --raw-output ".data[] | select( [ .groupId | match(\"$ACTUAL_BUDGET_SYNC_ID_X\") ] | any) | .fileId")
        color green "Downloading backup files"
        curl -s --location "${ACTUAL_BUDGET_URL}/sync/download-user-file" --header "X-ACTUAL-TOKEN: $TOKEN" --header "X-ACTUAL-FILE-ID: $FILE_ID" --output "${BACKUP_FILE_ZIP}"
        ENCRYPT_KEY_ID=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/list-user-files" \--header "X-ACTUAL-TOKEN: $TOKEN" | jq --raw-output ".data[] | select( [ .groupId | match(\"$ACTUAL_BUDGET_SYNC_ID_X\") ] | any) | .encryptKeyId")
		color blue "[DEBUG] ENCRYPT_KEY_ID: ${ENCRYPT_KEY_ID}"
        if [ "$ENCRYPT_KEY_ID" != "null" ]; then
            decrypt
        fi
    done
   
}

function decrypt() {
    color blue "File ${BACKUP_FILE_ZIP} is encrypted. Decrypting data..."
    
    #FILE_ID and ENCRYPT_KEY_ID are still set to the current file so they can be used here
    #TOKEN is cross function
    color yellow "[DEBUG]Attempting to get SALT"
    local JSON=$(jq -n --arg token "$TOKEN" --arg fileId "$FILE_ID" \
  '{token: $token, fileId: $fileId}')
    export SALT=$(curl "${ACTUAL_BUDGET_URL}/sync/user-get-key" -X POST -H "Content-Type: application/json" --data-raw "$JSON" | jq --raw-output ".data.salt")
    color yellow "[DEBUG] Attempting to get IV"
    export IV=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/get-user-file-info" \--header "X-ACTUAL-TOKEN: $TOKEN" \--header "X-ACTUAL-FILE-ID: $FILE_ID" | jq --raw-output ".data.encryptMeta.iv")
    color yellow "[DEBUG] Attempting to get Auth_Tag"
    export AUTH_TAG=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/get-user-file-info" \--header "X-ACTUAL-TOKEN: $TOKEN" \--header "X-ACTUAL-FILE-ID: $FILE_ID" | jq --raw-output ".data.encryptMeta.authTag")
	export E2E_PASS_ARG="${ACTUAL_BUDGET_E2E_PASSWORD}"
	export BACKUP_FILE_ZIP_ARG="${BACKUP_FILE_ZIP}"
    color blue "[DEBUG] Required variables have the following values:\n"
    color blue "SALT: ${SALT}"
    color blue "IV: ${IV}"
    color blue "AUTH_TAG: ${AUTH_TAG}"
    color yellow "E2E_PASSWORD_0: ${ACTUAL_BUDGET_E2E_PASSWORD_0}"
	color yellow "E2E_PASSWORD: ${ACTUAL_BUDGET_E2E_PASSWORD}"
    #aes-256-gcm-decrypt.py requires SALT, IV, and AUTH_TAG exported above in addition to user set ACTUAL_BUDGET_E2E_PASSWORD_X
    if ! python3 /app/aes-256-gcm-decrypt.py; then
        color red "Decryption failed. Encrypted backup ${BACKUP_FILE_ZIP} will be unusable. Check python error statement above for details"
    fi
    #We can delete the original encrypted file and rename the decrypted file so upload works as expected
    rm "${BACKUP_FILE_ZIP}"
    local DECRYPT_FILE_ZIP="${BACKUP_FILE_ZIP:0:-4}-decrypted.zip"
    mv "${DECRYPT_FILE_ZIP}" "${BACKUP_FILE_ZIP}"
}

function backup() {
    mkdir -p "backup"

    download_actual_budget

    ls -lah "backup"
}


function upload() {
    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        backup_file_name $ACTUAL_BUDGET_SYNC_ID_X
        if !(file "${BACKUP_FILE_ZIP}" | grep -q "Zip archive data" ) ; then
            color red "File not found \"${BACKUP_FILE_ZIP}\""

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


DECRYPT=0

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
