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

## Confirmed lessons

- `minecraft:geometry: "minecraft:geometry.full_block"` is the no-custom-model
  path and is enough for a placeholder block.
- `menu_category` is what puts it in the creative inventory. Without it the
  block exists but cannot be found by hand.
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
