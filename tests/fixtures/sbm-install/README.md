# sbm-install fixture

A frozen capture of a real `sbm install --yes` (sbm 4.1.0, English), used by
`tests/test-migrate.sh` and `tests/test-setup.sh` after the `sbm` installer was
removed from the repo. Source commit of the installer: `8f69f4f`
(branch `feat/plugin`).

## Layout

- `claude-home/` — the captured claude-home: `commands/`, `agents/`, `hooks/`,
  `settings.json`, `CLAUDE.md`, `.second-brain/config.json`, `.second-brain/manifest.json`.
- `vault/` — the captured vault files: `method/`, `.gitignore`, `00-index/home.md`.
- `materialize <claude-home> <vault>` — recreates the tree at the given paths.

Sandbox paths were replaced by `@@CLAUDE_HOME@@` and `@@VAULT@@` (file contents
and manifest keys). `config.json` `repo` is set to `/path/to/second-brain-method`.
`materialize` substitutes the placeholders and recomputes manifest shas only for
entries whose content changed through substitution (CLAUDE.md uses the inner-block
sha, same algorithm as `scripts/migrate-sbm`), so unedited files look exactly like a
fresh sbm install. It also creates the empty vault dirs sbm makes
(`00-index briefs learning/{til,concept} patterns projects`). No `jq` needed.

## Capture procedure (only needed if the fixture must be regenerated)

From a checkout of `8f69f4f` (the last commit that still has `sbm`):

```bash
S="$(mktemp -d)"; mkdir -p "$S/home"
HOME="$S/home" CLAUDE_HOME="$S/ch" bash sbm install --yes --vault "$S/vault" </dev/null
F=tests/fixtures/sbm-install; mkdir -p "$F/claude-home" "$F/vault"
SUB="s#$S/ch#@@CLAUDE_HOME@@#g; s#$S/vault#@@VAULT@@#g; s#$PWD#/path/to/second-brain-method#g"
(cd "$S/ch" && find . -type f) | while read -r f; do
  mkdir -p "$F/claude-home/$(dirname "$f")"
  sed "$SUB" "$S/ch/$f" > "$F/claude-home/$f"; [ -x "$S/ch/$f" ] && chmod +x "$F/claude-home/$f"
done
(cd "$S/vault" && find method -type f) | while read -r f; do
  mkdir -p "$F/vault/$(dirname "$f")"
  sed "$SUB" "$S/vault/$f" > "$F/vault/$f"; [ -x "$S/vault/$f" ] && chmod +x "$F/vault/$f"
done
```

Verification used when it was created: re-run `sbm install` into a fresh sandbox,
`materialize` into the same paths, `diff -r` both trees: identical except
`.second-brain/config.json` (`repo` is a fixed placeholder and `installed_at` is the capture time). The vault, including `.gitignore`, `00-index/home.md` and the `git init`-ed `.git`, compared identical (`diff -rq`). Also captured: `vault/.gitignore` and `vault/00-index/home.md`; `materialize` runs `git init -q` in the vault when git is available.
