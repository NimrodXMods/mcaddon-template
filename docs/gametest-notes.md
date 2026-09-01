# GameTest

**Status: not wired up.** Notes and drafts, per the skill policy in
`docs/decisions.md` - no test runs yet. One thing here is real and committed:
the fixture `packs/BP/structures/nimrodx_template/example.mcstructure`, built
from `docs/fixtures/example.volume.json`. The remaining gap is the
`@minecraft/server-gametest` manifest dependency; see the blockers section.

## Where GameTests actually live

Not here. GameTest scripts ship **inside the behavior pack**, because the game
loads them from the pack at runtime:

```
packs/BP/
  scripts/
    main.js                   # the manifest's script entry point
                              #   ("entry": "scripts/main.js"); imports every
                              #   test file
    gametests/
      ExampleTests.js
  structures/
    nimrodx_template/
      example.mcstructure     # built by `mct buildstructure`, see below
```

Wiring a test into `packs/BP/scripts/main.js` - the actual entry point named
by the manifest - is what makes it run. Per the
skill policy in `docs/decisions.md`, these notes become
`.claude/skills/bedrock-gametest/SKILL.md` once GameTests have actually been
authored and run against real content.

## The `gametests` *filter* is a different thing from the GameTest *API*

Do not conflate them. This file is about the API - `@minecraft/server-gametest`,
`register`, `.mcstructure` fixtures. The Regolith filter called `gametests` is
a **TypeScript build filter**: it transpiles TS to JS with esbuild and controls
what lands in the output, which is how test code gets excluded from a
production build. It is not required to run a GameTest, and it is useful even
if you never write one. See `docs/bedrock-regolith-notes.md`.

## Blockers before any test can run

Two were recorded here. Only one is real.

### 1. Structures - NOT a blocker. An agent can build them.

This file previously claimed a `.mcstructure` "can only be produced in game"
and "an agent cannot author one." **That is wrong.** `mct buildstructure`
writes a `.mcstructure` from a JSON block-volume description, no game and no
structure block required. Verified on mct v0.17.8; the file committed at
`packs/BP/structures/nimrodx_template/example.mcstructure` was produced this
way, from `docs/fixtures/example.volume.json`.

```bash
npx mct buildstructure <volume>.json packs/BP/structures/<ns>/<name>.mcstructure --overwrite
```

`--preview <path.png>` renders a preview in the same pass; `mct renderstructure
<file>.mcstructure <out.png>` renders one after the fact. Add `--isolated` to
skip the vanilla texture download - the geometry still renders, untextured.

The input is an **IBlockVolume**, and its layer ordering is the part that is
easy to get backwards:

- `blockLayersBottomToTop` - outer array is **Y, bottom to top** (ground floor
  first, roof last).
- Each layer is an array of strings, one per **Z row, north to south**.
- Each character in a string is an **X position, west to east**.
- `key` maps a character to `{ "typeId": "minecraft:stone" }`, optionally with
  `"properties": { "facing": "north" }` for block states. Space is air.
- `southWestBottom` is required: the world position of the south-west-bottom
  corner.
- `size` is **optional** and inferred from the data. Rows and strings do not
  have to be uniform length - short strings and missing rows become air.
- `entities` is optional: `[{ "typeId": ..., "locationWithinVolume": {x,y,z} }]`.

A 5x5 stone pad with three layers of headroom - enough for the example test,
and the exact contents of `docs/fixtures/example.volume.json`:

```json
{
  "southWestBottom": { "x": 0, "y": 0, "z": 0 },
  "blockLayersBottomToTop": [
    ["SSSSS", "SSSSS", "SSSSS", "SSSSS", "SSSSS"],
    ["     ", "     ", "     ", "     ", "     "],
    ["     ", "     ", "     ", "     ", "     "],
    ["     ", "     ", "     ", "     ", "     "]
  ],
  "key": {
    "S": { "typeId": "minecraft:stone" },
    " ": { "typeId": "minecraft:air" }
  }
}
```

The file path determines the identifier: `structures/<namespace>/<name>.mcstructure`
in the BP is referenced as `<namespace>:<name>`, so the file above is
`nimrodx_template:example` - which is what `.structureName()` in the template
below expects.

The MCP server exposes the same capability as `designStructure` (validate,
build, save into the project, return a preview) and `designModel`. The CLI is
the one to prefer per the harness rule in `CLAUDE.md`: do not architect around
the MCP server.

**Still human-only:** capturing a structure that already exists *in a world*.
Building a fixture from a description is now an agent task; copying a build out
of a save still means a structure block and `com.mojang/structures/`.

### 2. Beta APIs and the gametest module - still a real blocker, but only half of it

The world half is handled for you. `mct exportworld` always writes
`experiments: { gametest: 1 }` into the exported `level.dat` - a GameTest world
is what the command produces by definition. The `--betaapis` / `--no-betaapis`
flags are **inert here**: exporting with each and diffing the two `level.dat`
files leaves exactly one byte different, the `LastPlayed` timestamp. Do not
reach for those flags to control this; they matter on the world/deploy paths,
not on `exportworld`.

Untested, and worth checking the first time a world is actually loaded: the
export leaves `saved_with_toggled_experiments: 0` and `experiments_ever_used: 0`
alongside `gametest: 1`. If the game refuses the experiment or nags on load,
those two are the first suspects.

The manifest half is **not** handled. `packs/BP/manifest.json` still depends
only on stable `@minecraft/server` and `@minecraft/server-ui`; nothing adds
`@minecraft/server-gametest`. Until that dependency exists the exported world
loads and the tests simply are not there. **The base template deliberately
leaves it out** - it assumes production, and enabling Beta APIs is a per-project
decision made at instantiation. See `docs/decisions.md`.

Note also that adding that dependency makes the mct network stall more likely,
because mct resolves script module dependencies against `registry.npmjs.org`.
That is what `MCT_TIMEOUT` is for.

### `mct ensureworld` writes nothing

Run bare, `mct ensureworld` prints `Created world at '<repo>\out'` and then
leaves no files on disk - `find out -type f` comes back empty and `git status`
is clean. Do not trust that message. The command that actually produces a world
file is `exportworld` (see the next section for the right invocation), which
writes a real `.mcworld` - a zip containing:

```
level.dat, level.dat_old, levelname.txt
world_behavior_packs.json + world_behavior_pack_history.json
world_resource_packs.json + world_resource_pack_history.json
behavior_packs/<pack>/...  <- copied from the -i folder, INCLUDING structures/
resource_packs/<pack>/...
```

It picks up `structures/`, so a `buildstructure` fixture ships with no extra
wiring. What it packs depends entirely on `-i`, which defaults to the working
directory - meaning bare, it packs `packs/` **source, not the Regolith build
output**. Point it at `build/` instead.

### Point it at `build/`, not at source

Bare `exportworld` defaults `-i` to the working directory, which is why it
packs `packs/` and why it edits your source manifest. Both `-i` and `-o` work,
and using them fixes both problems at once:

```bash
npx mct -i build -o build/worlds exportworld
# -> build/worlds/build.mcworld
```

- **`-i build`** packs the **Regolith build output**. Verified: the exported
  world then contains the templated `drifter`/`stalker` entities, the generated
  `render_controllers/`, `texts/en_US.lang` and `textures/textures_list.json`
  - none of which exist in `packs/` - and still carries
  `structures/nimrodx_template/example.mcstructure` through. Run `regolith run`
  (or `scripts/verify.sh`) first; `-i build` on a stale `build/` exports stale
  content without complaint.
- **`-o <dir>`** chooses the output directory when `--of` is omitted. The
  filename is not configurable: it is `<basename of -i>.mcworld`, so `-i build`
  gives `build.mcworld`. Use `--of <path>` for an exact filename; `--of` wins
  over `-o`.
- The world's in-game name is also derived from the input folder basename -
  `-i build` produces a world called **"build World"**. There is no flag for
  it. `mct world set` adjusts an existing world's settings (`--betaApis`,
  `--behaviorPack`, `--resourcePack`) but not its name.

**`--if <file>` also works** - point it at a `.mcaddon`/`.mcpack` and it
exports a world containing those packs. It is the worse option here: the
pack folder names get a suffix doubled (`AddOnTemplate_bp_bp`), the world is
named after the file (`tpl.mcaddon World`), and the output picks up a double
extension (`tpl.mcaddon.mcworld`). Prefer `-i build`.

Since `build/` is gitignored and `scripts/verify.sh` removes it before and
after every run, a world written to `build/worlds/` is deliberately ephemeral -
regenerate it rather than treating it as an artifact.

### `exportworld` mutates the manifest of whatever `-i` points at

It rewrites `manifest.json` in place, converting the `module_name` dependency
versions from `"2.9.0"` to `[2, 9, 0]` and dropping the trailing newline. Run
bare it therefore edits **`packs/BP/manifest.json`, your source** - check
`git status` and revert. Using `-i build` confines the rewrite to derived
output, where it does not matter; that is a second reason to prefer it.

This collides directly with test-backlog item 6, which asks whether the game
accepts that array form for script-module dependencies at all. If it does not,
mct's own export quietly breaks the scripts it just packed.

### Loading the exported world

Double-click the `.mcworld`, or copy the unzipped tree into a folder under
`com.mojang/minecraftWorlds/`. Per memory, the live
`com.mojang` is under `%APPDATA%\Minecraft Bedrock\...`, not the UWP
`LocalState` tree.

## Template

```javascript
import { register } from "@minecraft/server-gametest";

register("ExampleTests", "entitySpawns", (test) => {
  test.spawn("nimrodx_template:example_entity", { x: 1, y: 2, z: 1 });
  test.assertEntityPresentInArea("nimrodx_template:example_entity", true);
  test.succeed();
})
  .maxTicks(100)
  .structureName("nimrodx_template:example");
```

Conventions worth keeping: class names `PascalCase`, test names `camelCase`
reading as a sentence, structure names `snake_case`. One behavior per test -
if it needs ten assertions, split it. Keep `maxTicks` at the minimum that
passes; a generous budget hides performance regressions.

Run with `/gametest run ExampleTests:entitySpawns`, or `/gametest runset
ExampleTests` for the class.
