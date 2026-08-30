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
- `mct create` ignores the name and creator arguments and leaves the raw
  template on disk.
- The script takes a profile argument (`./scripts/verify.sh ci`) because the
  default profile exports to `com.mojang`, which a CI runner does not have.

## Open questions

- Should recommendations ever be promoted to failures, e.g. behind a `--strict`
  flag?
- Is there a validation suite beyond `addon` worth running?
