# Manually trigger a backup

Sometimes, it's necessary to manually trigger backup actions.

This can be useful when other programs are used to consistently schedule tasks or to verify that environment variables are properly configured.

## Usage

Previously, performing an immediate backup required overwriting the entrypoint of the image. However, with the new setup, you can perform a backup directly with a parameterless command.

If you have already configured your docker compose file correctly, you can trigger this with the following command (You will need to `docker compose down` the running container first if it is running):

```shell
docker compose run --rm backup backup
```

If you have not configured Docker compose yet, you can run the image manually, and specify the env variables on the cli as follows

```shell
docker run \
  --rm \
  --name actualbudget-backup \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  -e ... \
  rodriguestiago0/actualbudget-backup:latest backup
```

You also need to mount the rclone config file and set the environment variables.

The only difference is that the environment variable `CRON` does not work because it does not start the CRON program, but exits the container after the backup is done.
