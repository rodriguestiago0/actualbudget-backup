# Notifications

The backup can send a message when it starts, succeeds or fails, to Telegram, Discord, Slack, ntfy, Gotify, Pushover, email and [many other services](https://shoutrrr.nickfedor.com/latest/services/overview/).

Notifications are sent with [Shoutrrr](https://github.com/nicholas-fedor/shoutrrr), the notification library [Watchtower](https://github.com/nicholas-fedor/watchtower) uses, so you can reuse the URLs from your `WATCHTOWER_NOTIFICATION_URL`.

For health check services such as healthchecks.io, use [ping notifications](ping-notifications.md). The two can be used together.

<br>

## Usage

| Variable | Default | Description |
| --- | --- | --- |
| `NOTIFICATION_URLS` | | One or more [Shoutrrr URLs](https://shoutrrr.nickfedor.com/latest/services/overview/), separated by spaces or new lines |
| `NOTIFICATION_ON` | `success,failure` | When to send a notification, comma separated: `start`, `success`, `failure` |

`NOTIFICATION_URLS` can also be set with `NOTIFICATION_URLS_FILE` (e.g. a Docker secret) or in the `.env` file.

Each message has a title, such as `✅ Actual Budget Backup Success`, and a text, such as `Backup finished at 2026-10-21 16:30:32 UTC. 1 budget(s) uploaded to 1 remote(s).`

A backup counts as failed when any budget fails to download or archive, or any upload fails.

URLs are checked at startup; invalid ones are logged and ignored. A notification that cannot be sent is logged but never fails the backup. The log never shows the URLs, only the service names, since URLs contain tokens.

> **Note:** If the configuration is invalid (for example no `ACTUAL_BUDGET_SYNC_ID` or no rclone remote), the container stops at startup before any backup runs, so no notification is sent.

<br>

## Examples

#### Telegram

Create a bot with [@BotFather](https://t.me/BotFather) to get its token, and send it a message so it can write to you. See the [Telegram service docs](https://shoutrrr.nickfedor.com/latest/services/chat/telegram/) to find the chat ID.

```yml
environment:
  NOTIFICATION_URLS: 'telegram://123456789:AAE-your-bot-token@telegram?chats=987654321'
```

#### Discord, only when the backup fails

```yml
environment:
  NOTIFICATION_URLS: 'discord://webhook-token@webhook-id'
  NOTIFICATION_ON: 'failure'
```

#### Several services

```yml
environment:
  NOTIFICATION_URLS: >-
    telegram://123456789:AAE-your-bot-token@telegram?chats=987654321
    ntfy://ntfy.sh/your-topic
  NOTIFICATION_ON: 'start,success,failure'
```

#### Docker secret

```yml
services:
  actualbudget_backup:
    environment:
      NOTIFICATION_URLS_FILE: '/run/secrets/notification-urls'
    secrets:
      - notification-urls

secrets:
  notification-urls:
    file: ./notification-urls.txt
```

<br>

## Testing a URL

The image includes the `shoutrrr` CLI, so you can check a URL or send a test message without running a backup:

```shell
docker run --rm rodriguestiago0/actualbudget-backup:latest shoutrrr verify -u 'telegram://...'
docker run --rm rodriguestiago0/actualbudget-backup:latest shoutrrr send -u 'telegram://...' -m 'Hello'
```

`shoutrrr generate` can build a URL step by step.
