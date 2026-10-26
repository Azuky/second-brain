---
name: setup
description: Create or adopt the second-brain vault and check the install
disable-model-invocation: true
---

Set up the vault for the method. Run:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup" --vault "${user_config.vault}" --plugin-root "${CLAUDE_PLUGIN_ROOT}"
```

Run it exactly as written; do not expand or rewrite `~` (the script expands
it).

Act on the exit code:

- **0**: the last line says `created`, `adopted` or `already set up`. If a
  `note:` line appears, pass it on to the user as is.
- **3**: the vault folder has files of its own and does not look like a
  second-brain vault. Nothing was written. Show the user the message and ask
  whether to add the vault structure alongside their files. Only on a clear
  yes, re-run the same command with `--confirm-foreign`. On no, stop and
  suggest changing "Vault folder" in `/config`.
- **4**: an old `sbm` install was found. Migrate it, with one confirmation:
  1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/migrate-sbm" --claude-home "$HOME/.claude" --vault "${user_config.vault}" --plan`
     and show the user its output as is. It lists what would be removed, what
     is kept because the user edited it, the settings and `CLAUDE.md` changes,
     and the vault `method/` rename. Nothing is written yet.
  2. Act on the exit code of `migrate-sbm` (these codes belong to
     `migrate-sbm`, not to the setup script):
     - **0**: ask ONCE whether to apply it, and say a backup is kept. On no,
       stop: nothing changed. On yes, compute `ts=$(date -u +%Y%m%dT%H%M%SZ)`
       and run the same command with
       `--apply --backup-dir "${CLAUDE_PLUGIN_DATA}/migration-backup/$ts"`
       instead of `--plan`. If `${CLAUDE_PLUGIN_DATA}` came through empty or
       still literally unexpanded, use
       `--backup-dir "$HOME/.second-brain-migration-backup/$ts"` instead
       (never a folder inside the vault or inside `~/.claude`). If that exits 0, re-run the setup command above,
       report the result in plain words and tell the user to restart Claude
       Code so the old hooks stop loading.
     - **5**: the old install used a different vault than "Vault folder". Show
       the message (it names the old path), tell the user to set "Vault
       folder" in `/config` to that old path, then run `/second-brain:setup`
       again. Stop.
     - **6**: `jq` is not installed, so the migration cannot run
       automatically. Show the manual list it printed and stop.
     - **1**: there was nothing to migrate. Say so and re-run the setup
       command above.
     - **2** or **7**: show the message and stop (7 names the path that could
       not be written).
  Quote every path.
- **8**: the "Vault folder" setting is empty (it was never saved). Tell the
  user in plain words: open `/config`, edit and save "Vault folder" (the
  default shown there is not saved until it is edited), restart Claude Code,
  then run `/second-brain:setup` again. Stop.
- **2**: usage error. Show the message and stop.
- **1**: the script could not write the vault folder or a file in it (the
  message names the path). Nothing is reported as done. Tell the user in plain
  words which path failed and suggest checking its permissions or changing
  "Vault folder" in `/config`, then stop.

Finish by reporting the result in plain words: where the vault is, whether it
was created, adopted or already set up, and any note that appeared.
