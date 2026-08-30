# jsonte templating notes

**Planned skill:** `bedrock-jsonte`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-jsonte/SKILL.md` only after templates are actually generating content - a block family or a mob variant set. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

`.templ` syntax, modules, and when to template versus write literal JSON.

## Confirmed lessons

- The filter is **self-contained**: it ships `jsonte.exe` / `jsonte-mac` /
  `jsonte-linux` and needs no separate install (unlike `command_lang`).
- It scopes **both** `data/jsonte` and `data/json_templating_engine`. A
  `Skipping non-existent scope file` warning for whichever you do not have is
  benign - do not rename your data folder chasing it.
- Filter order matters: jsonte must run before anything that scans the expanded
  output (`texture_list`, `name_ninja`).
- Expanded output exists only in the export target, never in `packs/`. A
  `packs/` diff shows what you wrote, not what the game loads.
- jsonte needs Java 11+ as a standalone CLI, but the Regolith filter uses a
  bundled platform binary - so a Regolith-only workflow needs no Java on the
  machine or in CI.

## Open questions

- `.templ` syntax in practice - nothing templated yet.
- Modules, and when they beat copy-paste.
- Where the line is between templating and just writing the JSON.
