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
`com.mojang`. `build` is the same set of filters **plus `bump_manifest`**, exporting to
`local`, invoked only by `scripts/deploy.sh` (see the `bump_manifest` entry
below for its brief removal and reinstatement).

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

## `bump_manifest` was wrongly blamed; it is used, in the `build` profile

**Decided, after a mis-attribution.** During a packaging test run,
`packs/BP/manifest.json` came back corrupted - `"@minecraft/server": "2.0.0"`
rewritten to `[2, 9, 0]` - and `bump_manifest`, newly added to the `build`
profile and named like a thing that rewrites manifests, was blamed and
removed. Isolation later showed the corruption was **`mct exportaddon`**: it
resolves the latest registry version of each script module dependency and
writes it back as an array, where `module_name` dependencies take semver
**strings** (arrays are for pack-UUID dependencies). It also strips the
trailing newline. `bump_manifest` does not touch dependency versions at all.

So: `bump_manifest` is back in the `build` profile and release builds
increment manifest versions, while `scripts/deploy.sh` snapshots and restores
the source manifests around `exportaddon`. The filter's documented write into
`packs/` (its `packs/data/bump_manifest/version.json` state file, so bumps
persist between builds) is expected behaviour, not corruption - though note
that file has not actually changed since the initial commit, so the
state-file write itself has not been observed here.

**Lesson worth keeping:** blame was assigned to the obvious suspect before
isolation, and documented across several files before being proven wrong -
the same arc as the mct "hang" entry below. Isolate before attributing.

**Revisit if:** `mct exportaddon` stops rewriting source manifests - then the
deploy.sh snapshot/restore guard can go.

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

## Version policy: latest stable, never preview or beta

**Decided.** `min_engine_version` and `format_version` track the newest
**released** Minecraft version. Never a preview, beta, or prerelease build.

`min_engine_version` is `1.26.40` in both manifests - the value mct itself
computes as newest supported.

Earlier drafts framed this as a deliberate tradeoff against "broad
compatibility". **That framing overstated the cost.**

Bedrock network compatibility is **asymmetric**: an older client is refused by
a newer server at any version difference, while a newer client can usually join
a somewhat older server provided the gap is not too large. The pressure is
therefore one-directional - staying on an old client progressively locks you
out of multiplayer, so players update and the old-client population keeps
draining. Combined with Realms forcing updates and Marketplace content
targeting current, a high `min_engine_version` costs very little in practice.

*Provenance: this is the project owner's understanding of Bedrock networking,
including the hedge on how large a backward gap a newer client tolerates. It
has not been measured here. Recorded because it is the reasoning behind the
policy - but note the conclusion does not depend on the exact boundary. Even
if the tolerated gap were wider than assumed, the one-directional pressure on
players to update is what makes old clients rare.*

The practical upshot: **there is no meaningful reason to hold any version
back.** Target the newest released version everywhere and treat lowering it as
an unusual, justified exception rather than a normal dial.

That last clause is **no longer a prediction**. Confirmed in game 2026-08-30:
an entity declaring `format_version` 1.8.0, byte-identical to a working one in
every other respect, silently lost `minecraft:environment_sensor` while keeping
everything else - and `mct validate` passed it with 0 errors. The practical
rule is therefore simply **author new content at the newest released
`format_version`**, per numbering line, and treat "one component does nothing"
as a version symptom first. See `docs/bedrock-entity-notes.md`.

**Do not use `mct fix setnewestminengineversion` to apply this.** It is a
no-op that reports success - it prints "Updated 2 min_engine_version(s)" and
returns `{"updatedCount": 2}` from `--json` while leaving the file byte-for-byte
identical (verified by md5 on 0.17.8). `setnewestformatversions` reports "No
format versions to update" on files that are demonstrably behind. Set both by
hand and confirm with `git diff`. `mct fix randomizealluids` *does* write, so
the defect is per-fix, not a general property of `mct fix`.

Content `format_version` values are currently mixed (`1.20.80` entity,
`1.21.40` block/item, `1.10.0` client entity) - each valid, none yet
deliberately chosen. Bumping one changes component semantics, so raise them
per-file when touching that file, not in a sweep.

---

## No Beta APIs in the base template

**Decided.** The template assumes production. The BP manifest depends only on
`@minecraft/server` and `@minecraft/server-ui`, both stable; no
`@minecraft/server-gametest`, and the test world does not enable the Beta APIs
experiment.

The cost is that GameTest cannot run against the template as shipped. That is
accepted: a beta dependency changes what the pack requires to load, and a
template that cannot be shipped to production is worse than one that cannot
self-test. Enabling Beta APIs is a decision made **at instantiation**, per
project, not inherited from the template.

**Revisit if:** the GameTest APIs stabilise out of beta.

---

## Skills are written after the work, not before

**Decided.** A `bedrock-<thing>` skill is only written once a *real* example of
that thing has been authored end to end - designed, built, validated, and
confirmed in game. Until then, notes accumulate in `docs/<thing>-notes.md`.

The reason is this project's own history: nearly every durable rule here came
from something failing in a way no amount of upfront reasoning predicted - the
invisible item's `minecraft:icon` shape, the Cooperative Add-On texture layout,
`exportaddon` rewriting manifests, `mct fix` lying about success. A skill
written before that experience would have encoded plausible guesses, which is
worse than no skill, because it reads as authoritative.

The lifecycle:

1. Author the thing for real. Keep notes in `docs/<thing>-notes.md` as you go -
   especially the failures and the things that were not obvious.
2. When the notes stop growing on the next example of the same thing, they have
   converged.
3. Convert `docs/<thing>-notes.md` into `.claude/skills/bedrock-<thing>/SKILL.md`.

`AGENTS.md` section 8c lists the planned skills. That is a roadmap, not an
inventory.

---

## Entity reuse goes through jsonte modules, not a custom filter

**Decided.** Shared entity structure is authored as jsonte `$module`
definitions in `packs/BP/modules/`, composed by `$extend` from a `.templ`, and
parameterised by `$scope`. No custom Regolith filter, no code generator.

The alternatives considered were a JS/TS generator script and a repo-local
Regolith filter. Both were rejected for the same reason: they would sit outside
or alongside the filter chain the project is already built on, and they lock in
a spec format before we know what actually varies between mobs. jsonte was
already installed, is self-contained, and its module system is a direct answer
to the problem.

The binding rule is in `AGENTS.md` section 4: **a module owns a whole state
machine or none of it.** The specific failure being designed out is a component
group that no event adds — dead code that neither the engine nor `mct validate`
reports. Modules that emit the closed loop make it unrepresentable.

**Revisit if:** a mob needs structure that is genuinely per-file rather than
shared, or if `$scope` parameterisation stops being expressive enough and
templates start carrying conditional logic that would read better as code.

---

## `system_template` is rejected — superseded by its own author

**Closed, 2026-08-30.** An earlier draft of this file deferred `system_template`
as a promising follow-up. That was based on its introduction page; the rest of
its docs 404'd at the time and were never read.

It is **superseded**. ModularMC's documentation describes itself as "a
TypeScript-based successor to the System Template filter," and the commit
record agrees: `system_template`'s last commit is **2025-03-27**, seventeen
months before this was checked, while `modular_mc` was active as of
**2026-06-05**.

Do not re-open this. If the file-grouping idea is ever revisited, the candidate
is `modular_mc`, evaluated below.

---

## jsonte is retained over `modular_mc`

**Decided 2026-08-30, after building and reverting a working probe.**

`modular_mc` was installed, the `stalker` was moved into a
`data/modular_mc/stalker/` module with a `_map.ts`, and the full gate was run.
**It worked** — the two filters coexist if `modular_mc` runs first, placing the
`.templ` into `BP/entities/` for jsonte to expand. The probe was then reverted.

Stacking them is not the intended design, and the probe was never meant to
ship: `modular_mc` bundles its own JSON Template, JSON merge, text templates and
esbuild, so it **overlaps jsonte** rather than complementing it. It can do what
`proximity_aggro.modl` does, via several sources merging into one target with
`onConflict: "merge"`. So the real choice is either/or.

What decided it:

| | jsonte | modular_mc |
| --- | --- | --- |
| Runtime | self-contained Go binary | needs Deno |
| `mct validate` coverage | full | **loses files moved into modules** |
| Reference safety | `$extend: ["name"]` — a **string** | `_resource_map.ts` — a **typed import** |
| Verified here | yes, in game | seam only |
| Public projects using it | 1 (`r4isen1920/OriginsPE`) | 0 found |
| Stars | 8 | 6 (whole repo) |

The `mct validate` loss is the decisive one. Files inside a `modular_mc` module
are no longer classified as content by mct — measured: the content count fell
17 → 16 when one `.entity.json` moved out of `packs/RP/`. Since `verify.sh`
deletes `build/` before mct runs, such files end up validated **nowhere**. In a
project whose central discipline is that gate, that is a permanent reduction in
coverage, traded for grouping that pays off only at many entities.

`modular_mc`'s typed imports **are** genuinely better than jsonte's string
`$extend`, which silently stops resolving if a module is renamed. That is a
known weakness of the current approach, recorded rather than solved.

**Revisit if:** there are several mobs each with grouped BP+RP+texture+sound
assets, or `modular_mc` shows real adoption. Any revisit must also answer how
the verify gate keeps covering module files — most likely by validating the
build output instead of `packs/`.

---

## Tool selection criterion: prefer what the official tools understand

**Decided 2026-08-30.** The standing test for any new layer in the toolchain:

> **Does it keep source files in the shape the official tools expect?**

`mct` classifies content by its pack-relative location - `packs/BP/entities/…`
is an entity, a file in `packs/data/…` is not. Any layer that *relocates source
out of that shape* pays a permanent tax: everything it moves silently drops out
of `mct validate`, and the verify gate - this project's central discipline -
quietly covers less than it appears to.

This is the general rule behind three decisions already made here:

- jsonte over `modular_mc`. jsonte expands **in place**: a `.templ` lives at
  `packs/BP/entities/` and becomes a `.json` there. `modular_mc` moves source
  into `data/`, and the content count fell 17 → 16 the moment one file did.
- `packs/` is source, not build output.
- `../mcbe-schemas` lives outside the repo, so mct does not walk it.

Judge the next candidate layer against this directly rather than re-deriving it.
A layer that is *more* capable but *less* legible to mct is the trade this
project declines by default - and the burden is on the new layer to show how the
gate keeps its coverage.

---

## The template demonstrates both plain and templated authoring

**Decided 2026-08-30.** Every content type should ship **two** worked examples:
one using only Regolith standard-library filters, and one using jsonte.

The reason is the decision above. jsonte is a defensible local choice, not a
Bedrock standard, and someone adopting this template may reasonably refuse any
non-standard layer. They should be able to delete jsonte from the profiles, copy
the plain example, and have a working project - without first reverse-engineering
which parts were jsonte-specific.

Current state - **entities only**:

| Type | Plain (standard filters) | jsonte |
| --- | --- | --- |
| Entity | `example_entity` - literal JSON | `stalker` - `.templ` + two `.modl` modules |
| Block | `example_block.json` | **missing** |
| Item | `example_item.json` | **missing** |

Blocks and items have no templated counterpart yet. That gap is the open work
this decision implies.

**Caveat, and it matters:** the two paths are separable at the *authoring*
level, not the *config* level. Removing jsonte from the profiles while a
`.templ` still exists would copy it unexpanded into the pack, where Minecraft
ignores it and mct would likely flag it. "Use the plain path" means authoring
literal JSON, not disabling the filter with templates still present. Whether mct
actually errors on a stray `.templ` has not been tested.

---

## Neither templating tool is "standard"; skills must not depend on one

**Decided 2026-08-30.** Checked while choosing between jsonte and
`modular_mc`, because this repo exists to establish practices worth teaching.

There is no dominant standard in this category:

- The Bedrock-OSS **standard library** (`Bedrock-OSS/regolith-filters`) holds
  twelve filters — `blockbench_convert`, `bump_manifest`, `filter_tester`,
  `fix_emissive`, `gametests`, `json_cleaner`, `json_convert`, `name_ninja`,
  `qjs_opt`, `texture_convert`, `texture_list`, `type_gen`. **jsonte is not
  among them**, and neither is `system_template` or `modular_mc`.
- Searching the whole `Bedrock-OSS/regolith` repo (compiler and its autodocs)
  for "jsonte" returns **zero** hits. The docs' only install example is
  `regolith install name_ninja`.
- The Bedrock-OSS filter **resolver** lists all of them, but it is a flat
  name→URL map with no curation, no categories and no deprecation markers.
  Appearing there is not endorsement.
- Both candidates are effectively single-maintainer projects in single digits
  of stars.

So jsonte is chosen as the *least bad* option, not the winner — and
`system_template` failing to become standard across three major versions is
evidence the category may never consolidate.

**The rule this implies:** a `bedrock-<thing>` skill teaches **Bedrock
semantics**, never tool syntax. Component groups are states and events are
transitions in plain JSON, under jsonte, and under any successor; that
knowledge outlives the toolchain. Templating syntax stays quarantined in
`bedrock-jsonte`. `docs/` already splits this way — `bedrock-entity-notes.md`
versus `bedrock-jsonte-notes.md` — and that separation is now deliberate, so
replacing the templating layer costs one skill rather than all of them.

---

## Not yet decided

- **jsonte examples for blocks and items.** Required by "The template
  demonstrates both plain and templated authoring", not yet built. Entities are
  the only type with both. A block family (variants from one template) and an
  item set are the obvious candidates - and per the skill policy, a block family
  is also what `bedrock-jsonte` needs before it can become a skill.
- **Whether to enable Beta APIs.** Required for GameTest. Adding a
  `@minecraft/server-gametest` dependency changes what the pack needs to load,
  so it is deliberate. See `docs/gametest-notes.md`.
- **Whether the template ships a custom model.** Currently vanilla-only.
- **Bringing existing files up to the `format_version` policy.** Not a question
  of *whether* - the policy is decided and, with version-locked multiplayer,
  there is no compatibility argument for holding back. Purely a question of
  *when*. The files lag: `min_engine_version` is `1.26.40` while BP entities
  declare `1.20.80` and block/item `1.21.40`, so anything added to those
  formats since is silently unavailable - a failure now *confirmed*, not
  theorised.

  Bumping is not clerical. It **exposes components that were being dropped**,
  which is a behaviour change to a mob that was just verified in game, so it
  needs its own verify pass and playtest. Do it as an isolated change: bumping
  while the spawn-rule question is still open would put two variables in flight
  at once.

  The numbering lines are independent - BP entity, RP client entity (`1.10.0`)
  and spawn rules (`1.8.0`) each track their own. **Spawn rules are correct at
  1.8.0**; that is what current vanilla still declares. This is not a
  find-and-replace.
