# syntax=docker/dockerfile:1

FROM rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS base

# Install the Actual CLI (pinned in package-lock.json). Build tools are only
# needed here, for platforms without a prebuilt better-sqlite3 binary.
FROM base AS cli

RUN apk add --no-cache nodejs npm python3 make g++

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
  && npm cache clean --force \
  && node_modules/.bin/actual --version

# Shoutrrr CLI for notifications (https://github.com/nicholas-fedor/shoutrrr).
# Runs on the build platform; it only downloads and verifies the binary.
FROM --platform=$BUILDPLATFORM rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS shoutrrr

ARG SHOUTRRR_VERSION="0.22.0"
ARG TARGETARCH

RUN case "${TARGETARCH}" in \
      amd64) ARCH="amd64" ;; \
      arm64) ARCH="arm64v8" ;; \
      arm)   ARCH="armhf" ;; \
      *)     echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
  && FILE="shoutrrr_linux_${ARCH}_${SHOUTRRR_VERSION}.tar.gz" \
  && URL="https://github.com/nicholas-fedor/shoutrrr/releases/download/v${SHOUTRRR_VERSION}" \
  && cd /tmp \
  && wget -q "${URL}/${FILE}" "${URL}/checksums.txt" \
  && grep " ${FILE}\$" checksums.txt | sha256sum -c - \
  && tar xzf "${FILE}" shoutrrr \
  && mv shoutrrr /usr/local/bin/shoutrrr

FROM base

LABEL org.opencontainers.image.source="https://github.com/rodriguestiago0/actualbudget-backup" \
  org.opencontainers.image.url="https://github.com/rodriguestiago0/actualbudget-backup" \
  org.opencontainers.image.description="Back up Actual Budget to any rclone remote" \
  org.opencontainers.image.licenses="MIT"

# HOME in /tmp, so the backup can also run as PUID/PGID or `user:`
ENV LOCALTIME_FILE="/tmp/localtime" \
  HOME="/tmp" \
  PATH="/app/node_modules/.bin:${PATH}"

RUN apk add --no-cache bash grep supercronic 7zip nodejs tzdata curl su-exec \
  && ln -sf "${LOCALTIME_FILE}" /etc/localtime

COPY --from=cli /app/node_modules /app/node_modules
COPY --from=shoutrrr /usr/local/bin/shoutrrr /usr/local/bin/shoutrrr
COPY --chmod=755 scripts/*.sh /app/

# unhealthy while the last backup failed or one is overdue, see
# scripts/healthcheck.sh
HEALTHCHECK --interval=5m --timeout=10s CMD ["/app/healthcheck.sh"]

ENTRYPOINT ["/app/entrypoint.sh"]
