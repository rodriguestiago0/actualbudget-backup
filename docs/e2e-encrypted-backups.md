# Encrypted budgets

Budgets with Actual's [end-to-end encryption](https://actualbudget.org/docs/getting-started/sync/#end-to-end-encryption) are backed up with their encryption password:

```yaml
environment:
  ACTUAL_BUDGET_E2E_PASSWORD: 'your-encryption-password'
```

> **Note:** The backup is **not** end-to-end encrypted. Like Actual's own export, it contains the decrypted budget, because Actual can only import unencrypted files. To protect the backups, set a [`ZIP_PASSWORD`](configuration.md#archive) or use an [rclone crypt](https://rclone.org/crypt/) remote. After restoring, turn encryption on again in Actual's settings.

<br>

## Several budgets

With [several budgets](multiple-sync-ids.md), each `ACTUAL_BUDGET_E2E_PASSWORD_N` belongs to `ACTUAL_BUDGET_SYNC_ID_N` with the same number. Leave it out for a budget that is not encrypted:

```yaml
environment:
  ACTUAL_BUDGET_SYNC_ID: 'not-encrypted'
  ACTUAL_BUDGET_SYNC_ID_1: 'encrypted'
  ACTUAL_BUDGET_SYNC_ID_2: 'also-encrypted'
  ACTUAL_BUDGET_E2E_PASSWORD_1: 'password-1'
  ACTUAL_BUDGET_E2E_PASSWORD_2: 'password-2'
```
