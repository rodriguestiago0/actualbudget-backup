# Troubleshooting

Start with one backup in the foreground, which shows the whole log:

```shell
docker compose run --rm backup backup
```

The first lines list the settings in use, with passwords hidden. Look for the first error below them.

<br>

## Startup errors

The container stops before any backup runs, and no notification is sent. Health check services see the missing [ping](ping-notifications.md).

#### `ACTUAL_BUDGET_URL is not set` or `Invalid sync id`

A required setting is missing. Check its name in `compose.yaml`, and that it is under `environment:` of the right service.

#### `rclone configuration information not found [ActualBudgetBackup]`

There is no rclone remote with that name.

- Run `rclone listremotes` (see [destination](configuration.md#destination)) and set `RCLONE_REMOTE_NAME` to one of the names, without the `:`.
- Check that the container mounts the volume where you ran `rclone config`: `actualbudget-rclone-data` at `/config/`.
- Remotes defined with environment variables are lowercased by rclone.

#### `illegal rclone global flags`

`RCLONE_GLOBAL_FLAG` contains a flag rclone doesn't know.

#### `storage system connection failure`

rclone can't reach the storage. At startup this is only a warning: the container keeps running and the scheduled backup tries again, failing and notifying if the storage is still unreachable. Test it with `rclone lsd ActualBudgetBackup:` using the command in [destination](configuration.md#destination). An expired token, common with OneDrive and Google Drive after a long time, is fixed with `rclone config reconnect ActualBudgetBackup:`.

#### `external volume "actualbudget-rclone-data" not found`

Docker Compose expects the volume to exist. It is created by the first `rclone config` command in [getting started](getting-started.md#1-set-up-rclone).

<br>

## Backup errors

The backup runs but fails. A [notification](notifications.md) is sent, and old backups are not deleted.

#### `Authentication failed: invalid-password`

`ACTUAL_BUDGET_PASSWORD` is wrong. In `compose.yaml`, a `'` in the password is written `''` and a `$` is written `$$`, see [setting values](configuration.md#setting-values).

#### `Authentication failed: network-failure`

The Actual server can't be reached, or its HTTPS certificate isn't trusted.

- `localhost` is the backup container, not your machine. Use the address you open Actual with, or Actual's container name on a shared Docker network, e.g. `http://actual_server:5006`.
- With a self-signed certificate or a private certificate authority, mount its CA certificate and point Node.js at it:
  ```yaml
  services:
    backup:
      environment:
        NODE_EXTRA_CA_CERTS: '/certs/ca.crt'
      volumes:
        - ./ca.crt:/certs/ca.crt:ro
  ```
  Behind Caddy with `tls internal`, the CA is in Caddy's data folder at `pki/authorities/local/root.crt`.

#### `Budget "..." not found`

`ACTUAL_BUDGET_SYNC_ID` is wrong. Copy it again from **Settings > Show advanced settings > Sync ID**. The budget must have been synced to the server at least once.

#### `download failed` for an encrypted budget

The encryption password is missing or wrong. Each budget reads its own `ACTUAL_BUDGET_E2E_PASSWORD_N`, see [encrypted budgets](e2e-encrypted-backups.md).

#### `WARNING: your Actual server (...) is older than the Actual CLI`

The backup works, but your server can't import it until you upgrade Actual. It is also sent as a [`warning` notification](notifications.md). A [fresh Actual](restore.md) can. See [Actual CLI version](configuration.md#actual-cli-version).

<br>

## Other problems

#### No backup at the expected time

- The container only backs up at the `CRON` time, not when it starts.
- `CRON` follows `TIMEZONE`, which is UTC by default.
- With [systemd](systemd.md), `CRON` is not used: check `systemctl list-timers`.

#### A backup a day replaces the previous one

[`BACKUP_FILE_SUFFIX`](configuration.md#file-names) has only the date. Add the time, as the default `%Y%m%d_%H%M%S` does.

#### The container is `unhealthy`

The last backup failed, or none succeeded in the last [`HEALTHCHECK_MAX_HOURS`](configuration.md#schedule); the log says why, and for the second, check that `CRON` runs when you expect. The container is healthy again once a backup succeeds. To see the result of the last backup:

```shell
docker inspect --format '{{json .State.Health.Log}}' <container>
```

#### `Permission denied` with `PUID`/`PGID` or `user:`

The backup runs as that user, so it must be able to read the mounted `.env` file and `_FILE` secrets, e.g. `chmod 644`. With `user:`, `/config` must also be writable by it; `PUID`/`PGID` take care of that. See [user](configuration.md#user).

<br>

Still stuck? [Open an issue](https://github.com/rodriguestiago0/actualbudget-backup/issues) with the log, after removing your URLs and sync IDs.
