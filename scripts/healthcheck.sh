#!/bin/bash
# Docker health check: unhealthy while the last backup failed, or when no
# backup succeeded in the last HEALTHCHECK_MAX_HOURS, counted from the
# container start at the earliest. `docker inspect` shows the message.

# shellcheck source=scripts/includes.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/includes.sh"

LAST_SUCCESS=0
START=""
MAX_HOURS=0

if [[ -f "${HEALTH_FILE}" ]]; then
    START="$(sed -n 's/^start=//p' "${HEALTH_FILE}")"
    MAX_HOURS="$(sed -n 's/^max_hours=//p' "${HEALTH_FILE}")"
fi

if [[ -f "${LAST_BACKUP_FILE}" ]]; then
    head -n 1 "${LAST_BACKUP_FILE}"
    [[ "$(head -c 3 "${LAST_BACKUP_FILE}")" == "ok:" ]] || exit 1
    LAST_SUCCESS="$(sed -n 's/^last_success=//p' "${LAST_BACKUP_FILE}")"
else
    echo "no backup has run yet"
fi

if [[ "${MAX_HOURS:-0}" -gt 0 && -n "${START}" ]]; then
    SINCE=$(( ${LAST_SUCCESS:-0} > START ? ${LAST_SUCCESS:-0} : START ))
    if (( $(date +%s) - SINCE > MAX_HOURS * 3600 )); then
        echo "no successful backup in the last ${MAX_HOURS} hours (HEALTHCHECK_MAX_HOURS), check the logs and CRON"
        exit 1
    fi
fi
