---
name: setup
description: Create or adopt the second-brain vault and check the install
disable-model-invocation: true
---

Set up the vault for the method. Run:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup" --vault "${user_config.vault}" --plugin-root "${CLAUDE_PLUGIN_ROOT}"
```

Act on the exit code:

- **0**: the last line says `created`, `adopted` or `already set up`. If a
  `note:` line appears, pass it on to the user as is.
- **3**: the vault folder has files of its own and does not look like a
  second-brain vault. Nothing was written. Show the user the message and ask
  whether to add the vault structure alongside their files. Only on a clear
  yes, re-run the same command with `--confirm-foreign`. On no, stop and
  suggest changing "Vault folder" in `/config`.
- **4**: an old `sbm` install was found.
  **PLACEHOLDER (Task 10):** the migration step is not part of this skill
  yet. Tell the user an old install was detected, that migrating it arrives
  in a later release, and stop. Do not re-run the script.
- **2**: usage error. Show the message and stop.

If a later migration reports that the vault differs from the configured one,
tell the user to change "Vault folder" in `/config` and run
`/second-brain:setup` again.

Finish by reporting the result in plain words: where the vault is, whether it
was created, adopted or already set up, and any note that appeared.
