# Ping notifications

The backup can call a URL when it starts, succeeds or fails. Use it with health check services such as [healthchecks.io](https://healthchecks.io/) or [Uptime Kuma](https://github.com/louislam/uptime-kuma), or with notification services such as [ntfy](https://ntfy.sh/) and other webhooks.

The variables are the same as in [vaultwarden-backup](https://github.com/ttionya/vaultwarden-backup#ping), so existing configurations can be reused.

For chat and push services such as Telegram, Discord or Pushover, [notifications](notifications.md) are easier to set up.

<br>

## Usage

| Variable | Sent when |
| --- | --- |
| `PING_URL` | the backup finishes, whether it succeeded or failed |
| `PING_URL_WHEN_START` | the backup starts |
| `PING_URL_WHEN_SUCCESS` | the backup succeeded |
| `PING_URL_WHEN_FAILURE` | the backup failed |

Each one has a matching `*_CURL_OPTIONS` variable (e.g. `PING_URL_WHEN_FAILURE_CURL_OPTIONS`) with extra [curl options](https://curl.se/docs/manpage.html), for example to send a `POST` body or headers.

Pings are sent with `curl -m 15 --retry 10 --retry-delay 1 -fsS`. A failed ping is logged but never fails the backup.

Like the other variables, they can also be set with a `_FILE` suffix or in the `.env` file. The log only shows which pings are set, not their URLs, since URLs often contain tokens. Set `PING_DEBUG: 'TRUE'` to print the full curl commands.

A backup counts as failed when any budget fails to download, is corrupt, fails to archive or can't be read back from its archive, or when any upload fails. Old backups that can't be deleted don't make it fail; they send a [`warning`](notifications.md) instead. The container exits with status `1` when the backup failed.

> **Note:** If the configuration is invalid (for example no `ACTUAL_BUDGET_SYNC_ID` or no rclone remote), the container stops at startup before any backup runs, so no ping is sent. Health check services detect this through the missing ping.

<br>

## Placeholders

The URL and the curl options can contain these placeholders:

| Placeholder | Example |
| --- | --- |
| `%{subject}` | `Actual Budget Backup Success` |
| `%{content}` | `Backup finished at 2026-10-21 16:30:32 UTC. 1 budget(s) uploaded to 1 remote(s).` |

In URLs, the text is percent-encoded, e.g. a space becomes `%20`. In curl options it is passed as is, as one argument: it is never read by the shell, so quotes and `$` in it are safe.

The URL is passed to curl on its standard input (`-K -`), so it doesn't show up in `ps`. Curl options can't read from standard input too, e.g. `-d @-`.

<br>

## Examples

#### healthchecks.io

```yml
environment:
  PING_URL_WHEN_START: 'https://hc-ping.com/your-uuid/start'
  PING_URL_WHEN_SUCCESS: 'https://hc-ping.com/your-uuid'
  PING_URL_WHEN_FAILURE: 'https://hc-ping.com/your-uuid/fail'
```

#### ntfy

```yml
environment:
  PING_URL_WHEN_FAILURE: 'https://ntfy.sh/your-topic'
  PING_URL_WHEN_FAILURE_CURL_OPTIONS: '-d "%{content}" -H "Title: %{subject}" -H "Priority: high" -H "Tags: warning"'
```

#### Any URL, on every run

```yml
environment:
  PING_URL: 'https://example.com/notify?subject=%{subject}&message=%{content}'
```
