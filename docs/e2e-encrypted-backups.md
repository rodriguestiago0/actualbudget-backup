# End-to-end Encrypted Backups

End-to-end encrypted backups are now supported. If you have specified a key in ActualBackup's End-to-end Encryption settings, they will be backed up successfully.
<br>

**NOTE:** Similarly to ActualBackup's Export feature, if you back up an end-to-end encrypted file, it is backed up **without encryption**. This is because Actual Backup does not support importing encrypted backups - the database files must be in an unencrypted zip file for successful import.

If it is necessary that these files remain encrypted, consider a per-file encryption solution, such as an rclone crypt remote.

After you import your backup, you will have to set a new key to enable end-to-end encryption again.


<br>

## Usage
If you are backing up a single E2E backup, use the environment variable `ACTUAL_BUDGET_E2E_PASSWORD` to set the same password used in ActualBackup.

To set additional passwords for different sync targets, use the environment variables `ACTUAL_BUDGET_E2E_PASSWORD_N` where:

- `N` is a serial number, starting from 1 and increasing consecutively for each additional password.

Note that if the serial number is not consecutive or the value is empty, the script will break parsing the environment variables for E2E_PASSWORD ids.

This means that if you are backing up a mixture of budgets where some are encrypted and some are not, you must still specify a `ACTUAL_BUDGET_E2E_PASSWORD_N` value for budgets that do not use an E2E password. You can use any value (such as 'null') but there must be something there or parsing will break.

<br>

#### Example

```yml
...
environment:
  # they have default values
  ACTUAL_BUDGET_SYNC_ID: 'encrypted-random-guid'
  ACTUAL_BUDGET_SYNC_ID_1: 'encrypted-random-guid-1'
  ACTUAL_BUDGET_SYNC_ID_2: 'random-guid-2' (NOT ENCRYPTED)
  ACTUAL_BUDGET_SYNC_ID_3: 'encrypted-random-guid-3'
  ACTUAL_BUDGET_E2E_PASSWORD_: 'password'
  ACTUAL_BUDGET_E2E_PASSWORD_1: 'password-1'
  ACTUAL_BUDGET_E2E_PASSWORD_2: 'anything except empty'
  ACTUAL_BUDGET_E2E_PASSWORD_3: 'password-3'
  
...
```

With the above example, even though `ACTUAL_BUDGET_SYNC_ID_2` identifies a budget which is not encrypted, `ACTUAL_BUDGET_E2E_PASSWORD_2` must still be a non-empty value.
