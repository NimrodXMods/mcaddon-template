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
- Delete `build/` and `out/` first - mct scans them and doubles every count.
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
