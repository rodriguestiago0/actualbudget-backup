# Actual Budget backup

Docker containers for [actualbudget](https://actualbudger.org) backup to remote.

Heavily inspired at [vaultwarden-backup](https://github.com/ttionya/vaultwarden-backup)

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

Download `docker-compose.yml` to you machine, edit the [environment variables](#environment-variables) and start it.

You need to go to the directory where the `docker-compose.yml` file is saved.

```shell
# Start
docker-compose up -d

# Stop
docker-compose stop

# Restart
docker-compose restart

# Remove
docker-compose down
```

#### Automatic Backups without docker compose

Start the backup container with default settings. (automatic backup at 12AM every day)

```shell
docker run -d \
  --restart=always \
  --name actualbudget_backup \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest
```

## Environment Variables

> **Note:** The container will run with no environment variables specified without error, however if you haven't set at least `ACTUAL_BUDGET_URL`, `ACTUAL_BUDGET_PASSWORD`, and `ACTUAL_BUDGET_SYNC_ID`, no backup will successfully happen.

### ACTUAL_BUDGET_URL

URL for the actual budget server, without a trailing `/`

### ACTUAL_BUDGET_PASSWORD

Password for the actual budget server. If you're setting this through the docker-compose file, Single quotes must be escaped with by doubling them up. e.g. if your password is `SuperGo'oodPassw\ord"1` you would enter `ACTUAL_BUDGET_PASSWORD: 'SuperGo''oodPassw\ord"1'`. If you're using the env file method, you will need to work out your own way to encode your password without breaking the env file.

### ACTUAL_BUDGET_SYNC_ID

Actual Sync ID. You can find this by logging into your Actual server in a web browser, go to `settings > show advanced settings` and the sync ID should be in the top block there.

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

Default: `''`

### CRON

Schedule to run the backup script, based on [`supercronic`](https://github.com/aptible/supercronic). You can test the rules [here](https://crontab.guru/#0_0_*_*_*).

Default: `0 0 * * *` (run the script at 12AM every day)

### BACKUP_KEEP_DAYS

Only keep last a few days backup files in the storage system. Set to `0` to keep all backup files.

Default: `0`

### BACKUP_FILE_SUFFIX

Each backup file is suffixed by default with `%Y%m%d`. If you back up your budget multiple times a day, that suffix is not unique any more. This environment variable allows you to append a unique suffix to that date to create a unique backup name.

You can use any character except for `/` since it cannot be used in Linux file names.

This environment variable combines the functionalities of [`BACKUP_FILE_DATE`](#backup_file_date) and [`BACKUP_FILE_DATE_SUFFIX`](#backup_file_date_suffix), and has a higher priority. You can directly use this environment variable to control the suffix of the backup files.

Please use the [date man page](https://man7.org/linux/man-pages/man1/date.1.html) for the format notation.

Default: `%Y%m%d`

### TIMEZONE

Set your timezone name.

Here is timezone list at [wikipedia](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

Default: `UTC`

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

If you prefer using an env file instead of environment variables, you can map the env file containing the environment variables to the `/.env` file in the container.

```shell
docker run -d \
  --mount type=bind,source=/path/to/env,target=/.env \
  rodriguestiago0/actualbudget-backup:latest
```

## Docker Secrets

As an alternative to passing sensitive information via environment variables, `_FILE` may be appended to the previously listed environment variables. This causes the initialization script to load the values for those variables from files present in the container. In particular, this can be used to load passwords from Docker secrets stored in `/run/secrets/<secret_name>` files.

```shell
docker run -d \
  -e ACTUAL_BUDGET_PASSWORD=/run/secrets/actual-budget-password \
  rodriguestiag0/actualbudget-backup:latest
```

## About Priority

We will use the environment variables first, followed by the contents of the file ending in `_FILE` as defined by the environment variables. Next, we will use the contents of the file ending in `_FILE` as defined in the `.env` file, and finally the values from the `.env` file itself.

## Advance

- [Multiple remote destinations](docs/multiple-remote-destinations.md)
- [Multiple sync ids](docs/multiple-sync-ids.md)
- [Manually trigger a backup](docs/manually-trigger-a-backup.md)


## License

MIT
