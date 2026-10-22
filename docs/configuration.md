# Configuration

All settings are environment variables. Only the first three are required.

| Variable | Default | Description |
| --- | --- | --- |
| [`ACTUAL_BUDGET_URL`](#actual-server) | | **Required.** Address of the Actual server |
| [`ACTUAL_BUDGET_PASSWORD`](#actual-server) | | **Required.** Actual server password |
| [`ACTUAL_BUDGET_SYNC_ID`](#actual-server) | | **Required.** Sync ID of the budget |
| [`ACTUAL_BUDGET_E2E_PASSWORD`](#actual-server) | | Encryption password, for an end-to-end encrypted budget |
| [`RCLONE_REMOTE_NAME`](#destination) | `ActualBudgetBackup` | rclone remote to upload to |
| [`RCLONE_REMOTE_DIR`](#destination) | `/ActualBudgetBackup/` | Folder on the remote |
| [`RCLONE_GLOBAL_FLAG`](#destination) | | Extra rclone flags |
| [`CRON`](#schedule) | `0 0 * * *` | When to back up |
| [`TIMEZONE`](#schedule) | `UTC` | Timezone for `CRON` and file names (`TZ` works too) |
| [`BACKUP_KEEP_DAYS`](#retention) | `0` | Delete backups older than this many days; `0` keeps all |
| [`ZIP_ENABLE`](#archive) | `TRUE` | `FALSE` saves an uncompressed `tar` instead |
| [`ZIP_TYPE`](#archive) | `zip` | `zip` or `7z` |
| [`ZIP_PASSWORD`](#archive) | | Password for the archive |
| [`BACKUP_FILE_SUFFIX`](#file-names) | `%Y%m%d` | Date format in file names |
| [`PUID`, `PGID`](#user) | | Run as this user and group instead of root |
| [`NOTIFICATION_URLS`](notifications.md) | | Where to send notifications |
| [`NOTIFICATION_ON`](notifications.md) | `success,failure` | Which events to notify |
| [`PING_URL`, `PING_URL_WHEN_*`](ping-notifications.md) | | URLs to call for health checks |

Several budgets and destinations use numbered variables, see [several budgets](multiple-sync-ids.md) and [several destinations](multiple-remote-destinations.md).

<br>

## Actual server

**`ACTUAL_BUDGET_URL`**: the address of your Actual server, including `http://` or `https://`, e.g. `https://actual.example.com`. `localhost` is the backup container itself, not your machine. When Actual runs in Docker on the same host, put both containers on one network and use Actual's container name, e.g. `http://actual_server:5006`. For a server with a self-signed certificate, see [troubleshooting](troubleshooting.md#authentication-failed-network-failure).

**`ACTUAL_BUDGET_PASSWORD`**: the password you log in to Actual with.

**`ACTUAL_BUDGET_SYNC_ID`**: the budget to back up. In Actual, open **Settings**, click **Show advanced settings**, and copy the **Sync ID**.

**`ACTUAL_BUDGET_E2E_PASSWORD`**: only for an [end-to-end encrypted](e2e-encrypted-backups.md) budget.

<br>

## Destination

**`RCLONE_REMOTE_NAME`**: the name of the remote created with `rclone config`. `rclone listremotes` shows the names you have:

```shell
docker run --rm \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone listremotes
```

**`RCLONE_REMOTE_DIR`**: the folder on the remote. It is created when missing.

**`RCLONE_GLOBAL_FLAG`**: extra [rclone flags](https://rclone.org/flags/) for every rclone command, e.g. `--bwlimit 1M`. Don't add flags that change rclone's output, such as `-P`: the cleanup reads it. To use an rclone config file somewhere else, mount it and set `--config /path/to/rclone.conf`.

Remotes can also be defined with rclone's own environment variables instead of a config file, e.g. `RCLONE_CONFIG_MYS3_TYPE: 's3'`. rclone lowercases these names, so set `RCLONE_REMOTE_NAME: 'mys3'`.

<br>

## Schedule

**`CRON`**: when the container starts a backup, as a [cron expression](https://crontab.guru/#0_0_*_*_*), run by [supercronic](https://github.com/aptible/supercronic). Not used when the backup is started [by systemd](systemd.md).

**`TIMEZONE`**: a [timezone name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) such as `Europe/Lisbon`. It sets when `CRON` runs, the times in the log and notifications, and the date in file names. `TZ` works too; when both are set, `TIMEZONE` wins. An unknown name is logged and UTC is used.

<br>

## Retention

**`BACKUP_KEEP_DAYS`**: after a successful backup, delete the backups older than this many days from every destination. `0`, the default, keeps everything.

Only files whose name starts with `backup.` are deleted, never other files or folders. Nothing is deleted after a failed backup, so a run of failures never removes your last good backups.

<br>

## Archive

Each budget is saved as its own archive, with `db.sqlite` and `metadata.json` at the root, the same layout as Actual's own export.

**`ZIP_TYPE`**: `zip` (default) or `7z`. A `zip` without a password can be imported into Actual as is. `7z` compresses better and, with a password, also hides the file names.

**`ZIP_PASSWORD`**: encrypts the archive with AES-256. Keep it somewhere other than the backups: without it, they can't be restored. An encrypted backup has to be unpacked before Actual can import it, see [restore](restore.md). Windows Explorer and some other built-in unzip tools can't open AES-encrypted zips; use [7-Zip](https://www.7-zip.org/) instead.

**`ZIP_ENABLE`**: `FALSE` saves an uncompressed `tar` instead of an archive. `ZIP_TYPE` and `ZIP_PASSWORD` are then ignored.

<br>

## File names

Backups are named `backup.<sync id>.<date>.<zip|7z|tar>`.

**`BACKUP_FILE_SUFFIX`**: the date part, in [`date` format](https://man7.org/linux/man-pages/man1/date.1.html). The default `%Y%m%d` gives one name per day, so a second backup the same day replaces the first. If you back up more often, add the time, e.g. `%Y%m%d_%H%M`. Any `/` is removed.

<br>

## User

By default the container runs as root, so the files it writes, such as the backups in a local or NAS folder and `rclone.conf` when rclone refreshes a token, belong to root.

**`PUID`**, **`PGID`**: the user and group IDs to run as instead, e.g. `PUID: '1000'` and `PGID: '1000'` (`id -u` and `id -g` on the host show yours; on Unraid they are `99` and `100`). At startup, the container gives `/config` to this user and group, then runs the schedule and the backups as them. With only `PUID` set, the group ID is the same number.

Compose's `user: '1000:1000'` works too. The container then never runs as root, so `/config` must already belong to that user.

Either way, a mounted `.env` file and `_FILE` secrets must be readable by that user.

<br>

## Setting values

### In `compose.yaml`

Use single quotes. A single quote inside the value is written twice: the password `it's` becomes `'it''s'`. Nothing else needs escaping, but a `$` must be written `$$`, since Compose reads `$NAME` as a variable.

### In a `.env` file

Instead of the `environment:` block, the settings can go in a file mounted at `/.env`. [`.env.example`](../.env.example) lists them all.

```yaml
services:
  backup:
    image: rodriguestiago0/actualbudget-backup:latest
    volumes:
      - actualbudget-rclone-data:/config/
      - ./backup.env:/.env:ro
```

Put one `NAME=value` per line. Values are read literally, nothing is expanded or run. Quote values with spaces or special characters, such as passwords, in single quotes: `ACTUAL_BUDGET_PASSWORD='pa$$ word'`. A value that contains a single quote can go in double quotes, where `\"` and `\\` are escapes. In an unquoted value, ` #` starts a comment.

### From files (Docker secrets)

Add `_FILE` to any variable name to read its value from a file instead, such as a [Docker secret](https://docs.docker.com/compose/how-tos/use-secrets/):

```yaml
services:
  backup:
    environment:
      ACTUAL_BUDGET_PASSWORD_FILE: '/run/secrets/actual-password'
    secrets:
      - actual-password

secrets:
  actual-password:
    file: ./actual-password.txt
```

### Priority

When a setting is given more than once, the first of these wins:

1. the environment variable, e.g. `ACTUAL_BUDGET_PASSWORD`
2. the file named by the `_FILE` environment variable
3. the file named by `_FILE` in `.env`
4. the value in `.env`

<br>

## Actual CLI version

Each image release contains a fixed version of the [Actual CLI](https://actualbudget.org/docs/api/cli/), pinned in [`package.json`](../package.json). Nothing is downloaded when a backup runs. To see it:

```shell
docker run --rm --entrypoint actual rodriguestiago0/actualbudget-backup:latest --version
```

The CLI upgrades the budget to its own version while downloading it, so a backup opens in that version of Actual or newer. Each backup logs both versions, and warns when your server is older than the CLI. Your own server then can't import those backups until you upgrade it, while a [fresh Actual](restore.md) still can.

<br>

## Old settings

These still work but are no longer needed:

| Variable | Instead |
| --- | --- |
| `BACKUP_FILE_DATE`, `BACKUP_FILE_DATE_SUFFIX` | `BACKUP_FILE_SUFFIX`, which replaces both and wins when set. The old ones built the name as `${BACKUP_FILE_DATE}${BACKUP_FILE_DATE_SUFFIX}`, keeping only letters, digits, `%`, `_` and `-`. |
| `ACTUAL_API_VERSION` | Ignored; the CLI version comes with the image. |
