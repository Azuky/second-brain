# Second Brain for Claude Code

> A Claude Code plugin that gives [Claude Code](https://claude.com/claude-code)
> persistent memory. Install it once and every session **resumes where you left
> off**, without re-explaining anything.

Claude Code remembers nothing between sessions. This plugin keeps a "second
brain" on your disk, a **vault** (a plain folder you can also open in
[Obsidian](https://obsidian.md)), where the state of each project and
everything you learn is written down.

## What you get

- **Skills** that load and save your context with discipline:
  `/second-brain:start`, `:close`, `:learn`, `:gate`, `:kickoff`,
  `:new-project` and `:setup`.
- A **vault** with the method's templates and guides, one folder per project.
- **Guard hooks** that inject the working rules at session start, remind you to
  close a session properly, check that delegated briefs carry evidence, and
  (optionally) record metrics. Every hook fails open: a problem never blocks
  your session.
- Two **agents**, `second-brain:implementer` and `second-brain:tester`, for
  delegated implementation and testing.
- **Safety rules**: no git commits/pushes or deletions without your explicit
  approval, and secrets are never read or stored.

## Install

Inside Claude Code:

```
/plugin marketplace add Azuky/second-brain
/plugin install second-brain@azuky
/second-brain:setup
```

`/second-brain:setup` creates (or adopts) your vault and checks the install.
The vault location is the plugin's `vault` option (default `~/second-brain`). Set it in `/config` (edit and save it; the
default shown there is not saved until you edit it), restart Claude Code, then
run `/second-brain:setup`.
Setup is safe to re-run: it reports "already set up" instead of duplicating
anything.

### Requirements

- **macOS / Linux**: `bash` and `git` (already there on most systems).
- **Windows**: install [Git for Windows](https://gitforwindows.org/). The hooks
  run through Git Bash; if it is missing they exit silently and do nothing.
- **`jq`** is optional. It is only used for metrics (`hooks/metrics-event`,
  `/second-brain:close` telemetry, the metrics scripts) and for the sbm
  migration. Without it those parts are skipped quietly.

## Migrating from `sbm`

Earlier versions were installed with the `sbm` CLI, which copied commands,
hooks and a `CLAUDE.md` block into `~/.claude`. The plugin replaces it.

If an old install is still present, the session-start hook says so, and
`/second-brain:setup` detects it and offers the migration. It shows exactly what
would be removed and what is kept (files you edited stay), asks for **one
confirmation**, backs everything up, then removes the old hooks, commands and
`CLAUDE.md` block, and renames the vault's old `method/` to `method.sbm-old/`.
Your projects and notes are never touched. Running it again says there is
nothing to migrate.

## Privacy

Your brain is **local**. The method never stores secret values (tokens,
passwords): it only records the *names* of variables and where to get them.
If you sync your vault to a git remote, review it before making it public.

## Development

```bash
bash tests/run-all.sh          # every tests/test-*.sh and tests/check-*.sh
claude plugin validate --strict .
```

CI runs the suites on macOS, Ubuntu and Windows (Git Bash) and validates the
manifest with the real Claude Code CLI. The plugin ships without an icon by
design, so `ICON_MISSING` is the one validation warning tolerated.

`legacy/` holds the frozen Spanish sources of the old installer, kept for a
possible future Spanish edition. It is not shipped.

## Credits

- Based on the second-brain method by
  [csaavedras](https://github.com/csaavedras/second-brain-method), the upstream project this
  plugin grew out of.
- The cross-platform hook launcher (`hooks/run-hook.cmd`) is adapted from
  [superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT).

## License

MIT. Use it, adapt it and share it.
