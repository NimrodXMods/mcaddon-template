# Item authoring notes

**Planned skill:** `bedrock-item`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-item/SKILL.md` only after items with real behavior - durability, use, recipes - have shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

Item components, the icon/texture contract, and recipes.

## Confirmed lessons

- **`minecraft:icon` is either a bare string or
  `{"textures": {"default": "<key>"}}`** - `textures` plural, `default`
  required, `additionalProperties: false`. Writing `{"texture": "x"}` is
  silently invalid: the component is rejected, no icon resolves, and the item
  renders **invisible**.
- The observed failure was **invisible**, not magenta: the rejected component
  meant no icon resolved at all. When an item is invisible, debug the
  component shape, not the texture.
- `mct validate` reported **zero errors** for the invalid icon. This was caught
  only by loading the pack in game.
- The icon key is looked up in `item_texture.json`, not a path.
- The lang key is `item.<id>` - **no `.name` suffix**, unlike entities
  (`entity.<id>.name`) and blocks (`tile.<id>.name`).
- `menu_category` is set here and the item shows up in the creative inventory.
  (The without case was never tested; the field has been there since the
  first commit.)
- Read the schema before writing any component. `minecraft:icon` was written
  from memory and was wrong; `../mcbe-schemas/behavior/items/items.json` had
  the answer in seconds. AGENTS.md rule 4a exists for exactly this and was
  still skipped.

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- Magenta means a texture path resolved but the file is missing. No magenta
  has ever been produced in this project - the one observed failure rendered
  invisible - so what magenta means, and what produces it, is inherited.

## Open questions

- Durability, cooldown, food, weapon components - none authored yet.
- Recipes - none authored yet.
- Whether RP-side item definitions (`resource/items/items.json`) are ever
  needed alongside BP items.
