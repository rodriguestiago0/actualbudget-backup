#!/bin/bash
# Docker health check: healthy until a backup fails, then unhealthy until
# the next one succeeds. `docker inspect` shows the message.

# shellcheck source=scripts/includes.sh
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/includes.sh"

if [[ ! -f "${LAST_BACKUP_FILE}" ]]; then
    echo "no backup has run yet"
    exit 0
fi

cat "${LAST_BACKUP_FILE}"
[[ "$(head -c 3 "${LAST_BACKUP_FILE}")" == "ok:" ]]
