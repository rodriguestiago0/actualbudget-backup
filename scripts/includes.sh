#!/bin/bash

ENV_FILE="/.env"
CRON_CONFIG_FILE="${HOME}/crontabs"

#################### Function ####################
########################################
# Print colorful message.
# Arguments:
#     color
#     message
# Outputs:
#     colorful message
########################################
function color() {
    case $1 in
        red)     echo -e "\033[31m$2\033[0m" ;;
        green)   echo -e "\033[32m$2\033[0m" ;;
        yellow)  echo -e "\033[33m$2\033[0m" ;;
        blue)    echo -e "\033[34m$2\033[0m" ;;
        none)    echo "$2" ;;
    esac
}

########################################
# Check storage system connection success.
# Arguments:
#     None
########################################
function check_rclone_connection() {
    # check configuration exist
    rclone ${RCLONE_GLOBAL_FLAG} config show "${RCLONE_REMOTE_NAME}" > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        color red "rclone configuration information not found"
        color blue "Please configure rclone first, check https://github.com/rodriguestiago0/actualbudget-backup#configure-rclone-%EF%B8%8F-must-read-%EF%B8%8F"
        exit 1
    fi

    # check connection
    local HAS_ERROR="FALSE"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        rclone ${RCLONE_GLOBAL_FLAG} mkdir "${RCLONE_REMOTE_X}"
        if [[ $? != 0 ]]; then
            color red "storage system connection failure $(color yellow "[${RCLONE_REMOTE_X}]")"

            HAS_ERROR="TRUE"
        fi
    done

    if [[ "${HAS_ERROR}" == "TRUE" ]]; then
        exit 1
    fi
}

########################################
# Check file is exist.
# Arguments:
#     file
########################################
function check_file_exist() {
    if [[ ! -f "$1" ]]; then
        color red "cannot access $1: No such file"
        exit 1
    fi
}

########################################
# Check directory is exist.
# Arguments:
#     directory
########################################
function check_dir_exist() {
    if [[ ! -d "$1" ]]; then
        color red "cannot access $1: No such directory"
        exit 1
    fi
}

########################################
# Export variables from .env file.
# Arguments:
#     None
# Outputs:
#     variables with prefix 'DOTENV_'
# Reference:
#     https://gist.github.com/judy2k/7656bfe3b322d669ef75364a46327836#gistcomment-3632918
########################################
function export_env_file() {
    if [[ -f "${ENV_FILE}" ]]; then
        color blue "find \"${ENV_FILE}\" file and export variables"
        set -a
        source <(cat "${ENV_FILE}" | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/DOTENV_\1=\2/')
        set +a
    fi
}

########################################
# Get variables from
#     environment variables,
#     secret file in environment variables,
#     secret file in .env file,
#     environment variables in .env file.
# Arguments:
#     variable name
# Outputs:
#     variable value
########################################
function get_env() {
    local VAR="$1"
    local VAR_FILE="${VAR}_FILE"
    local VAR_DOTENV="DOTENV_${VAR}"
    local VAR_DOTENV_FILE="DOTENV_${VAR_FILE}"
    local VALUE=""

    if [[ -n "${!VAR:-}" ]]; then
        VALUE="${!VAR}"
    elif [[ -n "${!VAR_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_FILE}")"
    elif [[ -n "${!VAR_DOTENV_FILE:-}" ]]; then
        VALUE="$(cat "${!VAR_DOTENV_FILE}")"
    elif [[ -n "${!VAR_DOTENV:-}" ]]; then
        VALUE="${!VAR_DOTENV}"
    fi

    export "${VAR}=${VALUE}"
}

########################################
# Get RCLONE_REMOTE_LIST variables.
# Arguments:
#     None
# Outputs:
#     variable value
########################################
function get_rclone_remote_list() {
    # RCLONE_REMOTE_LIST
    RCLONE_REMOTE_LIST=()

    local i=0
    local RCLONE_REMOTE_NAME_X_REFER
    local RCLONE_REMOTE_DIR_X_REFER
    local RCLONE_REMOTE_X

    # for multiple
    while true; do
        RCLONE_REMOTE_NAME_X_REFER="RCLONE_REMOTE_NAME_${i}"
        RCLONE_REMOTE_DIR_X_REFER="RCLONE_REMOTE_DIR_${i}"
        get_env "${RCLONE_REMOTE_NAME_X_REFER}"
        get_env "${RCLONE_REMOTE_DIR_X_REFER}"

        if [[ -z "${!RCLONE_REMOTE_NAME_X_REFER}" || -z "${!RCLONE_REMOTE_DIR_X_REFER}" ]]; then
            break
        fi

        RCLONE_REMOTE_X=$(echo "${!RCLONE_REMOTE_NAME_X_REFER}:${!RCLONE_REMOTE_DIR_X_REFER}" | sed 's@\(/*\)$@@')
        RCLONE_REMOTE_LIST=(${RCLONE_REMOTE_LIST[@]} "${RCLONE_REMOTE_X}")

        ((i++))
    done
}

function init_actual_sync_list() {
    ACTUAL_BUDGET_SYNC_ID_LIST=()

    local i=0
    local ACTUAL_BUDGET_SYNC_ID_X_REFER

    # for multiple
    while true; do
        ACTUAL_BUDGET_SYNC_ID_X_REFER="ACTUAL_BUDGET_SYNC_ID_${i}"
        get_env "${ACTUAL_BUDGET_SYNC_ID_X_REFER}"
    
        if [[ -z "${!ACTUAL_BUDGET_SYNC_ID_X_REFER}" ]]; then        
            break
        fi
        
        ACTUAL_BUDGET_SYNC_ID_LIST=(${ACTUAL_BUDGET_SYNC_ID_LIST[@]} ${!ACTUAL_BUDGET_SYNC_ID_X_REFER})

        ((i++))
    done

    for ACTUAL_BUDGET_SYNC_ID_X in "${ACTUAL_BUDGET_SYNC_ID_LIST[@]}"
    do
        color yellow "ACTUAL_BUDGET_SYNC_ID: ${ACTUAL_BUDGET_SYNC_ID_X}"
    done
}

function init_actual_env(){
    # ACTUAL BUDGET
    get_env ACTUAL_BUDGET_URL
    ACTUAL_BUDGET_URL="${ACTUAL_BUDGET_URL:-"https://localhost:5006"}"
    color yellow "ACTUAL_BUDGET_URL: ${ACTUAL_BUDGET_URL}"

    get_env ACTUAL_BUDGET_PASSWORD
    ACTUAL_BUDGET_PASSWORD="${ACTUAL_BUDGET_PASSWORD:-""}"
    color yellow "ACTUAL_BUDGET_PASSWORD: *****"

    get_env ACTUAL_BUDGET_SYNC_ID

    if [[ -z "${ACTUAL_BUDGET_SYNC_ID}" ]]; then        
        color red "Invalid sync id"
        exit 1
    fi 
    
    ACTUAL_BUDGET_SYNC_ID_0="${ACTUAL_BUDGET_SYNC_ID}"

    init_actual_sync_list
	
	get_env ACTUAL_BUDGET_E2E_PASSWORD
	ACTUAL_BUDGET_E2E_PASSWORD_0="${ACTUAL_BUDGET_E2E_PASSWORD}"
}

########################################
# Initialization environment variables.
# Arguments:
#     None
# Outputs:
#     environment variables
########################################
function init_env() {
    # export
    export_env_file

    # CRON
    get_env CRON
    CRON="${CRON:-"0 0 * * *"}"

    # RCLONE_REMOTE_NAME
    get_env RCLONE_REMOTE_NAME
    RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-"ActualBudgetBackup"}"
    RCLONE_REMOTE_NAME_0="${RCLONE_REMOTE_NAME}"

    # RCLONE_REMOTE_DIR
    get_env RCLONE_REMOTE_DIR
    RCLONE_REMOTE_DIR="${RCLONE_REMOTE_DIR:-"/ActualBudgetBackup/"}"
    RCLONE_REMOTE_DIR_0="${RCLONE_REMOTE_DIR}"

    # get RCLONE_REMOTE_LIST
    get_rclone_remote_list

    # RCLONE_GLOBAL_FLAG
    get_env RCLONE_GLOBAL_FLAG
    RCLONE_GLOBAL_FLAG="${RCLONE_GLOBAL_FLAG:-""}"

    # BACKUP_KEEP_DAYS
    get_env BACKUP_KEEP_DAYS
    BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-"0"}"

    # BACKUP_FILE_DATE_FORMAT
    get_env BACKUP_FILE_SUFFIX
    get_env BACKUP_FILE_DATE
    get_env BACKUP_FILE_DATE_SUFFIX
    BACKUP_FILE_DATE="$(echo "${BACKUP_FILE_DATE:-"%Y%m%d"}${BACKUP_FILE_DATE_SUFFIX}" | sed 's/[^0-9a-zA-Z%_-]//g')"
    BACKUP_FILE_DATE_FORMAT="$(echo "${BACKUP_FILE_SUFFIX:-"${BACKUP_FILE_DATE}"}" | sed 's/\///g')"

    # TIMEZONE
    get_env TIMEZONE
    local TIMEZONE_MATCHED_COUNT=$(ls "/usr/share/zoneinfo/${TIMEZONE}" 2> /dev/null | wc -l)
    if [[ "${TIMEZONE_MATCHED_COUNT}" -ne 1 ]]; then
        TIMEZONE="UTC"
    fi

    init_actual_env

    color yellow "========================================"
    color yellow "CRON: ${CRON}"

    for RCLONE_REMOTE_X in "${RCLONE_REMOTE_LIST[@]}"
    do
        color yellow "RCLONE_REMOTE: ${RCLONE_REMOTE_X}"
    done

    color yellow "RCLONE_GLOBAL_FLAG: ${RCLONE_GLOBAL_FLAG}"
    color yellow "BACKUP_FILE_DATE_FORMAT: ${BACKUP_FILE_DATE_FORMAT} (example \"[filename].$(date +"${BACKUP_FILE_DATE_FORMAT}").zip\")"
    color yellow "BACKUP_KEEP_DAYS: ${BACKUP_KEEP_DAYS}"

    color yellow "TIMEZONE: ${TIMEZONE}"
    color yellow "========================================"
}
