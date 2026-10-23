#!/bin/bash

# shellcheck source=scripts/includes.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/includes.sh"

########################################
# When started as root with PUID or PGID, give /config to that user and
# group, then run this script again as them.
########################################
function switch_user() {
    if [[ "$(id -u)" -ne 0 ]]; then
        return
    fi

    export_env_file > /dev/null
    get_env PUID
    get_env PGID

    if [[ -z "${PUID}" && -z "${PGID}" ]]; then
        return
    fi

    local RUN_UID="${PUID:-0}"
    # with only PUID set, use the same number for the group rather than root's
    local RUN_GID="${PGID:-${PUID:-0}}"

    if [[ ! "${RUN_UID}" =~ ^[0-9]+$ || ! "${RUN_GID}" =~ ^[0-9]+$ ]]; then
        color red "PUID and PGID must be numbers, e.g. PUID=1000 and PGID=1000"
        exit 1
    fi

    # only what isn't theirs yet, so a restart doesn't walk all of /config
    mkdir -p /config
    if ! find /config \( ! -user "${RUN_UID}" -o ! -group "${RUN_GID}" \) -exec chown "${RUN_UID}:${RUN_GID}" {} +; then
        color yellow "could not give /config to ${RUN_UID}:${RUN_GID}, rclone may not be able to save its config"
    fi

    color blue "running as ${RUN_UID}:${RUN_GID}"
    # su-exec sets HOME to / for a user the image does not know
    exec su-exec "${RUN_UID}:${RUN_GID}" env HOME="${HOME}" "$0" "$@"
}

switch_user "$@"

# rclone and shoutrrr commands
if [[ "$1" == "rclone" || "$1" == "shoutrrr" ]]; then
    exec "$@"
fi

function configure_timezone() {
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${LOCALTIME_FILE}"
}

function configure_cron() {
    # rewritten on every start, so a changed CRON applies after a restart
    echo "${CRON} bash /app/backup.sh" > "${CRON_CONFIG_FILE}"
}

function configure_healthcheck() {
    printf 'start=%s\nmax_hours=%s\n' "$(date +%s)" "${HEALTHCHECK_MAX_HOURS}" > "${HEALTH_FILE}"
}

init_env
# a remote that is down now may be back by the backup, which reports it
check_rclone_connection warn
configure_timezone
configure_cron

# backup manually
if [[ "$1" == "backup" ]]; then
    color yellow "Manually triggering a backup will only execute the backup script once, and the container will exit upon completion."

    exec bash "/app/backup.sh"
fi

configure_healthcheck

# foreground run crond
exec /usr/bin/supercronic -passthrough-logs -quiet "${CRON_CONFIG_FILE}"
