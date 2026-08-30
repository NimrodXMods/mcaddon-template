# Regolith pipeline notes

**Planned skill:** `bedrock-regolith`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-regolith/SKILL.md` only after the pipeline has been reshaped at least once for real needs - a custom filter, or a non-trivial profile. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

The filter pipeline, profiles, export targets, and the source/output
direction.

## Confirmed lessons

- **`packs/BP` and `packs/RP` are source, not output.** Regolith copies them to
  `.regolith/tmp`, filters the copy, and exports to the target. It never writes
  back. Do not deny writes to `packs/`.
- Two things do write into `packs/`: `bump_manifest` (its `version.json` state
  file - expected) and `mct exportaddon` (rewrites dependency versions
  incorrectly - guard it).
- `regolith install <filter> --profile=default` wires the filter into the
  profile. **Without `--profile` you get a populated `filterDefinitions` and an
  empty profile** - filters downloaded, pinned, and never run.
- `--profile` only works on first install. Afterwards install refuses and
  suggests `--update`, which re-resolves and can bump pins. Edit `config.json`
  by hand instead; the docs endorse this.
- Profiles differ only by export target: `default` -> `com.mojang`,
  `ci`/`build` -> `local`. CI runners have no `com.mojang`.
- `.regolith/` is gitignored, so CI needs `regolith install-all` before running
  anything - the filter cache does not exist on a fresh checkout.
- `command_lang` needs `cmcc`, a paid product. Not used here.
- `regolith run <profile>` selects a profile; bare `regolith run` uses
  `default`.
- The `local` export target writes into `build/` **inside the project**, which
  `mct validate` then scans alongside `packs/` and double-counts. Clear it
  before validating.
- Filter settings are per-filter and easy to under-specify: `name_ninja` needs
  separate `entities` / `blocks` / `items` / `spawn_eggs` blocks, and enabling
  three of the four silently omits the fourth.
- `name_ninja`'s `language` setting is deprecated in favour of `languages`,
  which takes a list.
- Regolith names the export folder from `config.json`'s `name`, so a
  placeholder name ships packs called "Project name_bp" into `com.mojang`.

## Open questions

- Writing a custom filter (Python or Node) - none written yet.
- `filterDefinitions` version pinning strategy over time.
- Whether `dataPath` is worth using for more than filter state.
