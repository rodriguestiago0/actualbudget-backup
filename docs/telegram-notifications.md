# Telegram notifications

The backup can send a Telegram message when it starts, succeeds or fails.

```
✅ Actual Budget Backup Success
Backup finished at 2026-10-21 16:39:49 UTC. 1 budget(s) uploaded to 1 remote(s).
```

<br>

## Setup

1. Open a chat with [@BotFather](https://t.me/BotFather), send `/newbot` and follow the steps. It gives you a **bot token** such as `123456789:AAH...`.
2. Send any message to your new bot, or add it to the group that should receive the notifications.
3. Open `https://api.telegram.org/bot<token>/getUpdates` in a browser and look for `"chat":{"id":...}`. That number is your **chat ID**. Group IDs are negative, e.g. `-1001234567890`.
4. Add both to your compose file:

```yml
environment:
  TELEGRAM_BOT_TOKEN: '123456789:AAH...'
  TELEGRAM_CHAT_ID: '-1001234567890'
```

Run a [manual backup](manually-trigger-a-backup.md) to check that the message arrives.

<br>

## Environment variables

| Variable | Description | Default |
| --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather. Supports `TELEGRAM_BOT_TOKEN_FILE` for Docker secrets. | |
| `TELEGRAM_CHAT_ID` | Chat, group or channel to send to. | |
| `TELEGRAM_THREAD_ID` | Topic ID, for groups with topics enabled. | |
| `TELEGRAM_NOTIFY_ON` | Comma-separated events to notify on: `start`, `success`, `failure`. | `success,failure` |
| `TELEGRAM_API_URL` | Bot API server, if you run your own. | `https://api.telegram.org` |

To only be told when something goes wrong, set `TELEGRAM_NOTIFY_ON: 'failure'`.

A backup counts as failed when any budget fails to download or archive, or any upload fails. A failed Telegram message is logged with Telegram's error (e.g. `chat not found`) but never fails the backup. The bot token is never written to the log.

Telegram can be combined with the [ping notifications](ping-notifications.md).
