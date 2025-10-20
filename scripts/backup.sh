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

    # Prepare Node script
    NODE_SCRIPT=$(mktemp)

cat > "$NODE_SCRIPT" <<'EOF'
const api = require('@actual-app/api');
const path = require('path');
const { execSync } = require('child_process');
const argv = require('minimist')(process.argv.slice(2));

// Parse arguments using minimist
const dataDir = argv.dataDir || '/tmp/actual-download';
const destDir = argv.destDir || '/data/backup';
const serverURL = argv.serverURL || 'http://localhost:5006';
const password = argv.password || 'password';
const syncIdList = (argv.syncIds || '').split(',');
const e2ePasswords = (argv.e2ePasswords || '').split(',');
const now = argv.now || 'now';

console.log("📥 Starting download from", serverURL);
console.log("🗂 Sync IDs:", syncIdList);

(async () => {
    for (let i = 0; i < syncIdList.length; i++) {
        const syncId = syncIdList[i];
        if (!syncId) continue;

        const e2ePassword = e2ePasswords[i] || null;
        const zipPath = path.join(destDir, `backup.${syncId}.${now}.zip`);

        console.log(`⬇️  Downloading budget ${syncId} -> ${zipPath}`);

        await api.init({ dataDir, serverURL, password });

        try {
            await api.downloadBudget(syncId, e2ePassword ? { password: e2ePassword } : {});
            console.log(`✅ Budget ${syncId} downloaded successfully.`);
            await api.getAccounts();
            await api.shutdown();

            // Zip the downloaded data
            execSync(`cd ${dataDir} && zip -r ${zipPath} .`, { stdio: 'inherit' });
            console.log(`📦 Created zip: ${zipPath}`);
        } catch (err) {
            console.error(`❌ Failed to download ${syncId}:`, err);
        } finally {
            await api.shutdown();
        }
    }

    console.log("🎉 All downloads completed!");
})();
EOF

    # Convert arrays to comma-separated strings
    SYNC_IDS="$(IFS=, ; echo "${ACTUAL_BUDGET_SYNC_ID_LIST[*]}")"
    E2E_PASSWORDS="$(IFS=, ; echo "${ACTUAL_BUDGET_E2E_PASSWORD_LIST[*]}")"

    export NODE_PATH=/app/node_modules

    # Run Node with arguments instead of relying on environment variable export
    node "$NODE_SCRIPT" \
        --syncIds="$SYNC_IDS" \
        --e2ePasswords="$E2E_PASSWORDS" \
        --dataDir="$API_DOWNLOAD_PATH" \
        --destDir="$(pwd)/backup" \
        --serverURL="$ACTUAL_BUDGET_URL" \
        --password="$ACTUAL_BUDGET_PASSWORD" \
        --now="$NOW"
    rm -f "$NODE_SCRIPT"
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
		if !(file "${BACKUP_FILE_ZIP}" | grep -q "Zip archive data" ) ; then
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
