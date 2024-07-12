# Multiple sync ids - WIP

Some users want to backup multiple budget.

You can achieve this by setting the following environment variables.

<br>



## Usage

To set additional remote destinations, use the environment variables `ACTUAL_BUDGET_SYNC_ID_N` where:

- `N` is a serial number, starting from 1 and increasing consecutively for each additional budget.

Note that if the serial number is not consecutive or the value is empty, the script will break parsing the environment variables for sync ids.

<br>

#### Example

```yml
...
environment:
  # they have default values
  ACTUAL_BUDGET_SYNC_ID: 'random-guid'
  ACTUAL_BUDGET_SYNC_ID_1: 'random-guid-1'
  ACTUAL_BUDGET_SYNC_ID_2: 'random-guid-2'
  ACTUAL_BUDGET_SYNC_ID_4: 'random-guid-4'
...
```

With the above example, both sync_ids will be backup: `random-guid`, `random-guid-1` and `random-guid-2` but not the `random-guid-4`.
