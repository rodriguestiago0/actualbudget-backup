# Several budgets

To back up more than one budget from the same Actual server, add numbered sync IDs next to `ACTUAL_BUDGET_SYNC_ID`, starting at `_1`:

```yaml
environment:
  ACTUAL_BUDGET_SYNC_ID: 'first-sync-id'
  ACTUAL_BUDGET_SYNC_ID_1: 'second-sync-id'
  ACTUAL_BUDGET_SYNC_ID_2: 'third-sync-id'
```

The numbers must follow each other: reading stops at the first missing one, so with `_1` and `_3` only, `_3` is ignored. The log lists every budget it found.

Each budget is saved as its own file, `backup.<sync id>.<date>.zip`. If one budget fails, the others are still uploaded and the backup is reported as failed.

For encrypted budgets, see [encrypted budgets](e2e-encrypted-backups.md). Budgets on different Actual servers need a backup container each.
