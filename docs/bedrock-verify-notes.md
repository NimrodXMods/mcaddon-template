# Verify gate notes

**Planned skill:** `bedrock-verify`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-verify/SKILL.md` only after the gate has survived a few real content types. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

Running `scripts/verify.sh`, reading the report, and never claiming done
without a clean run.

## Confirmed lessons

### Clear the export target before running, not only after

Regolith refuses to overwrite a file in the export target that it did not
create:

```
[+]: Deletion safety check for resource pack failed.
[+]: File is not on the list of files created by Regolith.
  >> Path: blocks.json
```

The underlying cause is **not** the stale directory itself: it is
`.regolith/cache/edited_files.json`, regolith's record of what it wrote into
each export target. Without that record regolith will not overwrite an export
it can no longer prove it owns. `regolith clean` wipes it, so a `local`-target
`build/` surviving a clean becomes untouchable. Full detail in
`docs/bedrock-regolith-notes.md`.

`scripts/verify.sh` originally ran `regolith run` first and `rm -rf build out`
afterwards, so the cleanup only happened when a run *completed*. That left the
gate dependent on whatever ran before it, and it failed with the message above
- which reads like content corruption and is nothing of the sort.

The gate now clears the target **before** running as well, so it does not
depend on whatever ran before it. Keep both cleanups: the one before guarantees
a clean export, the one after keeps `mct validate` from scanning `build/`
alongside `packs/` and double-counting everything.


### Validate the compiled output, not `packs/`

**Changed 2026-08-31.** The gate ran `mct validate addon -i .` with `build/`
deleted, which meant it validated **`packs/` - the source**. That is the wrong
input in both directions:

- `packs/` holds `.templ` and `.modl` files the game never loads and mct cannot
  interpret as content.
- The `.json` that jsonte generates from them exists **only in the export
  target**, so every templated file was invisible to the gate - both entities,
  the drifter client entity, and the render controller.

The gate now runs `mct validate addon -i build`. The effect was immediate: three
errors appeared that source validation had never once reported, all of them in
generated files.

```
[CADDONIREQ112] (/AddOnTemplate_bp/entities/drifter.behavior.json)
  JSON namespaced identifier is not in the expected form of
  creatorshortname_projectshortname:myitem: addontemplate:drifter
[CADDONIREQ112] (/AddOnTemplate_bp/entities/stalker.behavior.json)
[CADDONIREQ141] (/AddOnTemplate_rp/render_controllers/drifter.render_controllers.json)
  Resource pack render controller name section is not in the expected form of
  controller.render.creatorshortname_projectshortname: controller.render.drifter
```

These were not new breakage - they had been latent since the entities were
written, and were invisible only because the gate inspected `.templ` source
instead of the compiled `.json`. They are Cooperative Add-On requirements, the
same family as the `CADDONREQ108` loot-table path error, and they say the
namespace must be `<studio>_<pack>`. Ours was the single word `addontemplate`.

**Fixed the same day** by renaming the namespace to `nimrodx_template` and the
asset directories to `nimrodx/template/`; see `docs/decisions.md`. The gate is
green again. Keep the error text above: it is the only worked example of what
this class of failure looks like, and it is the evidence for validating output
rather than source.

Two consequences of the switch:

- **The report filename changed.** It is named from the *input folder*, so it is
  now `reports/build.mcr.json` rather than `reports/<project>.mcr.json`. The
  gate globs `reports/*.mcr.json`, so this did not break it - which is exactly
  why the rule below says glob rather than hardcode.
- **A profile that does not export locally cannot be validated.** The
  `development` target installs straight into `com.mojang` and leaves nothing in
  `build/`. `verify.sh` detects the target from `config.json` and, when it is
  not `local`, runs the `ci` profile a second time purely to materialise
  something to validate. Same filters and same content - only the destination
  differs - so what gets validated is what the development target deployed.

### The gate does not cover `format_version`, and the Content Log does

`mct validate` reported **0 errors** on an entity that could not load in game
at all, and on another whose component was silently dropped. Both were
`format_version` mismatches (see `docs/bedrock-entity-notes.md`). A clean
`verify.sh` therefore says nothing about whether components match the declared
schema, in either direction.

The only place that failure surfaces is Minecraft's **Content Log**:

```
C:/Users/<user>/AppData/Roaming/Minecraft Bedrock/logs/ContentLog<date>_1.txt
```

Reading it, in the order that actually works:

- A log file spans a whole **game session** and is appended to across
  `/reload all`, so it accumulates. One here reached **15 MB / 138k warnings**
  from a single already-fixed item. **Restart Minecraft to roll a fresh log**
  before drawing conclusions - otherwise you are reading history.
- Slice from the reload marker forward rather than grepping by timestamp:
  `awk '/<HH:MM:SS>\[Scripting\]\[verbose\]-Plugin Discovered/{f=1} f' <log>`.
- Then filter the noise: `grep -viE "\[(inform|verbose)\]"`. What remains is
  real. `[Sound][inform]-No sound found for block type 'normal'` is constant
  engine chatter, not your content.
- `[Actor][error]-... failed to load from JSON` is the line that matters most;
  it means the entity does not exist in game at all.

**The Content Log GUI and the file are not the same thing.** The GUI is a
session-long **accumulator that never clears**, and it **strips timestamps**.
Read it after fixing something mid-session and it will still show the failure
you just fixed, with nothing to indicate the entry is stale. Observed here: a
`minecraft:pushable` error from a world load at ~11:40 was still displayed
after the fix was deployed at 11:42 and reloaded at 11:43. The **file** keeps
timestamps (`11:35:04[Log][error]-…`), which is the only way to date an entry.

Two further traps in the file:

- Writes are **buffered**. A quiet session can leave the file at **0 bytes**
  while the GUI shows content - confirmed with `stat`, `wc -c`, a forced copy
  and PowerShell's `Get-Item.Length` all reporting 0. The old log's last entry
  was stamped 11:35:04 while its mtime was 11:38:32, a ~3.5 minute lag. **An
  empty log proves nothing**; quit Minecraft to flush the handle.
- Only the **first** parse error per entity is reported. Fixing it can uncover
  a second. After a schema-level change, re-check rather than assuming one fix
  was the whole problem.

The fastest confirmation that an entity actually loads is not the log at all -
it is `/summon <identifier>`. That proves it parsed; it does **not** prove its
behaviours survived.

**After any `format_version` change, read the Content Log before believing the
change worked.**

- The report is `reports/<project>.mcr.json`, named from the **project folder**,
  not `reports/info.json`. Glob it; do not hardcode.
- Errors live in `info.errorCount` and as items with `"iTp": 3`. There is no
  `"type":"error"` string - grepping for one matches nothing and the gate
  passes on a broken project.
- `info.errorSummary` is the human-readable list. Use it in output.
- `mct validate` exits nonzero (4 observed) but the gate checks exit code *and*
  report counts, so a change in either cannot silently disable it.
- Measuring the exit code through a pipe gives you the pipe's status, not mct's.
- `out/` is mct's own default output directory; delete it first or it gets
  scanned too and inflates every count. (Deleting `build/` before *validating*
  was correct only while the gate validated `packs/`; it is now the thing being
  validated. It is still cleared before the regolith *run* - see the deletion
  safety note above.)
- `behaviorPackManifestCount` / `resourcePackManifestCount` read `0` even on a
  healthy project. Not a health signal. `errorCount` is.
- Recommendations (`iTp: 6`) and `warningCount` never reach `errorCount`; print
  them as non-fatal notes or they are invisible.
- Wrap mct in `timeout` - it resolves script module deps against the npm
  registry and a half-open network stalls it for minutes.
- **The gate does not validate component payloads.** A malformed component
  reports zero errors. Only loading the pack in game catches that.

- `mct validate addon -i packs` also works and catches the same errors, but
  reports paths without the `packs/` prefix. `--threads` defaults to 8, caps
  at 16.

### Filters now carry part of the gate

Two filters were added 2026-08-31, moving checks off the shell script and into
the pipeline where they see the compiled pack:

- **`sanity_check`** (MCDevKit, `runWith: python`, 1.1.0) - cross-file and
  filesystem checks mct does not make: missing sound files referenced by
  `sound_definitions.json`, missing translations across `.lang` files,
  Levenshtein-based folder/file misspelling detection, duplicated recipe IDs,
  BOM removal, and entity property `range`/`default` type fixes. Defaults are
  `fail_on_errors: true`, `fail_on_warnings: false`, so everything it currently
  emits is advisory. Runs last in every profile, per its own readme.
  **Caveat:** its `duplicated_recipe_ids` check is dead code upstream - it only
  calls `recipe_ids.add(id)` inside the duplicate branch, so the set is never
  populated and no duplicate can be detected. Do not rely on it.
- **`prune_empty_dirs`** (local, `filters/prune_empty_dirs.py`) - removes empty
  directories from the built packs. Written because `sanity_check` immediately
  and correctly flagged `BP/modules`, the empty folder jsonte's `--remove-src`
  leaves behind. Fixing the cause beat disabling the check: a warning on every
  build is how a team learns to ignore warnings.

`sanity_check` finding a real issue on its first run is the argument for it.

## mct behaviour the gate has to work around

- `mct validate` is fast - about 7 seconds here. Anything from mct running for
  minutes is a **network stall**, not slow validation: it resolves script
  module dependencies against registry.npmjs.org, and a half-open connection
  hangs it. `--offline` does **not** suppress those lookups. Hence `timeout`
  and `MCT_TIMEOUT`.
- `mct fix setnewestminengineversion` is a **no-op that reports success**. It
  prints "Updated 2 min_engine_version(s)" and returns `updatedCount: 2` from
  `--json` while the file stays byte-identical (md5-verified on 0.17.8).
  `setnewestformatversions` claims "No format versions to update" on files that
  are demonstrably behind. `randomizealluids` does write, so the defect is
  per-fix, not general - check each one.
- `mct exportaddon` rewrites `packs/BP/manifest.json`, converting script module
  dependency versions from semver strings to arrays. `scripts/deploy.sh`
  snapshots and restores the manifests around it.
- The script takes a profile argument (`./scripts/verify.sh ci`) because the
  default profile exports to `com.mojang`, which a CI runner does not have.

## Open questions

- Should recommendations ever be promoted to failures, e.g. behind a `--strict`
  flag?
- Is there a validation suite beyond `addon` worth running?
