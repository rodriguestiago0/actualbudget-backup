# Restore a backup

Each backup is an archive named `backup.<sync id>.<date>.<zip|7z|tar>` that contains the budget's `db.sqlite` and `metadata.json`. Actual imports it as a zip file.

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

<br>

## 2. Get an importable zip

A `zip` backup **without** `ZIP_PASSWORD` can be imported as is; skip to step 3.

A backup with a password, a `7z` backup or a `tar` backup (`ZIP_ENABLE: 'FALSE'`) has to be repacked as a plain zip first. The image contains `7z`, so nothing else needs to be installed. Set `FILE` to your backup and `PASSWORD` to your `ZIP_PASSWORD` (leave it empty if there is none):

```shell
FILE='backup.<sync id>.<date>.7z'
PASSWORD='your-zip-password'

docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" -w /work \
  -e FILE="$FILE" -e PASSWORD="$PASSWORD" \
  --entrypoint sh rodriguestiago0/actualbudget-backup:latest -c \
  '7z x -y -p"$PASSWORD" -orestored "$FILE" && cd restored && 7z a -tzip ../restored.zip db.sqlite metadata.json'
```

This creates `restored.zip`, next to a `restored` folder you can delete afterwards.

<br>

## 3. Import it in Actual

1. In Actual, click the budget name in the top-left corner and choose **Switch file**.
2. Click **Import file**, then choose **Actual**.
3. Select the zip file and import it.

The budget is imported as a new file next to your existing ones, so nothing is overwritten. Check it, then rename it or delete the old copy. See Actual's [restore documentation](https://actualbudget.org/docs/backup-restore/restore) for more details.

If the budget used end-to-end encryption, the backup contains it decrypted. Turn encryption on again in the imported budget's settings.

<br>

## Version compatibility

The Actual CLI in the image upgrades the budget to its own version while downloading it. **A backup can only be imported into an Actual version at least as new as the CLI of the image that made it.** Each backup's log shows both versions. To check the CLI version of an image:

```shell
docker run --rm --entrypoint actual rodriguestiago0/actualbudget-backup:<tag> --version
```

If Actual says *"This budget cannot be loaded with this version of the app"*, upgrade Actual to at least that version and import again.
