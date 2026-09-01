# GameTest

**Status: wired up and passing in game.** The manifest declares
`@minecraft/server-gametest`, `packs/BP/scripts/gametests/ExampleTests.js`
registers two SimulatedPlayer tests, and `main.js` imports them.

**Both passed in game on 2026-08-31**, on the retail Win32 client, in a world
built by `scripts/testworld.sh`. `template:simulated_player_walks` and
`template:simulated_player_breaks_block` each showed a green beacon, and a
deliberately-failing control showed red - so the green ones mean something.
That confirms the whole chain: the beta module resolves, `register()` runs,
the fixture places, a SimulatedPlayer spawns, walks, aims and mines.

Running a test is still a **human step**: it means typing `/gametest run` in
the world. The `/connect` bridge exposes no command tool, so nothing outside
the game can trigger one - though the *result* is readable from outside, see
below.

The fixture `packs/BP/structures/nimrodx_template/example.mcstructure` is real
and committed, built from `docs/fixtures/example.volume.json`.

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
      ExampleTests.js         # registers the SimulatedPlayer tests
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

### 2. Beta APIs and the gametest module - RESOLVED, with a caveat

The world half is handled for you. `mct exportworld` always writes
`experiments: { gametest: 1 }` into the exported `level.dat` - a GameTest world
is what the command produces by definition. The `--betaapis` / `--no-betaapis`
flags are **inert here**: exporting with each and diffing the two `level.dat`
files leaves exactly one byte different, the `LastPlayed` timestamp. Do not
reach for those flags to control this; they matter on the world/deploy paths,
not on `exportworld`.

**The exported world is internally inconsistent, and this is the most likely
way the first run fails.** Measured on `build/worlds/testworld.mcworld` by
reading the byte tags out of `level.dat`:

```
gametest                       = 1
saved_with_toggled_experiments = 0
experiments_ever_used          = 0
```

A world where somebody actually enabled an experiment carries `1` for all
three. `exportworld` sets the experiment but not the two flags that record it
having been set, so the game may nag on load, or refuse the experiment and
load the world without the add-on.

Untested - the first world load settles it. If the add-on is missing on load,
this is the first suspect, ahead of anything in the pack. The recovery is to
toggle the experiment off and on once in world settings, which makes the game
write all three itself. `mct world set --betaApis` will **not** fix it (it is
inert; see below).

The manifest half is now handled too. `packs/BP/manifest.json` declares:

```json
{ "module_name": "@minecraft/server-gametest", "version": "1.0.0-beta" }
```

The version string is the **channel name**, not a resolved version. npm has no
`1.0.0-beta` tarball - the published versions are shaped
`1.0.0-beta.1.26.40-stable` - and the game resolves the channel against its own
engine version at load. Do not "fix" this to a concrete npm version.
`mct validate addon` accepts it and stays clean.

**What this costs.** A beta module is not optional at load time: with this
dependency present the pack requires the Beta APIs experiment and fails to load
without it, rather than quietly skipping the tests. A released add-on cannot
ask players to enable an experiment. That is accepted **for
development and testing only**. A production build must not ship it - see
`docs/decisions.md`.

To strip it for a production build, remove **both**:

1. the `@minecraft/server-gametest` dependency from `packs/BP/manifest.json`, and
2. the `import "./gametests/ExampleTests.js"` line from `packs/BP/scripts/main.js`.

Removing only one breaks the build: the import without the dependency fails to
resolve, and the dependency without the import still demands the experiment.

**This strip is manual, and that is the current weak point.** A release depends
on somebody remembering to do it. The proper fix is the `gametests` Regolith TS
filter, which excludes test code from a chosen profile - so the `build` profile
would drop the tests automatically while `default` keeps them. See the section
above on why that filter is a different thing from the GameTest API.

## SimulatedPlayer - the reason any of this is wired up

`SimulatedPlayer` is what makes GameTest worth the experiment flags. It is a
real, driveable player entity: `moveToLocation`, `navigateToLocation`, `jump`,
`breakBlock`, `interactWithBlock`, `useItemInSlot`, `attack`, `lookAtBlock`.

This matters because the alternative routes cannot move a player at all:

- The retail `/connect` WebSocket bridge drives commands and reads world state.
  It has no movement primitive, and the Education Agent it can locate does not
  exist in retail (`world_agent` returns `exists: false`).
- mct's session tools are BDS-only, and `moveSessionPlayerToLocation` is a `/tp`
  underneath - it repositions a player, it does not walk one. It cannot mine,
  place, attack or use an item.

So SimulatedPlayer is the only thing here that exercises *what happens when a
player does the thing*, rather than *what is near the thing*.

### Registration shape

```js
import { register } from "@minecraft/server-gametest";

register("template", "simulated_player_walks", (test) => {
  const player = test.spawnSimulatedPlayer({ x: 1, y: 1, z: 1 }, "WalkTester");
  player.moveToLocation({ x: 3, y: 1, z: 3 });
  test.succeedWhen(() => {
    test.assertEntityInstancePresent(player, { x: 3, y: 1, z: 3 });
  });
})
  .structureName("nimrodx_template:example")
  .maxTicks(200);
```

Points that are easy to get wrong:

- **Coordinates are relative to the structure origin**, not world coordinates.
  The fixture is a 5x5 pad at relative y=0, so a player stands at y=1.
- **`moveToLocation` is continuous, not blocking.** It starts the player
  walking and returns immediately; `succeedWhen` is what waits. A test that
  asserts position on the next line always fails.
- **`maxTicks` needs headroom.** A simulated player spawns falling and does not
  path until it lands, so a tight budget fails as "never arrived" when the
  player was merely still walking. 200 ticks for a two-block walk is
  deliberately generous.
- **`breakBlock` does not aim.** Call `lookAtBlock` first or it does nothing.
- **Nothing registers itself.** The game loads only the manifest's entry point,
  so `main.js` must import each test file or `/gametest run` will not list it.

### Reading a result without being in the game

A finished test leaves marker blocks beside the arena, and they are ordinary
blocks - so `world.read_region` through the bridge can read the outcome with
nobody reporting it. Confirmed in game 2026-08-31:

| Blocks | Meaning |
|---|---|
| beacon + `lime_stained_glass` above it | passed |
| beacon + `red_stained_glass` above it, plus a **lectern** beside the pad | failed |

The lectern holds the failure text. Its position is readable, its contents are
not - `world.get_block` returns block states, not NBT - so the lectern says
*that* a test failed, never *why*. The `structure_block`, `command_block` and
`stone_button` are present either way and carry no result.

Each run places a fresh arena in unused space rather than reusing the last one,
so several runs leave several arenas and the newest is the one nearest the
player.

### The structure is restored after a run - post-run blocks prove nothing

**This is the trap.** When a test finishes, GameTest puts the structure back
the way it started. A test that breaks, places, or moves a block leaves no
trace of having done so.

It cost an investigation here. `simulated_player_breaks_block` reported a pass
while its target block read `minecraft:stone` and no cobblestone had dropped,
which looks exactly like an assertion that passed without checking anything.

The way to tell those apart is a **control test that must fail** - assert
`diamond_block` where stone is, and see whether the beacon goes red. It did,
along with a failure lectern. So assertions do evaluate block types, the break
test's `air` assertion genuinely held during the run, and restoration is what
erased the hole afterwards.

Two lessons worth keeping:

- **Never conclude anything from the state of a structure after a run.**
  Reading the arena tells you the result markers and nothing else.
- **When a pass looks unearned, prove the harness can fail** before trusting
  it. A control assertion is cheap and conclusive; reasoning about the API from
  the outside is neither. Delete the control once it has answered - a
  permanently red test in the suite is how a team learns to ignore red.

If a test needs to report more than pass/fail, have it write a **sentinel
block** outside the structure bounds. Sentinels survive restoration, and the
bridge can read them.

### Running them

Needs the **Beta APIs** experiment - which is one toggle, not two. The key in
`level.dat` is `gametest`, and the checkbox in world settings is labelled *Beta
APIs*; they are the same thing. `mct exportworld` writes
`experiments: { gametest: 1 }` unconditionally, so a world from
`scripts/testworld.sh` should already have it and need nothing set by hand.

Evidence for the equivalence, since the naming actively misleads: `mct world
set` reads an exported world whose only experiment key is `gametest` and prints
`Beta APIs: true`. **Not yet confirmed in game** - if an imported world loads
without the add-on present, the experiment toggle is the first thing to check.

Do not try to fix it with `mct world set --betaApis true`. That command is
inert on an exported world folder: both `true` and `false` print
`Beta APIs: true` and leave `level.dat` byte-identical (md5-verified, 0.17.8).

Then, in game:

```
/gametest run template:simulated_player_walks
/gametest runset template          # every test in the class
```

This is a human step. The `/connect` bridge exposes no command tool, so an
agent cannot trigger a run or read the result; pass/fail appears in chat and on
the in-world test markers.

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
