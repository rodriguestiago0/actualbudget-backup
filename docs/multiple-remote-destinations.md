# Several destinations

Each backup can be uploaded to more than one place, e.g. a cloud drive and a NAS. First add each destination as a remote with `rclone config`, as in [getting started](getting-started.md#1-set-up-rclone).

Then add numbered destinations next to `RCLONE_REMOTE_NAME` and `RCLONE_REMOTE_DIR`, starting at `_1`. Each needs both a name and a folder:

```yaml
environment:
  # the first destination, here with its defaults
  # RCLONE_REMOTE_NAME: 'ActualBudgetBackup'
  # RCLONE_REMOTE_DIR: '/ActualBudgetBackup/'
  RCLONE_REMOTE_NAME_1: 'nas'
  RCLONE_REMOTE_DIR_1: '/backups/actual/'
  RCLONE_REMOTE_NAME_2: 'b2'
  RCLONE_REMOTE_DIR_2: 'my-bucket/actual'
```

This uploads to `ActualBudgetBackup:/ActualBudgetBackup/`, `nas:/backups/actual/` and `b2:my-bucket/actual`.

The numbers must follow each other: reading stops at the first number with a missing name or folder. The log lists every destination it found.

At startup, every destination must be reachable or the container stops. When a backup runs, it continues if at least one destination works, and is reported as failed. [`BACKUP_KEEP_DAYS`](configuration.md#retention) applies to every destination.
