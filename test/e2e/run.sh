#!/bin/bash
# End-to-end test of an image: seed an Actual server with the budget in
# budget.json, back it up with the image, then check that the backup holds
# the same budget as the server.
#
# Usage: test/e2e/run.sh [image]   (default: actualbudget-backup:ci)

set -euo pipefail

IMAGE="${1:-actualbudget-backup:ci}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="actualbudget-backup-e2e-$$"
SERVER_URL="http://${NAME}-server:5006"
PASSWORD='e2e-password'
# spaces, quotes and a $, to check it reaches 7z intact
ZIP_PASSWORD=' zip pa$$ "word '
WORK="$(mktemp -d)"

function cleanup() {
    docker rm -f "${NAME}-server" > /dev/null 2>&1 || true
    docker network rm "${NAME}" > /dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

function in_image() {
    docker run --rm --network "${NAME}" --user "$(id -u):$(id -g)" \
        -e ACTUAL_SERVER_URL="${SERVER_URL}" -e ACTUAL_PASSWORD="${PASSWORD}" \
        -v "${HERE}:/app/e2e:ro" -v "${WORK}:/work" \
        "$@"
}

# the server version that matches the bundled Actual CLI
CLI_VERSION="$(docker run --rm --entrypoint actual "${IMAGE}" --version)"
echo "Actual CLI ${CLI_VERSION}, starting actualbudget/actual-server:${CLI_VERSION}"

docker network create "${NAME}" > /dev/null
docker run -d --name "${NAME}-server" --network "${NAME}" "actualbudget/actual-server:${CLI_VERSION}" > /dev/null

for i in $(seq 60); do
    if in_image --entrypoint curl "${IMAGE}" -fsS -o /dev/null "${SERVER_URL}/info" 2> /dev/null; then
        break
    fi
    if [[ ${i} -eq 60 ]]; then
        echo "the Actual server did not start"
        docker logs "${NAME}-server"
        exit 1
    fi
    sleep 1
done

in_image --entrypoint curl "${IMAGE}" -fsS -o /dev/null -H 'Content-Type: application/json' \
    -d "{\"password\":\"${PASSWORD}\"}" "${SERVER_URL}/account/bootstrap"

echo "seeding the test budget"
in_image --entrypoint node "${IMAGE}" /app/e2e/e2e.mjs seed /app/e2e/budget.json /work/sync-id > /dev/null
SYNC_ID="$(cat "${WORK}/sync-id")"

echo "backing up ${SYNC_ID}"
mkdir "${WORK}/remote"
in_image \
    -e ACTUAL_BUDGET_URL="${SERVER_URL}" \
    -e ACTUAL_BUDGET_PASSWORD="${PASSWORD}" \
    -e ACTUAL_BUDGET_SYNC_ID="${SYNC_ID}" \
    -e ZIP_PASSWORD="${ZIP_PASSWORD}" \
    -e RCLONE_CONFIG_E2E_TYPE=local \
    -e RCLONE_REMOTE_NAME=e2e \
    -e RCLONE_REMOTE_DIR=/work/remote \
    "${IMAGE}" backup

BACKUPS=("${WORK}/remote/backup.${SYNC_ID}."*.zip)
if [[ ${#BACKUPS[@]} -ne 1 || ! -f "${BACKUPS[0]}" ]]; then
    echo "expected one backup in the remote, found: $(ls "${WORK}/remote")"
    exit 1
fi
BACKUP="/work/remote/$(basename "${BACKUPS[0]}")"

if ! in_image --entrypoint 7z "${IMAGE}" l -slt -p"${ZIP_PASSWORD}" "${BACKUP}" | grep -q '^Method = AES-256'; then
    echo "the backup is not encrypted with AES-256"
    exit 1
fi
in_image --entrypoint 7z "${IMAGE}" x -bso0 -p"${ZIP_PASSWORD}" -o/work/unpacked "${BACKUP}"

echo "comparing the backup with the server"
in_image --entrypoint node "${IMAGE}" /app/e2e/e2e.mjs snapshot-server "${SYNC_ID}" /work/server.json > /dev/null
in_image --entrypoint node "${IMAGE}" /app/e2e/e2e.mjs snapshot-backup /work/unpacked /work/backup.json > /dev/null
in_image --entrypoint node "${IMAGE}" /app/e2e/e2e.mjs compare /app/e2e/budget.json /work/server.json /work/backup.json
