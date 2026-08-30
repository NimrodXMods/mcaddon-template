# CLAUDE.md

## What this file is

`AGENTS.md` is the source of truth for working in this repo, for every agent
including Claude. Read it first. It covers the toolchain, the repo layout, the
authoring rules, and the verify gate.

This file holds **only what is specific to Claude Code as a harness** — things
that would be meaningless or wrong for a different agent. Everything else
belongs in `AGENTS.md`.

## Rules for maintaining these two files

- **Claude may write here**, but only content that does not apply to other
  agents. If a fact is true for any agent working on Bedrock add-ons, it goes
  in `AGENTS.md` instead.
- **Non-Claude agents must treat this file as read-only.** Do not edit it.
- **Duplicate as little as possible.** Repeat something from `AGENTS.md` only
  where this file would otherwise be incoherent, and link rather than restate.
- When a correction applies to both, fix `AGENTS.md` and leave this file
  pointing at it.

## Claude Code specifics for this repo

**Permissions** live in `.claude/settings.json` (committed) with machine-local
MCP enablement in `.claude/settings.local.json` (not committed). The shape:

- *allow* — the verify loop runs unprompted: `regolith run`, `mct validate`,
  `mct info`, the render commands, `mct fix`, read-only git, and
  `./scripts/verify.sh`.
- *ask* — anything mutating project identity or history prompts first:
  `git commit`/`push`, `mct create`/`set`/`add`, the export commands.
- *deny* — `mct deploy`/`deploytestworld`, the derived directories
  (`.regolith/`, `build/`, `reports/`), and `.geo.json` / `.bbmodel` / `.png`
  matched **by extension, not directory**, so `packs/RP/` stays writable.

Note `packs/**` is deliberately **not** denied — it is source. See `AGENTS.md`,
repo-structure section 1.

Settings are read at session start. After editing them, restart the session (or
`/config`) before expecting the new rules to apply.

**Interactive commands cannot be driven from the Bash tool.** It runs
non-interactive with stdin closed, so anything that prompts will hang until it
times out. Known cases here: `mct eula`, and `mct create` without `-y`. Hand
these to the user to run with the `!` prefix in the prompt, e.g.
`! npx mct eula`, so the output lands in the conversation.

Separately, `mct create` hangs *even with* `-y` — that is an mct defect, not a
harness limitation, and is documented in `AGENTS.md` section 3b.

**MCP**: `.mcp.json` wires the `minecraft-creator-tools` server (`mct mcp`).
Confirm it with `/mcp`. It is a convenience for structured project
introspection, not a dependency — the real verify loop is
`./scripts/verify.sh` through the Bash tool. Do not architect around the MCP
server.

**Context7**: the claude.ai Context7 connector is available in this harness
for prose documentation lookups. The library IDs live in the "Canonical
documentation" table in `AGENTS.md` — they are plain Context7 identifiers,
not Claude-specific; only the connector wiring is. This does not change the
schema rule: `../mcbe-schemas/` stays the authority for component shapes,
and observed behaviour recorded in `AGENTS.md`/`docs/` beats any
documentation.

**Skills**: `.claude/skills/` currently contains only `minecraft-gametest`.
The seven `bedrock-*` skills listed in `AGENTS.md` section 8c are a roadmap,
not an inventory — do not assume one exists because it is named there.

**Long-running commands**: `regolith run` and `mct validate` finish in
seconds. If an mct command exceeds ~30s it has almost certainly hung rather
than gotten slow; run it under `timeout` and judge success by its output files,
not its exit status.
