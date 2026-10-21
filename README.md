# Actual Budget backup

Docker image that backs up [Actual Budget](https://actualbudget.org) to any remote storage, on a schedule.

Budgets are downloaded with the official [Actual CLI](https://actualbudget.org/docs/api/cli/) and uploaded with [Rclone](https://rclone.org/) to any storage system it supports.

Heavily inspired by [vaultwarden-backup](https://github.com/ttionya/vaultwarden-backup)

Images are published to Docker Hub as [`rodriguestiago0/actualbudget-backup`](https://hub.docker.com/r/rodriguestiago0/actualbudget-backup) (`latest` and versioned tags such as `v1.0.13`) for `linux/amd64`, `linux/arm64`, `linux/arm/v7` and `linux/arm/v6`.

> **Important:** We assume you already read the `actualbudget` [documentation](https://actualbudget.org/docs/), and have an instance up and running.

## Getting started guide

The fastest way to get started is with the [getting started guide](docs/getting-started.md), which contains the required config to get running as quickly as possible. This README contains the full details of all the extras you might need to run as well.

## Usage

### Configure Rclone (⚠️ MUST READ ⚠️)

> **For backup, you need to configure Rclone first, otherwise the backup tool will not work.**

We upload the backup files to the storage system by [Rclone](https://rclone.org/).

Visit [Rclone's documentation](https://rclone.org/docs/) for more storage system tutorials. Different systems get tokens differently.

#### Configure and Check

You can get the token by the following command.

```shell
docker run --rm -it \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone config
```

**We recommend setting the remote name to `ActualBudgetBackup`, otherwise you need to specify the environment variable `RCLONE_REMOTE_NAME` as the remote name you set.**

After setting, check the configuration content by the following command.

```shell
docker run --rm -it \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone config show

# Microsoft Onedrive Example
# [ActualBudgetBackup]
# type = onedrive
# token = {"access_token":"access token","token_type":"token type","refresh_token":"refresh token","expiry":"expiry time"}
# drive_id = driveid
# drive_type = personal
```

### Backup

#### Use Docker Compose (Recommend)

Download [`compose.yaml`](compose.yaml) to your machine, edit the [environment variables](#environment-variables) and start it.

You need to go to the directory where the `compose.yaml` file is saved.

```shell
# Start
docker compose up -d

# Stop
docker compose stop

# Restart
docker compose restart

# Remove
docker compose down
```

#### Automatic Backups without docker compose

Start the backup container with the default schedule (a backup at 12AM every day).

```shell
docker run -d \
  --restart=always \
  --name actualbudget_backup \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  -e ACTUAL_BUDGET_URL='https://actual.example.com' \
  -e ACTUAL_BUDGET_PASSWORD='your-password' \
  -e ACTUAL_BUDGET_SYNC_ID='your-sync-id' \
  rodriguestiago0/actualbudget-backup:latest
```

#### Automatic Backups with systemd

Instead of keeping the container running with its built-in cron schedule, you can let a systemd timer start a one-off backup container. Logs then go to the journal, and a backup missed while the machine was off runs at the next boot. This repository includes a service (`systemd/actualbudget-backup.service`) and a timer (`systemd/actualbudget-backup.timer`).

> **Note:** Use either systemd or `docker compose up -d`, not both, or every backup runs twice. In this mode `CRON` is not used, and the timer follows the host's timezone.

**Installation Manual:**

1. Edit the `WorkingDirectory` in `systemd/actualbudget-backup.service` to point to the directory containing your `compose.yaml`.
2. If the backup container is running, stop it with `docker compose down`.
3. Copy both files to the systemd directory:
   ```shell
   sudo cp systemd/actualbudget-backup.service /etc/systemd/system/
   sudo cp systemd/actualbudget-backup.timer /etc/systemd/system/
   ```
4. Reload the systemd manager configuration:
   ```shell
   sudo systemctl daemon-reload
   ```
5. Run a backup once to check that it works, then enable and start the timer (only the timer is enabled, not the service):
   ```shell
   sudo systemctl start actualbudget-backup.service
   sudo systemctl enable --now actualbudget-backup.timer
   ```

By default, the provided timer is configured to run daily at `00:00`. You can customize this schedule by editing the `OnCalendar` rule in the `actualbudget-backup.timer` file.

Check the result of the last backup and the next scheduled run with:

```shell
systemctl status actualbudget-backup.service
journalctl -u actualbudget-backup.service
systemctl list-timers actualbudget-backup.timer
```

A failed backup marks the service as failed.

To run the backup without Docker at all, see [run without Docker](docs/run-without-docker.md).

## Environment Variables

> **Note:** At least `ACTUAL_BUDGET_URL`, `ACTUAL_BUDGET_PASSWORD` and `ACTUAL_BUDGET_SYNC_ID` must be set. The container stops at startup when `ACTUAL_BUDGET_SYNC_ID` is missing or the rclone remote cannot be found.

### ACTUAL_BUDGET_URL

URL for the actual budget server, e.g. `https://actual.example.com`.

Default: `https://localhost:5006`

### ACTUAL_BUDGET_PASSWORD

Password for the actual budget server. If you're setting this through the compose file, Single quotes must be escaped with by doubling them up. e.g. if your password is `SuperGo'oodPassw\ord"1` you would enter `ACTUAL_BUDGET_PASSWORD: 'SuperGo''oodPassw\ord"1'`. If you're using the env file method, you will need to work out your own way to encode your password without breaking the env file.

### ACTUAL_BUDGET_SYNC_ID

Actual Sync ID. You can find this by logging into your Actual server in a web browser, go to `settings > show advanced settings` and the sync ID should be in the top block there.

To back up several budgets, see [multiple sync ids](docs/multiple-sync-ids.md).

### ACTUAL_BUDGET_E2E_PASSWORD

The end-to-end encryption password, only needed if your budget is encrypted. See [encrypted files](docs/e2e-encrypted-backups.md).

Default: `''`

### Actual CLI version

The [Actual CLI](https://actualbudget.org/docs/api/cli/) (`@actual-app/cli`) is installed when the image is built, and its version is pinned in [`package.json`](package.json). Each image release ships a tested CLI version, so nothing is downloaded at backup time. You can check which version an image contains with:

```shell
docker run --rm --entrypoint actual rodriguestiago0/actualbudget-backup:latest --version
```

> **Note:** `ACTUAL_API_VERSION` is no longer used.

The CLI upgrades the downloaded budget to its own database version, so **a backup can only be imported into an Actual version at least as new as the bundled CLI**. Each backup logs both versions and prints a warning when your server is older than the CLI. Restoring into the same or a newer Actual always works; if you can't upgrade your server, use an image release whose CLI is not newer than your server.

### RCLONE_REMOTE_NAME

The name of the Rclone remote, which needs to be consistent with the remote name in the rclone config.

You can view the current remote name with the following command.

```shell
docker run --rm -it \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone config show

# [ActualBudgetBackup] <- this
# ...
```

Default: `ActualBudgetBackup`

### RCLONE_REMOTE_DIR

The folder where backup files are stored in the storage system.

Default: `/ActualBudgetBackup/`

### RCLONE_GLOBAL_FLAG

Rclone global flags, see [flags](https://rclone.org/flags/).

**Do not add flags that will change the output, such as `-P`, which will affect the deletion of outdated backup files.**

To use an rclone config file somewhere other than `/config/rclone/rclone.conf`, mount it and point rclone at it, e.g. `RCLONE_GLOBAL_FLAG: '--config /path/to/rclone.conf'`. Remotes defined through rclone's own environment variables (e.g. `RCLONE_CONFIG_MYREMOTE_TYPE`) work as well.

Default: `''`

### ZIP_ENABLE

Pack all backup files into a compressed archive. When set to `'FALSE'`, each backup file will be a uncompressed tar archive.

Each archive contains `db.sqlite` and `metadata.json` at its root, so a `zip` backup without a password can be imported directly in Actual (`Import file > Actual`). See [restore a backup](docs/restore.md).

Default: `TRUE`

### ZIP_PASSWORD

The password for the compressed archive. When set, the archive will be encrypted with this password. Leave empty for no password.

Default: `''` (no password)

### ZIP_TYPE

The archive format. Supports `zip` and `7z`. The `7z` format provides better compression and encryption (header encryption with `-mhe=on`).

Default: `zip`

### CRON

Schedule to run the backup script, based on [`supercronic`](https://github.com/aptible/supercronic). You can test the rules [here](https://crontab.guru/#0_0_*_*_*).

Default: `0 0 * * *` (run the script at 12AM every day)

### BACKUP_KEEP_DAYS

Only keep last a few days backup files in the storage system. Set to `0` to keep all backup files.

Default: `0`

### BACKUP_FILE_SUFFIX

The date format used in backup file names (`backup.<sync id>.<suffix>.zip`). If you back up your budget multiple times a day, the default `%Y%m%d` is not unique any more, so include the time, e.g. `%Y%m%d_%H%M`.

You can use any character except for `/` since it cannot be used in Linux file names.

This environment variable combines the functionalities of [`BACKUP_FILE_DATE`](#backup_file_date) and [`BACKUP_FILE_DATE_SUFFIX`](#backup_file_date_suffix), and has a higher priority. You can directly use this environment variable to control the suffix of the backup files.

Please use the [date man page](https://man7.org/linux/man-pages/man1/date.1.html) for the format notation.

Default: `%Y%m%d`

### TIMEZONE

Set your timezone name.

Here is timezone list at [wikipedia](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

The standard `TZ` variable works too; if both are set, `TIMEZONE` wins. An unknown timezone is logged and UTC is used.

Default: `UTC`

### NOTIFICATION_URLS

Send a message to Telegram, Discord, Slack, ntfy, email and [many other services](https://shoutrrr.nickfedor.com/latest/services/overview/) when a backup starts, succeeds or fails. Takes one or more [Shoutrrr](https://github.com/nicholas-fedor/shoutrrr) URLs separated by spaces, the same URLs Watchtower uses, e.g. `telegram://<bot-token>@telegram?chats=<chat-id>`.

`NOTIFICATION_ON` chooses the events: any of `start`, `success`, `failure` (default `success,failure`).

See [notifications](docs/notifications.md).

Default: `''`

### PING_URL

Call a URL when a backup finishes, for health check services such as [healthchecks.io](https://healthchecks.io/). `PING_URL_WHEN_START`, `PING_URL_WHEN_SUCCESS` and `PING_URL_WHEN_FAILURE` are called on those events.

See [ping notifications](docs/ping-notifications.md).

Default: `''`

<details>
<summary><strong>※ Other environment variables</strong></summary>

> **You don't need to change these environment variables unless you know what you are doing.**

### BACKUP_FILE_DATE

You should use the [`BACKUP_FILE_SUFFIX`](#backup_file_suffix) environment variable instead.

Edit this environment variable only if you explicitly want to change the time prefix of the backup file (e.g. 20220101). **Incorrect configuration may result in the backup file being overwritten by mistake.**

Same rule as [`BACKUP_FILE_DATE_SUFFIX`](#backup_file_date_suffix).

Default: `%Y%m%d`

### BACKUP_FILE_DATE_SUFFIX

You should use the [`BACKUP_FILE_SUFFIX`](#backup_file_suffix) environment variable instead.

Each backup file is suffixed by default with `%Y%m%d`. If you back up your budget multiple times a day, that suffix is not unique anymore.
This environment variable allows you to append a unique suffix to that date (`%Y%m%d${BACKUP_FILE_DATE_SUFFIX}`) to create a unique backup name.

Note that only numbers, upper and lower case letters, `-`, `_`, `%` are supported.

Please use the [date man page](https://man7.org/linux/man-pages/man1/date.1.html) for the format notation.

Default: `''`

</details>

## Using `.env` file

If you prefer using an env file instead of environment variables, you can map the env file containing the environment variables to the `/.env` file in the container. A template with all supported variables (commented out) is provided as [`.env.example`](/.env.example) — copy it to `.env` and fill in your values.

```shell
docker run -d \
  --mount type=bind,source=/path/to/env,target=/.env \
  rodriguestiago0/actualbudget-backup:latest
```

## Docker Secrets

As an alternative to passing sensitive information via environment variables, `_FILE` may be appended to the previously listed environment variables. This causes the initialization script to load the values for those variables from files present in the container. In particular, this can be used to load passwords from Docker secrets stored in `/run/secrets/<secret_name>` files.

```shell
docker run -d \
  -e ACTUAL_BUDGET_PASSWORD_FILE=/run/secrets/actual-budget-password \
  rodriguestiago0/actualbudget-backup:latest
```

## About Priority

We will use the environment variables first, followed by the contents of the file ending in `_FILE` as defined by the environment variables. Next, we will use the contents of the file ending in `_FILE` as defined in the `.env` file, and finally the values from the `.env` file itself.

## Advance

- [Multiple remote destinations](docs/multiple-remote-destinations.md)
- [Multiple sync ids](docs/multiple-sync-ids.md)
- [Manually trigger a backup](docs/manually-trigger-a-backup.md)
- [Restore a backup](docs/restore.md)
- [Run without Docker (systemd)](docs/run-without-docker.md)
- [Encrypted files](docs/e2e-encrypted-backups.md)
- [Notifications (Telegram, Discord, ntfy, email, ...)](docs/notifications.md)
- [Ping notifications](docs/ping-notifications.md)

## License

MIT
