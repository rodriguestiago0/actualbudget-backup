# Schedule with systemd

Instead of keeping a container running with its own `CRON` schedule, a systemd timer can start a one-off backup container. Logs go to the journal, a failed backup shows as a failed service, and a backup missed while the machine was off runs at the next boot.

This uses your existing [`compose.yaml`](../compose.yaml). To run without Docker at all, see [run without Docker](run-without-docker.md).

> **Note:** Use either systemd or `docker compose up -d`, not both, or every backup runs twice.

<br>

## Install

1. Get the unit files, e.g. by cloning the repository:
   ```shell
   git clone https://github.com/rodriguestiago0/actualbudget-backup.git
   cd actualbudget-backup
   ```
2. In `systemd/actualbudget-backup.service`, set `WorkingDirectory` to the folder that contains your `compose.yaml`.
3. If the backup container is running, stop it from that folder with `docker compose down`.
4. Install the units and run one backup to check it works:
   ```shell
   sudo cp systemd/actualbudget-backup.service systemd/actualbudget-backup.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl start actualbudget-backup.service
   journalctl -u actualbudget-backup.service
   ```
5. Enable the timer (only the timer, not the service):
   ```shell
   sudo systemctl enable --now actualbudget-backup.timer
   ```

<br>

## Schedule

The timer runs daily at `00:00` in the host's timezone. `CRON` is not used. To change it, run `sudo systemctl edit actualbudget-backup.timer` and set another [`OnCalendar`](https://www.freedesktop.org/software/systemd/man/latest/systemd.time.html#Calendar%20Events):

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 03:30:00
```

`TIMEZONE` still sets the date in file names and the times in the log.

<br>

## Check

```shell
systemctl status actualbudget-backup.service     # result of the last backup
journalctl -u actualbudget-backup.service        # its log
systemctl list-timers actualbudget-backup.timer  # next run
```
