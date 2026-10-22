# Actual Budget backup

Backs up [Actual Budget](https://actualbudget.org) on a schedule to any storage [Rclone](https://rclone.org/) supports: S3, Backblaze B2, Google Drive, OneDrive, Dropbox, SFTP, a local folder and [many more](https://rclone.org/overview/).

Budgets are downloaded with the official [Actual CLI](https://actualbudget.org/docs/api/cli/) and saved as zip files that Actual can import directly.

- Back up several budgets, including end-to-end encrypted ones, to one or more destinations
- Optional password-protected `zip` or `7z` archives
- Old backups deleted after a number of days
- Notifications to Telegram, Discord, ntfy, email and more, and pings to health check services
- Runs as a Docker container, from a systemd timer, or without Docker

Images are on Docker Hub as [`rodriguestiago0/actualbudget-backup`](https://hub.docker.com/r/rodriguestiago0/actualbudget-backup), tagged `latest`, by version (`v1.2.3`) and by major or minor version (`v1`, `v1.2`, which follow the newest release), for `linux/amd64`, `linux/arm64`, `linux/arm/v7` and `linux/arm/v6`.

Inspired by [vaultwarden-backup](https://github.com/ttionya/vaultwarden-backup).

<br>

## Quick start

You need a running Actual server, and Docker on the machine that runs the backup.

1. Set up a storage destination with `rclone config`, naming it `ActualBudgetBackup`:
   ```shell
   docker run --rm -it \
     --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
     rodriguestiago0/actualbudget-backup:latest \
     rclone config
   ```
2. Download [`compose.yaml`](compose.yaml) and set `ACTUAL_BUDGET_URL`, `ACTUAL_BUDGET_PASSWORD` and `ACTUAL_BUDGET_SYNC_ID`.
3. Run one backup to check the configuration, then start the schedule (daily at midnight by default):
   ```shell
   docker compose run --rm backup backup
   docker compose up -d
   ```

The [getting started guide](docs/getting-started.md) walks through each step.

<br>

## Ways to run it

| | How the schedule runs | Guide |
| --- | --- | --- |
| **Docker Compose** (recommended) | A container stays running and starts each backup at the `CRON` time | [Getting started](docs/getting-started.md) |
| **systemd + Docker** | A systemd timer starts a one-off container; missed backups run at the next boot | [systemd](docs/systemd.md) |
| **Without Docker** | A systemd timer runs the script directly on the host | [Run without Docker](docs/run-without-docker.md) |

<br>

## Documentation

- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md): every setting, the `.env` file and Docker secrets
- [Restore a backup](docs/restore.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Notifications](docs/notifications.md) (Telegram, Discord, ntfy, email, ...) and [ping notifications](docs/ping-notifications.md) (healthchecks.io, Uptime Kuma, ...)
- [Several budgets](docs/multiple-sync-ids.md), [encrypted budgets](docs/e2e-encrypted-backups.md) and [several destinations](docs/multiple-remote-destinations.md)
- [Run a backup now](docs/manually-trigger-a-backup.md)
- [systemd + Docker](docs/systemd.md) and [run without Docker](docs/run-without-docker.md)

<br>

## Test your backups

A backup you have never restored is a guess. Every now and then, [restore one](docs/restore.md) into a temporary Actual and check your accounts. It takes a few minutes and doesn't touch your server.

<br>

## License

MIT
