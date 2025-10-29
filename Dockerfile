FROM rclone/rclone:1.66.0

LABEL "repository"="https://github.com/rodriguestiago0/actual-backup" \
  "homepage"="https://github.com/rodriguestiago0/actual-backup"

ARG USER_NAME="backuptool"
ARG USER_ID="1100"

ENV LOCALTIME_FILE="/tmp/localtime"

COPY scripts/*.js /app/
COPY scripts/*.sh /app/

RUN chmod +x /app/* \
  && apk add --no-cache grep file bash supercronic curl jq zip nodejs npm wget tar xz \
  && ln -sf "${LOCALTIME_FILE}" /etc/localtime \
  && addgroup -g "${USER_ID}" "${USER_NAME}" \
  && adduser -u "${USER_ID}" -Ds /bin/sh -G "${USER_NAME}" "${USER_NAME}"

ENTRYPOINT ["/app/entrypoint.sh"]