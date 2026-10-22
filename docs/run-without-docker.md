# Run without Docker

The backup is a bash script, so it can also run directly on a Linux host, started by a systemd timer instead of a container. No container keeps running between backups, logs go to the journal, and a backup missed while the machine was off runs at the next boot.

The steps below are for Debian and Ubuntu; other distributions need the same tools from their own packages.

<br>

## 1. Install the requirements

| Tool | Version | Debian / Ubuntu |
| --- | --- | --- |
| bash, curl, git | | `sudo apt install bash curl git` |
| 7z | | `sudo apt install 7zip` |
| rclone | | `sudo apt install rclone`, or the [rclone install script](https://rclone.org/install/) for the latest version |
| Node.js | **22 or newer** | Debian 13 ships 20, which is too old. Use [NodeSource](https://github.com/nodesource/distributions) or the [official binaries](https://nodejs.org/en/download) |
| python3, make, g++ | | `sudo apt install python3 make g++`, needed by `npm ci` to install the CLI's SQLite module |
| [Shoutrrr](https://github.com/nicholas-fedor/shoutrrr/releases) | optional | only for [notifications](notifications.md): copy the `shoutrrr` binary to `/usr/local/bin` |

<br>

## 2. Install the backup scripts

Clone a release into `/opt/actualbudget-backup` and install the Actual CLI next to it:

```shell
sudo git clone https://github.com/rodriguestiago0/actualbudget-backup.git /opt/actualbudget-backup
cd /opt/actualbudget-backup
sudo git checkout "$(sudo git describe --tags --abbrev=0 origin/main)"   # the latest release
sudo npm ci --omit=dev
```

The CLI version is the one pinned by that release, see [Actual CLI version](configuration.md#actual-cli-version).

<br>

## 3. Create the user and the rclone config

The service runs as its own system user. Its home, `/var/lib/actualbudget-backup`, holds the rclone config and the working files.

```shell
sudo useradd --system --home-dir /var/lib/actualbudget-backup --shell /usr/sbin/nologin actualbudget-backup
sudo install -d -o actualbudget-backup -g actualbudget-backup -m 700 /var/lib/actualbudget-backup

sudo -u actualbudget-backup rclone config --config /var/lib/actualbudget-backup/rclone.conf
```

Name the remote `ActualBudgetBackup`, or set `RCLONE_REMOTE_NAME` in the next step. To reuse a config made for the Docker image, copy its `rclone.conf` to that path and give it to the user with `sudo chown actualbudget-backup: /var/lib/actualbudget-backup/rclone.conf`.

<br>

## 4. Configure the backup

The settings are the same [environment variables](configuration.md) as for the Docker image, in `/etc/actualbudget-backup/backup.env`. Only root can read it, since it contains your password:

```shell
sudo install -d -m 755 /etc/actualbudget-backup
sudo install -m 600 /dev/null /etc/actualbudget-backup/backup.env
sudo nano /etc/actualbudget-backup/backup.env
```

```shell
ACTUAL_BUDGET_URL=https://actual.example.com
ACTUAL_BUDGET_PASSWORD=your-password
ACTUAL_BUDGET_SYNC_ID=your-sync-id
BACKUP_KEEP_DAYS=30
TIMEZONE=Europe/Lisbon
# NOTIFICATION_URLS="telegram://<bot-token>@telegram?chats=<chat-id>"
# NOTIFICATION_ON=failure
```

This file is read by systemd: put one `NAME=value` per line, use double quotes around values with spaces, and keep comments on their own lines (a `#` after a value is part of the value).

`CRON` is not used: the timer sets the schedule. `TIMEZONE` (or `TZ`) still sets the date in the backup file names.

<br>

## 5. Install and start the systemd units

```shell
sudo cp /opt/actualbudget-backup/systemd/native/actualbudget-backup.service /etc/systemd/system/
sudo cp /opt/actualbudget-backup/systemd/actualbudget-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload

# run one backup now to check the configuration
sudo systemctl start actualbudget-backup.service
journalctl -u actualbudget-backup.service

# then back up on schedule (only the timer is enabled, not the service)
sudo systemctl enable --now actualbudget-backup.timer
```

The timer runs daily at `00:00` in the host's timezone. To change it, run `sudo systemctl edit actualbudget-backup.timer` and set another [`OnCalendar`](https://www.freedesktop.org/software/systemd/man/latest/systemd.time.html#Calendar%20Events) value:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:30:00
```

Check the last backup and the next run with:

```shell
systemctl status actualbudget-backup.service
systemctl list-timers actualbudget-backup.timer
```

A failed backup marks the service as failed. The service is sandboxed: it can only write to `/var/lib/actualbudget-backup` and a private `/tmp`.

<br>

## Updating

```shell
cd /opt/actualbudget-backup
sudo git fetch --tags
sudo git checkout "$(sudo git describe --tags --abbrev=0 origin/main)"
sudo npm ci --omit=dev
```

A new release can bundle a newer Actual CLI. Backups are restored into a fresh, `latest` Actual, see [restore a backup](restore.md).
