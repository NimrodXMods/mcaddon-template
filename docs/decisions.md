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

## `command_lang` is not used, and is not referenced

**Decided.** Removed outright. `command_lang` is a thin wrapper that shells
out to `cmcc`, a **commercially licensed product**: not open source, no
compiler repo, distributed through the mcdevkit.com client panel against an
active subscription, and activated with `cmcc activate <license key>`.
`regolith install` fetches the wrapper but never the binary, so without a
licence the filter fails and takes the whole profile down.

Originally the entry was left parked in `filterDefinitions` on the grounds
that it was harmless and kept the option open. That was reversed: this
project takes no dependency on commercial software, and a config entry
pointing at one is an invitation to re-add it. The `filterDefinitions` entry,
the seeded `packs/data/command_lang/main.mcc` stub, and the surrounding prose
were all removed.

Note nothing commercially licensed was ever committed here — `cmcc` is never
vendored, and what was present was the open-source wrapper's cached
`filter.json` plus an empty generated stub. The removal is about not
*referencing* a paid dependency, not about licence contamination.

Templating is covered by `jsonte`, which is free and self-contained.

**Revisit if:** `cmcc` becomes freely available. Re-adding it means
reinstating the `filterDefinitions` entry *and* wiring it into a profile;
until `cmcc` is on PATH and activated, doing so breaks every build.

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
`packs/RP/textures/nimrodx/template/{blocks,items,entity}/`.

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

`mcbe-schemas/bedrock-samples` **must be initialised** (`git submodule update
--init --depth 1 bedrock-samples`); it holds the vanilla reference assets this
project reads for real geometry identifiers, texture paths and component
shapes. Initialising it makes the sibling-clone decision *more* important, not
less - it adds the entire vanilla resource and behaviour pack to that tree.

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
removed. Isolation later showed the rewriter was **`mct exportaddon`**, which
converts `module_name` dependency versions from a semver string to an array
and strips the trailing newline. `bump_manifest` does not touch dependency
versions at all.

**Amended 2026-08-31: this is not corruption.** Reading mct's own source
settled it - `IAddonDependency` types `version` as `number[] | string`, and
`setModuleVersion()` deliberately converts stable 3-part versions to arrays
while preserving anything containing `-` as a string. Both forms are valid;
mct is normalizing, not breaking the file. The word "corrupted" above is left
in place because it records what was believed during the mis-attribution, and
the lesson below is about that.

This project still prefers strings, for reasons unrelated to validity: Learn
documents `{"module_name": "@minecraft/server", "version": "2.9.0"}` as the
canonical form, **manifest v3 requires a string**, and the rewrite churns
every diff. The trailing-newline strip remains a plain defect.

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

**Decided, and kept for a different reason than it was adopted.**

The original trigger was a **local router misconfiguration**, since fixed. It
left outbound connections half-open, and mct's registry lookups hung on them
rather than failing. That was a one-off fault in this environment, **not** a
standing hazard of the toolchain: do not write warnings about network stalls
into this repo, and do not diagnose a slow mct command as a network problem.

The `timeout` wrapper stays anyway, on its own merits. mct does hang for
reasons of its own - `mct create` still does, reliably, even with `-y` - and an
unbounded hang inside the completion gate is worse than a clean failure. So
`scripts/verify.sh`, `scripts/deploy.sh` and `scripts/testworld.sh` wrap every
mct call in `timeout` (60s default, `MCT_TIMEOUT` to override). `deploy.sh`
additionally fails when no `.mcaddon` is produced, rather than exiting 0 having
packaged nothing.

**Lesson worth keeping:** a failure that survives version, drive, install and
invocation changes is environmental. Suspect the box before the tool.

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

## Beta APIs: yes for testing, never in a production build

**Refined 2026-09-01.** This supersedes an earlier entry that banned
`@minecraft/server-gametest` from the template outright. The ban was aimed at
the right target - the **shipped** add-on - but it was written as a blanket
rule and so also forbade testing.

The split now is:

- **Development and testing: Beta APIs are fine.** The BP manifest declares
  `@minecraft/server-gametest` (`"1.0.0-beta"`) and the template ships two
  SimulatedPlayer tests. A test world needs the Beta APIs experiment, which
  `mct exportworld` sets on its own.
- **Production: the beta dependency and the test code both come out.** A
  released add-on must load without experimental toggles, which is what the
  original decision was protecting and still holds.

Why testing was worth it: nothing else can move a player. The retail
`/connect` bridge has no movement primitive and no Agent in retail; mct's
BDS-only `moveSessionPlayerToLocation` is a `/tp`, which repositions a player
but cannot make one walk, mine, place or use an item. `SimulatedPlayer` is the
only route to testing *player-driven* behaviour.

**The gap this leaves.** Stripping is currently **manual** - two deletions,
documented in `docs/gametest-notes.md` - which means a production build depends
on somebody remembering. That is the weak point of this decision, not the beta
dependency itself. The fix is the `gametests` Regolith TS filter: it excludes
test code from a chosen profile, so a `build`/production profile drops the
tests while `default` keeps them, and the split stops being a manual step.
Not yet installed; tracked in the open questions.

**Revisit if:** the GameTest APIs stabilise out of beta (the strip becomes
unnecessary), or the `gametests` filter gets wired in (the strip becomes
automatic).

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

## The `dash` Regolith filter is rejected

**Decided 2026-08-31.** Investigated after establishing that bridge.'s Dash
compiler has a genuinely stronger answer than jsonte to the problem this
project cares most about — keeping generated cross-file references from
drifting.

**What the filter is.** `dash` in the Bedrock-OSS resolver points at
`evilguy50/my-regolith-filters`, and it is **not** a port of Dash to Regolith.
It is a ~40-line Nim script that downloads `deno-dash-compiler` as a zip from a
hardcoded GitHub URL on first run, `deno task install:full`s it globally, shells
out to `dash_compiler build`, then **deletes `BP/` and `RP/` and moves
`builds/dist/<name> BP` over them**. A whole second compiler nested inside
Regolith, replacing the pack wholesale rather than transforming it. The two
`sleep(1000)` calls in the source are load-bearing.

**Why not.** Any one of these would be survivable; together they are not:

- **Stale by three years.** Last commit 2023-08-05, pinning Dash **0.4.5**.
  Upstream `deno-dash-compiler` is at **v1.1.1** (2026-06-02). The drift is not
  cosmetic: v1.0.1 moved default build paths to the GDK folders and v1.1.0
  rewrote path handling for Linux/Windows parity. The filter's
  `builds/dist/<name> BP` assumption was written against the old layout.
- **Two new toolchain prerequisites**, Nim *and* Deno. The `jsonte` filter
  ships prebuilt binaries and needs neither (see `docs/bedrock-jsonte-notes.md`).
- **A network fetch at filter runtime.** A build-time download is the wrong
  direction for a gate that has to run offline, and it breaks offline CI.
- **`config.json` collision.** bridge. and Regolith both use `config.json` at
  the project root. Dash demands a `compiler` key in ours, which is a bridge
  concept inside a file validated against `Bedrock-OSS/regolith-schemas`. The
  filter's `use_bridge_config` setting exists to work around exactly this.

**What we would have gained, and why it does not change the answer.** Dash's
custom components are imperative JavaScript with a context object, and calling
`animation({...})` emits the animation file, registers it under
`description/animations`, *and* wires `scripts/animate` — reference and referent
created by one call, so they cannot drift. `lootTable()`, `spawnRule()`,
`tradeTable()` and `client.create()` (which emits the **RP** client entity from
the BP file) work the same way. That is structurally stronger than what our
`.modl` modules do: the drifter variant chain keeps BP component groups, the RP
texture map and the render controller's `Array.skins` aligned by *convention* —
a shared array in `packs/data/jsonte/data.json` plus the discipline to index it
consistently.

But the principle is portable and the tool is not. **The rule worth keeping:
never let a template emit a name that something else has to remember to
reference.** `proximity_aggro.modl` already obeys it by making each component
group and the event that adds it inseparable; that is the same idea as Dash
returning its own handle. Generalising that within jsonte is cheap. Adopting
Dash is not.

**Dash also contributes nothing to logical-error detection.** Its complete
diagnostic vocabulary, confirmed by reading every `console.error` in `src/`, is:
undefined file dependency, circular dependency, plugin/component threw or has
the wrong export shape, JSON5 parse failure, and non-string entry in a command
array. No schema validation, no semantic linting. bridge.'s schemas live in
`editor-packages` and are applied by the *editor* through Monaco, never by the
compiler.

The irony worth recording: `Component.ts` contains
`findComponentGroupReferences(events, 'add'|'remove', groupName)`, which walks
`sequence` and `randomize` recursively to find every event touching a given
group. That is precisely the analysis an unreachable-group check needs, computed
and then discarded — it exists only to attach lifecycle hooks.

**Revisit if:** someone republishes a maintained Dash filter tracking v1.x, or
we decide to leave Regolith entirely. The maintained Dash entry points are
`deno-dash-compiler` invoked directly and the `bridge-core/build-mc-project`
GitHub Action — but both *replace* Regolith rather than plugging into it, which
contradicts staying close to the official tools.

---

## There is no Regolith filter that authors animations

**Decided 2026-08-31.** Checked while looking for one; recording the negative
result so it is not searched for twice.

`blockbench_convert` is the filter the model-authoring docs describe, and its
readme is explicit about scope: it converts `.bbmodel` files **into geometry
files and images**. Files named `*.entity.bbmodel` or `*.block.bbmodel` also
export textures. **Animations are not mentioned and are not converted**, even
though `.bbmodel` can carry them. It automates the geometry export step, nothing
more.

Across all **137** filters in the Bedrock-OSS resolver, the only
animation-adjacent one is `bogumidu/bedrock_bundler`, which *"bundles
animation_controllers, animations, models and render_controllers into single
files"* — a packaging convenience, not an authoring tool. Nothing generates
animation content.

So animations stay hand-authored JSON (or Blockbench exports moved in by hand),
and the one-directional handoff in `docs/model-authoring-human.md` is unchanged.

**Also spotted while enumerating the resolver**, unverified and relevant to the
open question of semantic validation: `sanity_check`, `validate`, `style_lint`,
and `extend-vanilla-entities`. None has been looked at.

---

## The gate validates compiled output; checks that can be filters, are

**Decided 2026-08-31.** Two changes made together, from one observation: the
verify gate was doing work in Bash that belonged in the pipeline, and it was
doing it to the wrong files.

**`verify.sh` validated `packs/`.** It ran `mct validate addon -i .` after
deleting `build/`, so the input was source: `.templ` and `.modl` files the game
never loads, minus every `.json` jsonte generates, which exists only in the
export target. Both entities, the drifter client entity and the render
controller were invisible to the gate. Pointing it at `build/` produced three
errors on the first run that source validation had never reported once — see
`docs/bedrock-verify-notes.md`.

This is worth stating as a rule because the failure was silent and looked like
success for weeks: **a gate that validates its inputs instead of its outputs
reports on files nobody ships.** Where a build step generates content, the
generated content is the thing to check.

**Two checks moved into filters.** `sanity_check` (MCDevKit) covers cross-file
and filesystem checks mct does not make — missing sounds referenced by
`sound_definitions.json`, missing translations across `.lang` files, folder and
file misspellings by edit distance, BOM removal, entity property type fixes. It
runs last in every profile and found a real issue on its first run.
`prune_empty_dirs` is a small local filter that removes the empty `BP/modules/`
directory jsonte leaves behind, which is what `sanity_check` had flagged.

The division that emerged, and the one to keep:

- **A filter** for anything that inspects or transforms pack content. It runs on
  the compiled copy, it is declarative in `config.json`, and it works the same
  in CI and locally.
- **The shell script** for what a filter structurally cannot do: bound a hung
  process with `timeout` (a filter cannot time itself out), clear the export
  target before the run so the deletion-safety check cannot fire, choose a
  profile, and parse the report with the multi-signal strictness the gate needs.

**Revisit if:** filters gain a timeout mechanism, in which case more of
`verify.sh` can move.

---

## The `validate` filter is not adopted, and not forked

**Decided 2026-08-31.** Considered while moving gate logic into filters, since
`MCDevKit/regolith-library`'s `validate` filter is literally `mct validate` in
the pipeline — the right shape for the split above.

Rejected on three grounds:

- **Nothing to fix.** The one capability worth having, `logOverrides` (match an
  info item on level/error code/id/file and rewrite its level), already exists.
  A fork would add nothing.
- **Forking means owning its worst part.** `main.js` reaches mct's validation
  entry point by monkey-patching a third-party module to capture an unexported
  function — it assigns `require("threads/worker").expose` and then requires
  `@minecraft/creator-tools/cli/TaskWorker.js` to trigger it. That crosses two
  package boundaries into internals and will break on mct upgrades. Given the
  creator-tools install trouble already documented in `AGENTS.md` section 2,
  this is a bad thing to take responsibility for.
- **It is weaker than what we have.** It checks only items with
  `iTp === error`. `verify.sh` additionally checks
  `internalProcessingErrorCount`, cross-checks the `iTp: 3` item count against
  `errorCount`, cross-checks mct's exit code against a clean report, and prints
  warnings and recommendations. Adopting it would loosen the gate.

**Worth stealing, not adopting:** `logOverrides` is the right answer to a
Cooperative Add-On rule that conflicts with a deliberate choice — the
`CADDONREQ108` loot-table path problem was solved by moving the file, but the
next conflict may not have a clean workaround, and the gate is currently
all-or-nothing on `errorCount`.

**Revisit if:** we need per-error suppression, in which case implement it in
`verify.sh`'s report parser rather than taking the dependency.

---

## The namespace is `nimrodx_template`, derived from `studio` + `pack`

**Decided 2026-08-31.** Forced by the gate: once it validated compiled output
instead of source, `CADDONIREQ112` (both entities) and `CADDONIREQ141` (the
drifter render controller) appeared. Cooperative Add-On requires identifiers of
the form `<studio>_<pack>:thing`, asset paths of the form `<studio>/<pack>/...`,
and render controllers named `controller.render.<studio>_<pack>`. The old
namespace was the single word `addontemplate`.

Renaming rather than suppressing, because this repo exists to model practice: a
template that ships identifiers failing the platform's own naming rules teaches
the wrong thing. `studio = nimrodx`, `pack = template`.

What moved:

- `addontemplate:*` -> `nimrodx_template:*` (identifiers, events, type families)
- `loot_tables/addontemplate/template/` -> `loot_tables/nimrodx/template/`
- `textures/addontemplate/{common,template}/` -> `textures/nimrodx/...`
- `controller.render.drifter` -> `controller.render.nimrodx_template.drifter`

**The two spellings are not interchangeable** - the namespace joins with an
underscore, the directory path with a slash - and mct enforces the *shape* of
each without being able to tell you the two halves disagree. So both are derived
from the same two words rather than written out.

### `name_ninja` does not do this, and no filter should

Checked, because it was assumed to. `name_ninja` reads identifiers and writes
**display names** into `.lang` files (`entity.<id>.name=...`), optionally
auto-generating them from the identifier. It is a *consumer* of identifiers and
never a producer. Nothing about namespaces passes through it.

The filter that does do it, `cda94581/namespace`, is **rejected**. Its own
readme lists "Keys are not changed" as a known issue - and our entity events are
JSON *keys* (`"nimrodx_template:become_aggro": {...}`), so it would rewrite the
`trigger` values while leaving the event definitions behind and silently break
every state transition. It also warns that "Molang may be messed up", requires
`json_cleaner` ahead of it, and sits at v0.0.7. Worse in principle: it would
make `packs/` hold a placeholder namespace, so source would no longer read as
what ships - directly against the decision that `packs/` is source of truth.

### Where the derivation lives, and why not in `data.json`

`studio` and `pack` are global (`packs/data/jsonte/data.json`); the joined forms
are derived in each `.templ`'s `$scope`. This is not stylistic - a global scope
value is substituted only **once**, so `"namespace": "{{studio}}_{{pack}}"`
reaches the built file as the literal string `{{studio}}_{{pack}}`. It produces
valid JSON containing an impossible path, `mct validate` passes it, and only
reading `build/` catches it. Full detail and the resolution table in
`docs/bedrock-jsonte-notes.md`.

Cost: four lines of `$scope` per template. Benefit: one place to change project
identity, and no way for the underscore form and the slash form to disagree.

**Revisit if:** jsonte resolves global scope values recursively, which would let
the derivation move back into `data.json`.

---

## Not yet decided

- **jsonte examples for blocks and items.** Required by "The template
  demonstrates both plain and templated authoring", not yet built. Entities are
  the only type with both. A block family (variants from one template) and an
  item set are the obvious candidates - and per the skill policy, a block family
  is also what `bedrock-jsonte` needs before it can become a skill.
- ~~**Running a GameTest in game.**~~ Done 2026-08-31: both SimulatedPlayer
  tests pass on the retail client, verified against a failing control. See
  `docs/gametest-notes.md`.
- **Automating the production strip.** Beta APIs are accepted for testing and
  rejected for release, but removing the dependency and the test import is a
  manual step today. Wiring the `gametests` Regolith filter into a production
  profile is what makes that automatic. This is the highest-value gap in the
  GameTest setup.
- **Whether the template ships a custom model.** Currently vanilla-only.
- **Whether the bumped entities still *behave*.** Tracked in
  `docs/test-backlog.md`. `/summon` proves they load; nothing has confirmed
  wandering, aggro, flee and loot still work at 1.26.40, and the schema
  changed under every component, not just `minecraft:pushable`.
