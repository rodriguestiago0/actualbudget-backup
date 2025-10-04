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
    #We will use $TOKEN in decrypt step
	TOKEN="$(curl -s --location "${ACTUAL_BUDGET_URL}/account/login" --header 'Content-Type: application/json' --data @/tmp/login.json  | jq --raw-output '.data.token')"
    rm /tmp/login.json
    local i=0
	for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        color green "Get file id for ${ACTUAL_BUDGET_SYNC_ID_X}"
        backup_file_name $ACTUAL_BUDGET_SYNC_ID_X

        #We will use $FILE_ID in decrypt step
		FILE_ID=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/list-user-files" \--header "X-ACTUAL-TOKEN: $TOKEN" | jq --raw-output ".data[] | select( [ .groupId | match(\"$ACTUAL_BUDGET_SYNC_ID_X\") ] | any) | .fileId")
        color green "Downloading backup files"
        curl -s --location "${ACTUAL_BUDGET_URL}/sync/download-user-file" --header "X-ACTUAL-TOKEN: $TOKEN" --header "X-ACTUAL-FILE-ID: $FILE_ID" --output "${BACKUP_FILE_ZIP}"
        ENCRYPT_KEY_ID=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/list-user-files" \--header "X-ACTUAL-TOKEN: $TOKEN" | jq --raw-output ".data[] | select( [ .groupId | match(\"$ACTUAL_BUDGET_SYNC_ID_X\") ] | any) | .encryptKeyId")
        if [ "$ENCRYPT_KEY_ID" != "null" ]; then
            color blue "File ${BACKUP_FILE_ZIP} is encrypted with Encryption ID: ${ENCRYPT_KEY_ID}. Decrypting data..."
			BACKUP_FILE_BIN="${BACKUP_FILE_ZIP:0:-4}.bin"
			cp "${BACKUP_FILE_ZIP}" "${BACKUP_FILE_BIN}"
			decrypt "${i}"
		else
		    color blue "File ${BACKUP_FILE_ZIP} is NOT encrypted. Backing up normally..."
        fi
        ((i++))
    done
   
}

function decrypt() {
	#$FILE_ID and $TOKEN are still set properly so they can be used here
    local JSON=$(jq -n --arg token "$TOKEN" --arg fileId "$FILE_ID" \
  '{token: $token, fileId: $fileId}')
    local SALT=$(curl "${ACTUAL_BUDGET_URL}/sync/user-get-key" -X POST -H "Content-Type: application/json" --data-raw "$JSON" | jq --raw-output ".data.salt")
    local IV=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/get-user-file-info" \--header "X-ACTUAL-TOKEN: $TOKEN" \--header "X-ACTUAL-FILE-ID: $FILE_ID" | jq --raw-output ".data.encryptMeta.iv")
    local AUTH_TAG=$(curl -s --location "${ACTUAL_BUDGET_URL}/sync/get-user-file-info" \--header "X-ACTUAL-TOKEN: $TOKEN" \--header "X-ACTUAL-FILE-ID: $FILE_ID" | jq --raw-output ".data.encryptMeta.authTag")

    #Set the password index to match X from ACTUAL_BUDGET_SYNC_ID_X
	#This will fail if not user defined
	local E2E_PASSWORD_X="${ACTUAL_BUDGET_E2E_PASSWORD_LIST[$1]}"

    local DECRYPT_FILE_ZIP="${BACKUP_FILE_ZIP:0:-4}-decrypted.zip"
	
	#aes-256-gcm-decrypt.py requires SALT, IV, and AUTH_TAG retrieved above in addition to user set ACTUAL_BUDGET_E2E_PASSWORD_X
	if ! python3 /app/aes-256-gcm-decrypt.py \
	    "--salt=${SALT}" \
		"--password=${E2E_PASSWORD_X}" \
		"--iv=${IV}" \
		"--authtag=${AUTH_TAG}" \
		"--input=${BACKUP_FILE_ZIP}" \
		"--output=${DECRYPT_FILE_ZIP}"; then
        #Unusable backup is kept as .bin in case of failure as you can still manually decrypt it given the same server state. Better to have it than not.
		color red "Decryption failed. Encrypted backup ${BACKUP_FILE_ZIP} is unusable. Check python error statement above for details"
	else
	    color blue "Decryption successful. Backing up ${BACKUP_FILE_ZIP}..."
		#Rename successfully decrypted backup file
        mv "${DECRYPT_FILE_ZIP}" "${BACKUP_FILE_ZIP}"
    fi
	#Delete the redundant .bin file
	rm "${BACKUP_FILE_BIN}"

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
			color red "This may be a file which failed to properly decrypt and will not be backed up"
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
