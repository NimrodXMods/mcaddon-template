# Packaging and manifest notes

**Planned skill:** `bedrock-packaging`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes a skill only once
this project has shipped something other than a plain BP+RP add-on. Today it
ships exactly that, so most of the surface below is unexercised here.

## What the skill must cover

Module types, the manifest format versions they belong to, and the
distribution file extensions - which are a **separate axis** from module type.

## The two axes people conflate

`.mcaddon` and `.mctemplate` are **not** module types. They are distribution
archives. A module type is declared inside `manifest.json` at
`modules[].type`; an extension describes the zip you hand someone.

```
manifest.json  modules[].type   what the pack IS
file extension                  how the pack(s) are DELIVERED
```

A `.mcaddon` typically holds two packs - one whose module type is `data`, one
whose module type is `resources`.

## Module types

The allowed set depends on the manifest's `format_version`. Read from
`../mcbe-schemas/source/general/manifest/manifest.{1,2,3}.json` on 2026-08-31:

| `format_version` | Allowed `modules[].type` |
| --- | --- |
| 1 | `resources`, `data`, `client_data`, `interface`, `world_template`, `skin_pack` |
| 2 and 3 | `resources`, `data`, `client_data`, `interface`, `world_template`, `javascript`, `script` |

The difference is not cosmetic: **`skin_pack` exists only in v1**, and
**`script` / `javascript` only in v2 and later**. A skin pack manifest is a v1
manifest for that reason. Learn states v1 is for skin packs, v2 for resource,
behavior and world template packs, with v3 in preview.

| Type | What it is |
| --- | --- |
| `resources` | Resource Pack. |
| `data` | Behavior Pack. |
| `script` | A JS/TS scripting module. Requires `entry` (e.g. `scripts/main.js`) and `language: "javascript"`. |
| `javascript` | Older spelling of the scripting module. |
| `world_template` | A world template - see below, this is not world *generation*. |
| `skin_pack` | Skin pack. v1 manifests only. |
| `client_data` | **Undocumented.** See below. |
| `interface` | **Undocumented.** See below. |

### `client_data` and `interface` are unverified

Both appear in the schema enum for every manifest version, and **neither is
defined anywhere authoritative**:

- The Learn manifest reference describes only `data`, `resources` and
  `script`: *"Modules define what the pack contains: 'data' for behavior
  packs, 'resources' for resource packs, or 'script' for packs with
  JavaScript/TypeScript code."*
- **No vanilla pack uses them.** Every `manifest.json` under
  `../mcbe-schemas/bedrock-samples/` declares only `resources` or `data`.

Community understanding is that `client_data` was client-side scripting and
`interface` was a custom UI pack, but that is lore, not a citable source.
Treat both as vestigial and do not use them without evidence.

Note the schema is internally inconsistent here, which is a good reminder that
the enum is the machine-readable part and the prose beside it is not:
manifest.1's own `description` says the type *"can be any of the following:
resources, data, client_data, interface, world_template"* - five values -
while the `enum` immediately below lists six, including `skin_pack`.

## Distribution file extensions

| Extension | Contents |
| --- | --- |
| `.mcpack` | A single pack - BP or RP. |
| `.mcaddon` | A bundle of several packs, as directory trees. Learn also claims it may contain `.mcpack` or `.mcworld` files - unverified, see below. |
| `.mctemplate` | A world template. |
| `.mcworld` | An exported world. |

`mct exportaddon` produces the first two and chooses between them:

> "Produces .mcaddon when both a behavior and resource pack are present,
> .mcpack for single-pack projects."

`--format` overrides that (`auto` | `mcpack` | `mcaddon`). `scripts/deploy.sh`
forces `mcaddon`.

**`--offline` does NOT prevent the manifest rewrite.** Confirmed 2026-08-31:
`mct exportaddon --offline` still rewrote `packs/BP/manifest.json`, turning
`"version": "2.9.0"` into `[2, 9, 0]` for both `@minecraft/server` and
`@minecraft/server-ui`, and stripped the trailing newline. The comment in
`scripts/deploy.sh` says `--offline` is safe because it produces a
byte-identical archive, which is true of the *archive* but implies a safety
for the *source* that does not hold. deploy.sh is unaffected only because it
snapshots and restores the manifests either way. **Never run `exportaddon` by
hand without checking `git diff packs/` afterwards.**

All four extensions are zips; `.mctemplate` is documented as literally "zip
everything up, rename the file".

`.mcaddon` and `.mcworld` are gitignored here.

## Which artifact to ship

| Shipping | Use |
| --- | --- |
| Packs only - mobs, items, blocks | `.mcaddon` (or one `.mcpack` each) |
| One specific world, packs included | **`.mcworld`** |
| A world others instantiate fresh copies of | `.mctemplate` |
| A generated world from custom biomes/features | `.mctemplate` with `allow_random_seed`, no `db` |

**A `.mcworld` already carries its packs.** Exporting a world with add-ons
active produces `behavior_packs/` and `resource_packs/` alongside `db/`,
`level.dat` and `world_behavior_packs.json` / `world_resource_packs.json`
(which reference the packs **by UUID**). So "world plus custom content in one
file" needs nothing beyond `.mcworld`.

The choice between `.mcworld` and `.mctemplate` is therefore **not** about
whether packs are included. It is about **instancing**:

| | `.mcworld` | `.mctemplate` |
| --- | --- | --- |
| Imports into | `minecraftWorlds/` | `world_templates/` |
| Appears as | a world, ready to play | an option in world creation |
| Instances | one - the recipient plays *that* world | many - each use spawns a fresh copy |
| `manifest.json` | not required | **required**: `type: world_template`, `format_version` 2, two UUIDs |
| `texts/` folder | - | optional; without it the name shows literally as `pack.name` |

A `.mcworld` is a **copy**; a `.mctemplate` is a **factory**. Marketplace
worlds are templates so every buyer gets a fresh instance.

### A template cannot be both a fixed map and a random-seed generator

`db/` **is** the world - the LevelDB chunk store. The documented random-seed
recipe is to *delete* it:

> 1. Starting with any unzipped, exported world, delete the **db** folder.
> 2. Add `"allow_random_seed": true` to the manifest.json.

So one template either has `db` (that specific map) or lacks it (generate
fresh from the packs). The presence of the map is the switch; there is no
setting that yields both. To ship a playable generated world *and* a showcase
map, ship two artifacts - a random-seed template plus a separate `.mcworld`
demo.

Also: *"After the world is created, the world seed is locked and no longer
editable."*

## What is actually inside a `.mcaddon`

**Verified 2026-08-31** by running `mct exportaddon -i . -o ./build --format
mcaddon --offline` on this project and listing the archive.

It contains **directory trees, not nested archives**:

```
BP_bp/
  manifest.json
  entities/  items/  blocks/  loot_tables/  scripts/  spawn_rules/
RP_rp/
  manifest.json
  entity/  render_controllers/  textures/
```

46 entries, **zero** `.mcpack` or `.mcworld` files. Each pack is a top-level
directory carrying its own `manifest.json`, and therefore its own UUIDs and
module type.

**There is no root-level manifest.** The archive has exactly two manifests,
one per pack directory. Whatever the importer uses to decide what it is
looking at, it is not a manifest at the top of the `.mcaddon`.

Note also that `mct` names the directories from the **source folder** names
(`packs/BP` -> `BP_bp`), not from `config.json`'s `name` the way regolith does
for its export target. The same project therefore ships under two different
folder names depending on which tool packaged it.

### Unverified - documented but not tested here

Learn's file-extension glossary says `.mcaddon` is *"a zip file that contains
.mcpack or .mcworld files"*. That is a one-line glossary entry, from the same
prose that got `minecraft:icon` wrong, and **the archive built here contained
neither**. Open, in order of how much they matter:

- Does the importer actually accept **nested `.mcpack` / `.mcworld`
  archives**, as the glossary implies?
- Can one `.mcaddon` hold **more than one pack of the same type** - two
  resource packs, say? Nothing structural forbids it, since each directory has
  its own manifest and UUIDs, but that is reasoning, not evidence.
- Can an `.mcaddon` contain a **`.mctemplate`**? The glossary does not mention
  it, and silence is not exclusion.

**Working hypothesis, untested:** `.mcaddon` may be a general "meta importer"
- a container whose only job is to let one file import a list of packs and
worlds at once. That would explain the loose glossary wording, and it fits the
UUID-based referencing already visible inside worlds, where
`world_behavior_packs.json` names required packs by UUID rather than by
folder. Under that reading, the plausible real use for a world inside an
`.mcaddon` is shipping **several worlds that share one copy of the packs**,
rather than duplicating packs per world.

Recorded as a hypothesis. Test before relying on any of it: build an
`.mcaddon` by hand containing two worlds and one pack, import it, and see what
the game does.

## World templates are not world generation

The naming trap. A **world template** is a packaged, pre-built world -
terrain, settings and any bundled packs - offered as a starting point in the
world-creation UI. Vanilla's own lang file makes the meaning plain:

```
worldTemplate.Skyrim.name=Skyrim Mash-up
worldTemplate.redstonemansion.name=Redstone Mansion
worldTemplate.GreekMythology.name=Greek Mythology Mash-up
```

It contains an already-generated world, **not** generation rules.

**Custom world generation has no distinct pack type or in-game name.** Biomes,
features and feature rules are ordinary behavior pack content - a `data`
module, exactly like entities and items. See
`docs/bedrock-worldgen-notes.md`.

The two compose: a world template may *bundle* a behavior pack that contains
worldgen rules, which is how Marketplace worlds ship custom terrain. The
template is the delivery vehicle; the BP is the ruleset. Searching for
"Bedrock world template" while trying to write worldgen returns packaging
documentation and none of it applies.

Two details from Learn worth keeping if a template is ever built here:

- `allow_random_seed: true` (with the `db` folder deleted) makes the template
  apply to any new world rather than one fixed map.
- Pack folder names inside a world template must be **10 characters or
  shorter** - an Xbox path-length issue, where longer names silently fail to
  load.

## Open questions

- What did `client_data` and `interface` ever do, and is either still honoured
  by the game?
- Does this project ever need a v3 manifest? v3 adds a user-visible settings
  screen (label / toggle / slider), currently preview-only and subject to
  change.
