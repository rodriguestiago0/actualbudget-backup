# syntax=docker/dockerfile:1

FROM rclone/rclone:sha-9ee9d0a AS base
# FROM rclone/rclone:1.75.0 AS base

# Install the Actual CLI (pinned in package-lock.json). Build tools are only
# needed here, for platforms without a prebuilt better-sqlite3 binary.
FROM base AS cli

RUN apk add --no-cache nodejs npm python3 make g++

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
  && npm cache clean --force \
  && node_modules/.bin/actual --version

FROM base

LABEL org.opencontainers.image.source="https://github.com/rodriguestiago0/actualbudget-backup" \
  org.opencontainers.image.url="https://github.com/rodriguestiago0/actualbudget-backup" \
  org.opencontainers.image.description="Back up Actual Budget to any rclone remote" \
  org.opencontainers.image.licenses="MIT"

ARG USER_NAME="backuptool"
ARG USER_ID="1100"

ENV LOCALTIME_FILE="/tmp/localtime" \
  PATH="/app/node_modules/.bin:${PATH}"

RUN apk add --no-cache bash grep supercronic 7zip nodejs tzdata \
  && ln -sf "${LOCALTIME_FILE}" /etc/localtime \
  && addgroup -g "${USER_ID}" "${USER_NAME}" \
  && adduser -u "${USER_ID}" -Ds /bin/sh -G "${USER_NAME}" "${USER_NAME}"

COPY --from=cli /app/node_modules /app/node_modules
COPY --chmod=755 scripts/*.sh /app/

ENTRYPOINT ["/app/entrypoint.sh"]
