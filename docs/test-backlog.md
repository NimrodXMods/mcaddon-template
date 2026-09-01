# Test backlog

Manual tests that are built, deployed and gate-clean, but not yet confirmed in
game. Batched deliberately: a playtest costs a context switch, so it is cheaper
to accumulate several and run them in one session than to stop after each
change.

**Lifecycle.** Add an item here the moment something ships unverified. After a
playtest, move the *result* into the relevant `docs/bedrock-*-notes.md` and
delete the item from this file. This file only ever holds what is outstanding -
if it starts accumulating history, it has stopped doing its job.

Each item states what to do, and what each outcome would mean. An item whose
outcomes are not written down is not ready to test: "see if it works" produces
observations that cannot be interpreted later. Two tests in this project have
already been invalidated by that - see the notes on the vanilla-texture
lookalike and the aggro-vs-flee ambiguity.

## Before any session

- **`/reload all`**, not `/reload`. Plain `/reload` reloads functions and
  scripts only, not entity/block/item definitions or textures.
- **`domobspawning` must be `true`** for anything spawn-related. A test world
  created with mob spawning off silently defeats every spawn rule.
- **Difficulty above peaceful**, or no monster spawns at all.
- **Restart Minecraft first if you intend to read the Content Log.** The log
  accumulates across a whole session, the GUI never clears and strips
  timestamps, and file writes are buffered. See `docs/bedrock-verify-notes.md`.

---

## 1. Drifter colour variants  (highest - wholly unverified content)

`/summon nimrodx_template:drifter` several times, or use the spawn egg.

The whole chain is untested end to end: `randomize` -> `minecraft:variant` ->
`query.variant` -> `Array.skins[...]` -> texture. It is also the first custom
render controller and the first templated RP files in this project.

| Outcome | Means |
| --- | --- |
| A mix of azure / amber / violet / jade checkerboards | the whole chain works |
| All one colour | `randomize` is not firing, or the guard filter is wrong |
| All the same *wrong* colour | `query.variant` resolves but the array order is off |
| Magenta or invisible | texture paths or the render controller are broken |

Also confirm they wander, and drop leather on death.

## 2. Stalker behaviours after the format_version bump  (regression check)

The bump to 1.26.40 broke both entities outright until `minecraft:pushable` was
migrated. `/summon` proves they **load**; nothing has confirmed they still
**behave**, and the schema changed under every component, not just that one.

Re-confirm all four: wanders when ignored, aggros within ~4 blocks, flees when
hit, drops bone/string on death. Any single failure is a removed or altered
component, and the Content Log will name it.

## 3. Does the flee timer restart on a second hit?

Hit a fleeing stalker again, wait, and see whether it flees for a further full
5s or finishes the original countdown.

Known already: re-firing `flee` while fleeing is a safe no-op (it removes two
absent groups and adds one already present). Unknown: whether re-adding a group
that is already present **restarts** its `minecraft:timer`. If it does, repeated
hits can pin a mob in flee indefinitely, which is a design consideration for any
timer-based state.

## 4. `example_entity` collision box vs its model  (cosmetic)

`example_entity` still declares a 1x1 collision box while rendering
`geometry.zombie.v1.8`, which is ~1.9 tall. Confirmed already: the collision box
does **not** affect ground placement - that comes from the geometry origin - so
this is a hitbox/model mismatch, not a floating model. Check whether it is
actually noticeable when hitting it; if so, set 1.9 x 0.6.

## 5. `environment_sensor` version cutoff  (low - only if it matters)

Established: it is dead at `format_version` 1.8.0 and alive at 1.20.80. The
upper bound was never measured and both probes have been deleted.

To redo: copy `stalker.behavior.templ`, change only `format_version`, bisect.
Worth doing only if the exact cutoff ever becomes load-bearing - the general
rule ("author at the newest released version") does not depend on it.

## 6. Does Minecraft accept the array form for `module_name` dependencies?

Reading mct's source established that **both** forms are legal *to mct*:
`IAddonManifest.d.ts` types the dependency as `version: number[] | string`, and
Learn's manifest reference agrees. Neither of those is the game. This project
prefers strings anyway (manifest v3 requires them), so the question is not which
to use - it is whether the array form mct normalizes to would actually load,
because that determines how urgent the `deploy.sh` snapshot-and-restore guard is.

To test: hand-edit `packs/BP/manifest.json` to `"version": [2, 9, 0]` for
`@minecraft/server`, deploy, and load a world with the pack enabled. Note this
deliberately bypasses `scripts/deploy.sh`'s manifest restore - use
`regolith run` directly, and restore the string form afterwards.

| Outcome | Means |
| --- | --- |
| Pack loads, scripts run | Both forms work; the restore guard is cosmetic hygiene, not a correctness fix |
| Pack loads, scripts silently dead | The array form parses but breaks module resolution - the worst case, and the reason to test |
| Pack fails to load, Content Log names the manifest | The array form is invalid to the game despite mct and Learn; the guard is load-bearing |

Read the **Content Log** either way - a scripting failure will not announce
itself in the world.

## 7. Does an `.mcaddon` accept nested `.mcpack` / `.mcworld` archives?

Learn's glossary calls `.mcaddon` *"a zip file that contains .mcpack or .mcworld
files"*, but the archive `mct exportaddon` actually produced here held **46
entries and zero nested archives** - directory trees only, each pack a top-level
folder with its own manifest. One of the two is wrong about what the importer
accepts, and the glossary comes from the same prose that got `minecraft:icon`
wrong.

To test: build two `.mcpack` files by hand, zip them into a `.mcaddon`, and
import it. This is a build-and-import test, not an in-world one.

| Outcome | Means |
| --- | --- |
| Both packs import | The glossary is right and `.mcaddon` is a general meta-importer; the working hypothesis in `docs/bedrock-packaging-notes.md` holds |
| Import fails or silently installs nothing | The glossary is wrong; `.mcaddon` is strictly directory trees, and `mct exportaddon`'s output is the only correct shape |
| Only one imports | Ordering or manifest-collision behaviour worth its own note |

If nested archives *do* work, the follow-on questions in the packaging notes
become worth answering: whether one `.mcaddon` can hold two packs of the same
type, and whether it can contain a `.mctemplate`.

---

## Build-time checks - no playtest needed

These need only `./scripts/verify.sh` and a look at the output, so they can be
cleared without entering the game.

- **Does jsonte error or silently skip an unresolvable `$extend`?** Rename a
  `.modl` without updating the reference. `$extend` resolves by string, so a
  silent skip would mean renaming a module quietly drops its contents - the one
  place `modular_mc`'s typed imports are genuinely better. Recorded as a known
  weakness in `docs/bedrock-jsonte-notes.md`; the severity depends on this
  answer.
- **What does mct do with a stray `.templ`?** Remove jsonte from a profile
  while a `.templ` exists and run the gate. Determines whether "use the plain
  path" is a safe instruction or a trap - see the "both plain and templated
  authoring" decision.
- **Does `name_ninja` omit the spawn egg if only `entities` is enabled?** Set
  `spawn_eggs.auto_name: false`, rebuild, read the generated `.lang`. This is
  the last unverified inherited claim in `docs/bedrock-entity-notes.md`.
