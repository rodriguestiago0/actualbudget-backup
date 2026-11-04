# Contributing

## Tests

```shell
bats test/*.bats
shellcheck scripts/*.sh test/e2e/run.sh .github/scripts/*.sh
docker build -t actualbudget-backup:ci . && test/e2e/run.sh actualbudget-backup:ci
```

## Releases

Every push to `main` that changes the image (`Dockerfile`, `.dockerignore`, `package.json`, `package-lock.json`, `scripts/`) or the systemd units (`systemd/`) is released automatically, as the next patch version by default. The release notes list those changes only.

To change that, put a marker in the **pull request title**. GitHub copies the title into both merge commits and squash commits, which is where the release reads it from (only `main`'s own commits are read, not the commits inside a PR):

| Marker | Effect |
| --- | --- |
| `[minor]` | Bump the minor version, e.g. for a new setting |
| `[major]` | Bump the major version, for a change that needs users to act |
| `[skip release]` | Don't release this change on its own; the next release includes it |

A new minor or major version of `@actual-app/cli` always bumps at least the minor version.
