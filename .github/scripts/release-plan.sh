#!/bin/bash
# Plans the next release from the first-parent commits since the last tag.
#
# A commit is released when it changes the image. Markers in its message
# (the PR title, for merge and squash merges) change that:
#   [skip release]   not released on its own
#   [minor]/[major]  bump that part instead of the patch version
#
# Usage: release-plan.sh
# Prints, as key=value lines (for $GITHUB_OUTPUT):
#   image=true      some commit since the last tag changes the image
#   release=true    something is to be released
#   bump=patch|minor|major
#   latest_tag=v1.2.3

set -euo pipefail

IMAGE_PATHS='^(Dockerfile|\.dockerignore|package(-lock)?\.json|scripts/)'
RELEASE_PATHS="${IMAGE_PATHS}"

LATEST_TAG="$(git describe --tags --abbrev=0 2> /dev/null || echo "v0.0.0")"
RANGE="${LATEST_TAG}..HEAD"
if [[ "${LATEST_TAG}" == "v0.0.0" ]]; then
    RANGE="HEAD"
fi
echo "Latest tag: ${LATEST_TAG}" >&2

IMAGE=false
RELEASE=false
BUMP="patch"

for COMMIT in $(git rev-list --first-parent "${RANGE}"); do
    MSG="$(git log -1 --format=%B "${COMMIT}")"
    SUBJECT="$(git log -1 --format=%s "${COMMIT}")"
    FILES="$(git diff --name-only "${COMMIT}^1" "${COMMIT}" 2> /dev/null || git show --name-only --format= "${COMMIT}")"

    if grep -qE "${IMAGE_PATHS}" <<< "${FILES}"; then
        IMAGE=true
    fi
    if grep -q '\[skip release\]' <<< "${MSG}"; then
        echo "Skipped ([skip release]): ${SUBJECT}" >&2
        continue
    fi
    if ! grep -qE "${RELEASE_PATHS}" <<< "${FILES}"; then
        echo "Skipped (image unchanged): ${SUBJECT}" >&2
        continue
    fi

    echo "Included: ${SUBJECT}" >&2
    RELEASE=true
    if grep -q '\[major\]' <<< "${MSG}"; then
        BUMP="major"
    elif [[ "${BUMP}" != major ]] && grep -q '\[minor\]' <<< "${MSG}"; then
        BUMP="minor"
    fi
done

echo "image=${IMAGE}"
echo "release=${RELEASE}"
echo "bump=${BUMP}"
echo "latest_tag=${LATEST_TAG}"
