# Decisions

Why this project is shaped the way it is. Each entry records the decision, the
evidence behind it, and what would justify revisiting it. Add to the bottom.

---

## `packs/BP` and `packs/RP` are source, not build output

**Decided.** Earlier drafts of `AGENTS.md` described a `source/` -> `packs/`
compiler and told agents to treat `packs/` as read-only. That is not how
Regolith works.

Evidence: the Regolith docs state packs are the "source-of-truth" you edit, and
a direct test confirmed it — with `texture_list` in the profile, a run left
`packs/` byte-identical while the generated `textures_list.json` appeared only
in the export target. Regolith copies `packs/` to `.regolith/tmp`, filters the
copy, and exports from there.

Consequence: `Edit(packs/**)` must **not** be denied in
`.claude/settings.json`. The read-only side is `.regolith/`, `build/`,
`reports/`, and the `com.mojang` export target.

**Revisit if:** never, unless Regolith changes its execution model.

---

## No `source/` directory

**Decided.** Follows from the above. Adding one would mean writing a
copy-into-`packs/` step by hand, duplicating a compile stage Regolith already
provides, and giving up the export-target mechanism.

---

## `command_lang` is installed but not used

**Decided.** The filter is a thin wrapper that shells out to `cmcc`, which
`regolith install` does not provide. `cmcc` is a **paid product** — the
MCDevKit GitHub org publishes only `cmcc-docs`, no compiler repo, and the
official guide says to download it from a client panel and run
`cmcc activate <license key>` against an active subscription.

Without it the filter fails and takes the whole profile down. It stays in
`filterDefinitions` (harmless, keeps the option open) and is absent from every
profile.

**Revisit if:** someone buys a licence, or there are real `.mcc` sources to
compile. `jsonte` covers templating and is free and self-contained.

---

## Template content uses vanilla geometry

**Decided.** `packs/RP/entity/example_entity.entity.json` points at
`geometry.frog` and `controller.render.default` rather than shipping a custom
`.geo.json`.

Rationale: `AGENTS.md` forbids agents from authoring `.geo.json`, which would
otherwise make a self-contained, agent-verifiable entity template impossible
without opening Blockbench. Borrowing vanilla geometry keeps the whole template
authored and verified without human asset work. The official Regolith tutorial
uses the same trick.

**Revisit if:** the template grows a real mob. Swap geometry per-file; the rest
of the wiring does not change.

---

## Textures nest under `textures/<creator>/<gamename>/`

**Forced, not chosen.** Cooperative Add-On validation (`CADDONREQ102`, `104`,
`108`) rejects textures sitting loose in common-named folders, and permits
exactly one subfolder under the creator namespace. Hence
`packs/RP/textures/addontemplate/template/{blocks,items,entity}/`.

Found by the gate, not by reading docs: the first layout produced six errors,
the second one, the third zero.

---

## `name_ninja` uses `auto_name` rather than `name` fields

**Decided.** The filter emits an empty `.lang` unless names are supplied. Two
routes: a `name` field in each BP description, or `auto_name` per type.

Chose `auto_name` because a `name` key is not part of the vanilla BP schema,
and adding non-schema fields risks validation errors. `auto_name` derives
correct names from identifiers with no extra fields.

Note the settings are **per type** — `entities`, `blocks`, `items` and
`spawn_eggs` are separate blocks, and enabling three silently omits the fourth.

---

## Three regolith profiles

**Decided.** `default` exports to `development` (com.mojang) for local work.
`ci` is identical but exports to `local`, because CI runners have no
`com.mojang`. `build` is the same set of filters exporting to `local`, invoked
only by `scripts/deploy.sh`; it originally carried `bump_manifest`, which was
removed (see below).

`scripts/verify.sh` takes the profile as an optional argument, so there is one
gate rather than three.

---

## The verify gate checks both exit code and report contents

**Decided.** `mct validate` writes `reports/<project>.mcr.json`, counts errors
in `info.errorCount`, and marks error items with `"iTp": 3`. There is no
`"type":"error"` string anywhere in it — the obvious grep matches nothing and
passes every broken build. The same broken check was in the original CI
workflow.

`mct` does exit nonzero (4 observed), but the gate checks both so that a change
in either behaviour cannot silently turn it into a no-op.

---

## `../mcbe-schemas` lives outside the repo

**Decided.** Anything under the project root is walked by `mct validate`. With
the clone inside, scans covered 1221 files instead of 8 and emitted spurious
`Could not load biome definition` errors — mct reading biome *schemas* as biome
*definitions*. Those errors never reach `errorCount`, so the motivation is
report noise, not a false failure.

Note `mcbe-schemas/bedrock-samples` is an **uninitialised submodule** (empty).
There are no vanilla reference assets on disk.

---

## Repository stores LF; Windows working copies use CRLF

**Decided.** `.gitattributes` sets `* text=auto eol=crlf`, with `*.sh` and
`*.yml`/`*.yaml` pinned to `eol=lf`.

Shell scripts must stay LF everywhere: `bash` fails on a CR in the shebang, and
`scripts/verify.sh` runs on a Linux CI runner.

---

## `bump_manifest` is not used

**Decided, after it broke something.** The filter was added to a `build`
profile, then removed when a test run corrupted the behavior pack manifest: it
rewrote `"@minecraft/server": "2.0.0"` to `[2, 9, 0]`. Module dependencies take
semver **strings**; version arrays are for pack-UUID dependencies. The filter
does not distinguish between the two, and invented a version number in the
process. It also strips the trailing newline.

Separately, it writes into `packs/` - the documented exception to filters never
touching source, since the bumped version has to persist between builds. That
alone is manageable; silently corrupting a dependency is not.

**Revisit if:** the filter learns the difference between the two dependency
shapes, or the project stops declaring script module dependencies. Until then,
bump versions by hand at release time.

---

## mct calls are wrapped in `timeout`

**Decided, after losing an afternoon to it.** `mct create` and `mct exportaddon`
appeared to hang indefinitely - reproduced across 0.17.7 and 0.17.8, two drives,
`--offline`, a fresh dependency tree, and three invocation methods (global shim,
direct `node`, `npx`). All of that pointed at an mct bug.

It was the network. mct resolves script module dependencies
(`@minecraft/server`, `@minecraft/server-ui`) against registry.npmjs.org. A
router fault was leaving connections half-open - reachable but never completing -
so mct stalled for minutes instead of failing. `--verbose` eventually reveals it:

```
Could not load registry for '@minecraft/server': Error: read ECONNRESET
```

`--offline` does **not** suppress these lookups, despite the flag name.

So: `scripts/verify.sh` and `scripts/deploy.sh` wrap every mct call in `timeout`
(60s default, `MCT_TIMEOUT` to override) and fail with a message naming the
likely cause. `deploy.sh` additionally fails when no `.mcaddon` is produced,
rather than exiting 0 having packaged nothing.

npm's own `fetch-retry-*` settings do not help here - mct has its own registry
client and does not read npm config.

**Lesson worth keeping:** a stall that survives version, drive, install and
invocation changes is more likely environmental than a tool bug. Check the
network before concluding the tool is broken.

---

## Not yet decided

- **Whether to enable Beta APIs.** Required for GameTest. Adding a
  `@minecraft/server-gametest` dependency changes what the pack needs to load,
  so it is deliberate. See `tests/gametest/README.md`.
- **Whether the template ships a custom model.** Currently vanilla-only.
- **`format_version` policy.** Values are currently whatever the template and
  hand-authored files carry (`1.20.80` entity, `1.21.40` block/item, `1.10.0`
  client entity). No project-wide rule has been set.
