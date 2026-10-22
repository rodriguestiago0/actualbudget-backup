# Restore a backup

Each backup is an archive named `backup.<sync id>.<date>.<zip|7z|tar>` with the budget's `db.sqlite` and `metadata.json`, the same files as an export from Actual. To restore it, start a fresh Actual and import the archive, as described in Actual's [restore documentation](https://actualbudget.org/docs/backup-restore/restore).

<br>

## 1. Download the backup

List the backups on your remote and copy one to the current directory. Use your own remote name and folder if you changed `RCLONE_REMOTE_NAME` or `RCLONE_REMOTE_DIR`.

```shell
docker run --rm \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  rodriguestiago0/actualbudget-backup:latest \
  rclone ls ActualBudgetBackup:/ActualBudgetBackup/

docker run --rm \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  -v "$PWD:/restore" \
  rodriguestiago0/actualbudget-backup:latest \
  rclone copy ActualBudgetBackup:/ActualBudgetBackup/backup.<sync id>.<date>.zip /restore/
```

Without Docker, run the same `rclone` commands directly.

A `zip` backup **without** `ZIP_PASSWORD` imports as is. A backup with a password, a `7z` backup or a `tar` backup has to be repacked as a plain zip first. Password-protected zips use AES-256, which Windows Explorer can't open, so use `7z`:

```shell
7z x -p'your-zip-password' -orestored 'backup.<sync id>.<date>.7z'
(cd restored && 7z a -tzip ../restored.zip db.sqlite metadata.json)
```

No `7z` on your machine? The image has it: open a shell in the current directory with the command below, then run the two commands above.

```shell
docker run --rm -it --user "$(id -u):$(id -g)" -v "$PWD:/work" -w /work \
  --entrypoint bash rodriguestiago0/actualbudget-backup:latest
```

<br>

## 2. Start a fresh Actual

Start a new, empty Actual server with its own data volume, so your existing server is not touched:

```shell
docker run -d --name actual-restore -p 5007:5006 \
  -v actual-restore-data:/data \
  actualbudget/actual-server:latest
```

Open http://localhost:5007 and set a password. See Actual's [install guide](https://actualbudget.org/docs/install/) for other ways to run it.

Use the `latest` Actual. The Actual you import into must be at least as new as the version that made the backup, and a fresh `latest` always is.

<br>

## 3. Import the backup

Follow Actual's [restore documentation](https://actualbudget.org/docs/backup-restore/restore): on the **Switch file** page, click **Import file**, choose **Actual** and select the zip.

If the budget used end-to-end encryption, the backup contains it decrypted. Turn encryption on again in the imported budget's settings.

Once you have checked the budget, keep using this server, or export the budget from it (**Settings > Export data**) and import that into your main Actual. When you are done with it:

```shell
docker rm -f actual-restore
docker volume rm actual-restore-data
```

