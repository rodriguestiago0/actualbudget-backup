# Getting Started

This doc should contain the minimal steps required to get a working backup going. It assumes you already have a box with docker running that this will run on, and that that box is able to talk to your Actual server over https.

## Setup

There are two parts to the setup, one to tell the backup system how to connect to your Actual server, and the other to tell the backup system how to connect to the storage system you are going to save the backup to. We will setup the storage first, and then the connection to Actual.

### Storage

The backup system uses Rclone to talk to the storage system. At time of writing, Rclone supports 55 different storage systems, so this guide will not tell you exactly how to setup your storage system, for that you should check out [Rclone's excellent documentation](https://rclone.org/docs/). However these are the required steps to get it working in this system.

1. Run the following code to start the setup. Note: if you're running this on Windows, replace the `\` at the end of each line with `` ` `` (backticks)

   ```shell
   docker run --rm -it \
     --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
     rodriguestiago0/actualbudget-backup:latest \
     rclone config
   ```

2. Choose the option to create a new remote, and when prompted for a name call it "ActualBudgetBackup".
3. From here, follow the instructions from Rclone's Documentation to set up your storage.

The only thing to note that we're doing differently is that Rclone is running inside Docker. There are a few storage providers that require you to launch a web browser as part of the auth flow (e.g Google Drive and OneDrive). If you are using one of these methods, you will need to answer "no" to Rclone launching the browser for you (as the Docker container is headless), and follow the instructions it will then provide to use Rclone on a different machine to get the auth token.

### Connection to Actual

Next we need to tell the container how it's going to talk to your Actual server. To start with, download the [`docker-compose.yml`](/docker-compose.yml?raw=1) file to your machine. Put it in its own folder somewhere, and then open it for editing. I will go over the mandatory and most used fields here, for the others, check the [README](/README) for what they do.

#### Mandatory fields

`ACTUAL_BUDGET_URL` - First, we need to tell it the url of the website, including the protocol, and the port (if applicable) (NB: Do NOT add a trailing / to this. For e.g. `ACTUAL_BUDGET_URL: 'https://acutal.example.com'` will work, but `ACTUAL_BUDGET_URL: 'https://acutal.example.com/'` will not)

`ACTUAL_BUDGET_PASSWORD` - Second, you need to put the password for your budget. (NB: If your password contains either a `'` or a `\`, you need to escape them e.g. if your password was `123Super'Pass\word` you would need to enter `ACTUAL_BUDGET_PASSWORD: '123Super\'Pass\\word'`. If your password contains any of `"`, `$`, or a space, change it so it doesn't. It's possible to make that work, but it's painful.

`ACTUAL_BUDGET_SYNC_ID` - Finally, this identifies the budget on the server. To get this ID, open Actual in your web browser, and go to `Settings`. At the bottom, click `Show advanced settings`, and the `Sync ID` should be in the top section there.

#### Optional fields you might need to change

`ACTUAL_BUDGET_SYNC_ID_1` If you have multiple budgets to backup, you can add more sync IDs by using the `ACTUAL_BUDGET_SYNC_ID_1: ''` field to hold the second ID, and you can add as many of those as you want by incrementing the number `ACTUAL_BUDGET_SYNC_ID_2`, `ACTUAL_BUDGET_SYNC_ID_3`... etc.

`CRON` - This line tells the container what time to perform the backup. By default, it happens at midnight every day. This is fine if your computer is on 24/7, but if the machine you're running this on is only active in the day, you might want to change it to happen when you know it will be on. To do this, enter any valid cron string, but note that the default config only allows one backup per day, so making it occur more frequently will overwrite the first backup.

`TIMEZONE` - your local timezone. If you're changing the cron time, you will also want to set the timezone, else it will not run at the time you want it to. It's entered in standard TZ data format. e.g. to set the timezone to UK time, you'd set it to `TIMEZONE: 'Europe/London'`

`BACKUP_KEEP_DAYS` - by default, this tool never deletes old backups. To change this behaviour, set this to the number of days to keep backups for. e.g. for a weeks worth of backups, set `BACKUP_KEEP_DAYS: 7`

## Testing

Now all the config is set, you should run a test backup to confirm all the config is correct. To do that, run the following command from the folder where you have the docker compose file:

```shell
docker compose run --rm backup backup
```

If everything is ok, this will run for a few seconds, and will finish on a line similar to `upload backup file to storage system [backup/backup.<ID>.20250208.zip -> ActualBudgetBackup:/ActualBudgetBackup]`. If you check your storage system, you should now have a file called `backup.<ID>.20250208.zip` stored within there. If anything went wrong, go back and check all your env variables. If you can't work out what's gone wrong, file an issue in this repo.
