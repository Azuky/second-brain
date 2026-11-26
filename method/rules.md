# Personal working method

## Brain
- All method state lives in the vault (see Paths below).
- Current project state: `<vault>/projects/<project>/`; the exact path is
  given by each repo's `CLAUDE.local.md`.

## Always-active rules
- Task that modifies code → never the native `EnterPlanMode`; plan with
  superpowers and get human approval before touching files. Large (several
  sessions or >~5 steps): `superpowers:brainstorming` (design spec) then
  `superpowers:writing-plans`. Brief: `superpowers:writing-plans` only.
  Saved specs/plans start with frontmatter `type: spec`/`type: plan` + `date:`;
  skip superpowers' "commit the spec" step.
  Save the spec in
  `<vault>/projects/<project>/specs/<YYYY-MM-DD>-<task>-design.md` and the
  plan in `<vault>/projects/<project>/plans/<YYYY-MM-DD>-<task>.md`, never in
  superpowers' default `docs/superpowers/`.
- Never `git add` / `commit` / `push` / `checkout` without explicit approval.
- Never `rm` / `rmdir` / `mv` on files not created in the same session.
- Feature/fix on its own branch (`feat/<topic>`, `fix/<topic>`), never
  directly on `main`/`master`. Creating the branch also requires approval.
- Design decisions: always with the human present. No one decides downward.
- Secrets: never read or record values of tokens/credentials — only the
  names of variables and where to obtain their values.

## Context and delegation
- Convention docs: read on demand only the ones relevant to the task
  (index in the repo's `CLAUDE.local.md`), never all of them up front.
- The main session **orchestrates**: it holds the context and the decisions,
  and **delegates the changes**. Choose by goal (not by habit): search →
  **Explore**; implement → **`second-brain:implementer`**; tests →
  **`second-brain:tester`**; diff review → **`/code-review`**. The subagents
  are **generic-role** and detect the repo's stack — conventions live in its
  `CLAUDE.local.md`. Briefs carry acceptance criteria + 0–2 skills from
  `SKILLS-REGISTRY.md` in the method docs.
- Code destined for a commit/MR → `/second-brain:gate` on the integrated diff;
  only a READY verdict enables leaving the commit message (detail in the
  gate skill).
- Model by use (Explore→by thoroughness · Implementer→Sonnet ·
  Reasoner→Opus): every delegable task goes to the **cheapest model that
  solves it well** (detail in `MODEL-ROUTING.md` and `MULTI-AGENT.md` in the
  method docs). Explore inherits the session model, so always pass `model`:
  quick → `haiku`, medium → `sonnet`, very thorough → `opus`.
- Explore delegation (standing instruction: it overrides the default "don't
  spawn agents unless asked"): reading/searching beyond one targeted lookup
  (more than ~2 files, more than ~3 searches, or any "how does X work") →
  delegate to Explore. Only a single grep or one known file stays inline.
  The brief carries what the session knows (Explore sees no conversation).
- Verify the subagent's report before considering the task done. In the
  `/second-brain:start` report, name which skill/role and which model will be
  used.

## Sessions
- Open a session: `/second-brain:start`. Close each task or the session:
  `/second-brain:close` — mandatory before moving to the next task or stopping.
- Model and effort are fixed when opening; changing them mid-way **invalidates
  the cache** → do it at the `/second-brain:close`→`/second-brain:start` break.
  Context pruning and detail in `MODEL-ROUTING.md` in the method docs.
