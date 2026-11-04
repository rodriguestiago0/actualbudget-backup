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

case "${1:-}" in
    "") ;;                           # the schedule
    backup) ;;                       # one backup, below
    rclone|shoutrrr) exec "$@" ;;
    *)
        color red "unknown command \"$1\": use backup, rclone or shoutrrr, or nothing to run the schedule"
        exit 2
        ;;
esac

function configure_timezone() {
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${LOCALTIME_FILE}"
}

function configure_cron() {
    # rewritten on every start, so a changed CRON applies after a restart
    echo "${CRON} bash /app/backup.sh" > "${CRON_CONFIG_FILE}"
}

########################################
# Remove the work folders of backups that were killed before they could
# clean up, as they can hold a decrypted budget. Nothing runs yet.
########################################
function clear_stale_work_dirs() {
    find "${TMPDIR:-/tmp}" -mindepth 1 -maxdepth 1 -type d -name 'tmp.*' -user "$(id -u)" \
        -exec rm -rf {} + 2> /dev/null
}

function configure_healthcheck() {
    printf 'start=%s\nmax_hours=%s\n' "$(date +%s)" "${HEALTHCHECK_MAX_HOURS}" > "${HEALTH_FILE}"
}

init_env
# a remote that is down now may be back by the backup, which reports it
check_rclone_connection warn
configure_timezone
configure_cron

########################################
# Pass a stop signal on to every running backup, then to the child.
# Supercronic doesn't forward signals to its jobs, and each job runs in its
# own process group, so the whole group is signalled: that also stops the
# actual or rclone command a backup is waiting on.
########################################
# shellcheck disable=SC2317,SC2329 # called by the trap below
function forward_stop() {
    local PID
    for PID in $(pgrep -f '^bash /app/backup.sh'); do
        kill -TERM -- "-${PID}" 2> /dev/null
    done
    kill -TERM "${CHILD}" 2> /dev/null
}

trap forward_stop TERM INT

# backup manually
if [[ "$1" == "backup" ]]; then
    color yellow "Manually triggering a backup will only execute the backup script once, and the container will exit upon completion."

    # in its own process group, like a supercronic job
    setsid bash /app/backup.sh &
else
    clear_stale_work_dirs
    configure_healthcheck

    /usr/bin/supercronic -passthrough-logs -quiet "${CRON_CONFIG_FILE}" &
fi
CHILD=$!

# a trapped signal ends wait early, so wait again until the child has exited
wait "${CHILD}"
STATUS=$?
while kill -0 "${CHILD}" 2> /dev/null; do
    wait "${CHILD}"
    STATUS=$?
done
exit "${STATUS}"
