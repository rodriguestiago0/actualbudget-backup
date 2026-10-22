# Run a backup now

Pass `backup` as the command to run one backup and exit, without waiting for the schedule. Use it to test your settings, or to back up before upgrading Actual.

From the folder with `compose.yaml`:

```shell
docker compose run --rm backup backup
```

This starts a separate container, so the scheduled one can keep running.

Without Compose, pass the same settings with `-e`:

```shell
docker run --rm \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  -e ACTUAL_BUDGET_URL='https://actual.example.com' \
  -e ACTUAL_BUDGET_PASSWORD='your-password' \
  -e ACTUAL_BUDGET_SYNC_ID='your-sync-id' \
  rodriguestiago0/actualbudget-backup:latest backup
```

`CRON` is not used in this mode.

The container exits with status `0` when every budget was backed up and uploaded, and `1` otherwise, so other schedulers, such as [systemd](systemd.md) or a Kubernetes CronJob, can detect failed backups. Budgets that downloaded are uploaded even if another one failed, and old backups are not deleted after a failed run.
