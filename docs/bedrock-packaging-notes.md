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
| `.mcaddon` | A bundle of several packs. |
| `.mctemplate` | A world template. |
| `.mcworld` | An exported world. |

`mct exportaddon` produces the first two and chooses between them:

> "Produces .mcaddon when both a behavior and resource pack are present,
> .mcpack for single-pack projects."

`--format` overrides that (`auto` | `mcpack` | `mcaddon`). `scripts/deploy.sh`
forces `mcaddon`. All four extensions are zips; `.mctemplate` is documented as
literally "zip everything up, rename the file".

`.mcaddon` and `.mcworld` are gitignored here.

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
