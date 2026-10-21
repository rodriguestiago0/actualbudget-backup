#!/bin/bash

# shellcheck source=scripts/includes.sh
. /app/includes.sh

# rclone and shoutrrr commands
if [[ "$1" == "rclone" || "$1" == "shoutrrr" ]]; then
    exec "$@"
fi

function configure_timezone() {
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${LOCALTIME_FILE}"
}

function configure_cron() {
    if ! grep -q 'backup.sh' "${CRON_CONFIG_FILE}" 2> /dev/null; then
        echo "${CRON} bash /app/backup.sh" >> "${CRON_CONFIG_FILE}"
    fi
}

init_env
check_rclone_connection all
configure_timezone
configure_cron

# backup manually
if [[ "$1" == "backup" ]]; then
    color yellow "Manually triggering a backup will only execute the backup script once, and the container will exit upon completion."

    exec bash "/app/backup.sh"
fi

# foreground run crond
exec /usr/bin/supercronic -passthrough-logs -quiet "${CRON_CONFIG_FILE}"
