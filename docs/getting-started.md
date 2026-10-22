# Getting started

This guide sets up a daily backup with Docker Compose. You need:

- a running Actual server, and its password
- Docker with Compose on the machine that runs the backup, able to reach the Actual server

The commands are for Linux and macOS. On Windows PowerShell, replace the `\` at the end of each line with `` ` ``.

<br>

## 1. Set up rclone

The backups are uploaded with [rclone](https://rclone.org/), which supports [many storage systems](https://rclone.org/overview/). Its configuration is kept in a Docker volume, `actualbudget-rclone-data`, which the backup container reads.

Start the rclone setup:

```shell
docker run --rm -it \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone config
```

1. Choose `n` to create a new remote and name it `ActualBudgetBackup`. Another name works too, set it in `RCLONE_REMOTE_NAME`.
2. Follow [rclone's guide for your storage system](https://rclone.org/docs/).

Some storage systems, such as Google Drive, OneDrive and Dropbox, sign in through a web browser. The container has none, so answer `n` when rclone asks to open a browser, and follow its instructions to get a token with `rclone authorize` on a computer that has one.

Check the result:

```shell
docker run --rm \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone config show
```

```ini
[ActualBudgetBackup]
type = onedrive
...
```

Backups go to the `/ActualBudgetBackup/` folder of the remote. Use `RCLONE_REMOTE_DIR` to choose another one. Give the backups a folder of their own: old backups are deleted by name (`backup.*`) when [`BACKUP_KEEP_DAYS`](configuration.md#retention) is set.

<br>

## 2. Configure the backup

Download [`compose.yaml`](../compose.yaml) into a folder of its own and set the three required settings:

| Setting | Value |
| --- | --- |
| `ACTUAL_BUDGET_URL` | The address of your Actual server, as you open it in the browser, e.g. `https://actual.example.com`. If Actual runs in Docker on the same machine, its container address such as `http://actual_server:5006` works when both containers share a network. |
| `ACTUAL_BUDGET_PASSWORD` | The password you log in to Actual with. |
| `ACTUAL_BUDGET_SYNC_ID` | The budget to back up. In Actual, open **Settings**, click **Show advanced settings**, and copy the **Sync ID**. |

Settings you will probably want too:

| Setting | Default | |
| --- | --- | --- |
| `TIMEZONE` | `UTC` | Your timezone, e.g. `Europe/Lisbon`. Sets when `CRON` runs and the date in file names. |
| `CRON` | `0 0 * * *` | When to back up, as a [cron expression](https://crontab.guru/). The default is daily at midnight. |
| `BACKUP_KEEP_DAYS` | `0` | Delete backups older than this many days. `0` keeps them all. |

Values in `compose.yaml` are in single quotes. If a value contains a single quote, write it twice: `'it''s'`. All the settings are in [configuration](configuration.md).

<br>

## 3. Test it

From the folder with `compose.yaml`, run one backup:

```shell
docker compose run --rm backup backup
```

It takes a few seconds and ends with:

```
upload backup file to storage system [backup/backup.<sync id>.20261022.zip -> ActualBudgetBackup:/ActualBudgetBackup]
backup finished successfully
```

The file `backup.<sync id>.20261022.zip` is now in your storage. If something failed, the log says what, and [troubleshooting](troubleshooting.md) lists the usual causes.

<br>

## 4. Start the schedule

```shell
docker compose up -d
```

The container keeps running and starts a backup at the `CRON` time. Nothing runs when it starts, so the first backup happens at the next scheduled time. Check it later with `docker compose logs`.

<br>

## Next steps

- [Get a message](notifications.md) when a backup fails
- [Restore a backup](restore.md) once, to know it works
- Back up [several budgets](multiple-sync-ids.md) or to [several destinations](multiple-remote-destinations.md)
