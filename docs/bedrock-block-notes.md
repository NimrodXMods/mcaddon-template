# Block authoring notes

**Planned skill:** `bedrock-block`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-block/SKILL.md` only after a block family - states, permutations, custom geometry - has shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

Block states and permutations, geometry and culling, and the
`blocks.json` / `terrain_texture.json` / `textures/` three-way path contract.

## How blocks differ from entities

Verified against `../mcbe-schemas/source/behavior/` on 2026-08-31. The word
"component" is shared with entities; almost nothing else is.

Top-level keys, side by side:

```
entity   description, components, component_groups, events, upgrades
block    description, components, permutations
item     description, components
```

**Blocks have no `component_groups` and no `events`.** The whole
entity machinery documented in `docs/bedrock-entity-notes.md` - triggers
naming events, events adding and removing groups - does not exist here. There
is no `events.json` under `blocks/format/`, only under `entities/format/`.

What blocks have instead is **permutations**. Each entry is
`{condition, components}`, where `condition` is a Molang expression. The
schema states a real limit on it:

> "For permutation conditions you are limited to using one Molang query:
> `query.block_state()`"

The two models are opposites in kind, which is the part worth holding onto:

| | Entity | Block |
| --- | --- | --- |
| Mechanism | `component_groups` + `events` | `permutations` |
| Style | **imperative** - an event explicitly adds/removes groups | **declarative** - conditions are evaluated against current states |
| What changes it | a trigger fires an event | you change a block **state** |
| Persistence | the active set persists until an event changes it | re-derived from state; nothing is "held" |

So the failure modes invert. The entity gotcha is forgetting to `remove` a
sibling group in one transition. The block equivalents are a permutation whose
condition never matches, or two that match at once. Different bug, equally
silent - `mct validate` sees neither.

**Component names recur across types with different meanings.**
`minecraft:loot`, `minecraft:collision_box` and `minecraft:display_name` all
exist for blocks and overlap entity names, with different schemas behind them.
Read `../mcbe-schemas/behavior/blocks/` for blocks; an entity page is not a
substitute.

One thing that *is* shared: a component is silently dropped if
`format_version` predates it, per-component and at parse time, with zero
errors from `mct validate`. That was confirmed in game for entities and is not
entity-specific - assume it applies here.

## Confirmed lessons

- `minecraft:geometry: "minecraft:geometry.full_block"` is the no-custom-model
  path and is enough for a placeholder block.
- `menu_category: {"category": "construction"}` is set here and the block
  shows up in the creative inventory.
- Textures must follow the Cooperative Add-On layout -
  `textures/<creator>/<gamename>/blocks/*.png`, exactly one folder under the
  creator namespace. See `CADDONREQ102/104/108`.
- `blocks.json` uses an **array** `format_version` (`[1, 1, 0]`), not the string
  form used by BP definition files. Easy to get wrong by copying.
- The lang key for a block is `tile.<id>.name` - `tile.`, not `block.`.
- The BP block and the RP `blocks.json` entry are keyed by the **full
  namespaced identifier**, while `terrain_texture.json` is keyed by a short
  texture name. Two key spaces, one line apart.

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- The three-way contract is the thing that breaks: the BP block's
  `material_instances` texture key must exist in `terrain_texture.json`, whose
  `textures` path must point at a real file, and `blocks.json` ties the
  identifier to that key. Break any link and you get magenta with no error.
- Without `menu_category` the block would exist but be unfindable by hand.
  The block here has had the field since its first commit, so the without
  case was never observed.

The contract itself is real - all three files were written and the block renders.
What is untested is the **failure** mode: no link was ever deliberately broken,
so "magenta with no error" is inherited, not observed. The item's failure was
observed and was *invisible*, not magenta, which is a reason to be careful about
assuming what a broken block looks like.

## Open questions

- Block states and permutations - none authored yet.
- Culling rules and when they are needed.
- Whether the block-family generator idea in `model-authoring-human.md` is
  worth building.
