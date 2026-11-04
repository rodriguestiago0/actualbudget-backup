# syntax=docker/dockerfile:1

FROM rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS base

# better-sqlite3 is the only native module, and it has no prebuilt binary for
# 32-bit ARM, where compiling it under QEMU takes about half an hour. Its
# version is read from the lockfile on its own, so the sqlite stage below is
# rebuilt only when that version changes, not on every lockfile change.
FROM --platform=$BUILDPLATFORM base AS sqlite-version

RUN apk add --no-cache jq
COPY package-lock.json /tmp/
# The cli stage installs with --ignore-scripts, so fail if another package
# ever needs an install script
RUN jq -e '[.packages[] | select(.hasInstallScript)] == []' /tmp/package-lock.json > /dev/null \
  && jq -er '.packages["node_modules/better-sqlite3"].version' /tmp/package-lock.json > /better-sqlite3.version

FROM base AS sqlite

RUN apk add --no-cache nodejs npm python3 make g++

WORKDIR /build
COPY --from=sqlite-version /better-sqlite3.version ./
# Compiles only where the package has no prebuild (binding.js prints 0)
RUN mkdir /out \
  && npm install --no-save --no-package-lock --no-audit --no-fund --ignore-scripts \
       "better-sqlite3@$(cat better-sqlite3.version)" \
  && cd node_modules/better-sqlite3 \
  && if [ "$(node lib/binding.js)" = 0 ]; then \
       npm run build-release && cp build/Release/better_sqlite3.node /out/; \
     fi

# Install the Actual CLI (pinned in package-lock.json)
FROM base AS cli

RUN apk add --no-cache nodejs npm

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund \
  && npm cache clean --force
# better-sqlite3 falls back to build/Release/ when it has no prebuild
COPY --from=sqlite /out/ /app/node_modules/better-sqlite3/build/Release/

# Shoutrrr CLI for notifications (https://github.com/nicholas-fedor/shoutrrr).
# Runs on the build platform; it only downloads and verifies the binary.
FROM --platform=$BUILDPLATFORM rclone/rclone:1.75.2@sha256:2687085f718d3c628f7fdfb77c52a1d344332aed543110bb88088f2c70d43eb5 AS shoutrrr

ARG SHOUTRRR_VERSION="0.22.1"
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
# Checks, on every platform, that the native module loads and can write and
# read a database; `actual --version` alone does not load it
RUN cd /app && node -e " \
    const db = new (require('better-sqlite3'))('/tmp/smoke.sqlite'); \
    db.exec('CREATE TABLE t (v TEXT)'); \
    db.prepare('INSERT INTO t VALUES (?)').run('ok'); \
    if (db.prepare('SELECT v FROM t').pluck().get() !== 'ok' \
      || db.pragma('integrity_check', { simple: true }) !== 'ok') process.exit(1); \
    db.close();" \
  && rm /tmp/smoke.sqlite \
  && actual --version
COPY --from=shoutrrr /usr/local/bin/shoutrrr /usr/local/bin/shoutrrr
COPY --chmod=755 scripts/*.sh /app/

# unhealthy while the last backup failed or one is overdue, see
# scripts/healthcheck.sh
HEALTHCHECK --interval=5m --timeout=10s CMD ["/app/healthcheck.sh"]

ENTRYPOINT ["/app/entrypoint.sh"]
