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
- Invisible and magenta mean different things. Magenta = a texture path
  resolved but the file is missing. Invisible = the component itself was
  rejected. Do not debug the texture when the item is invisible.
- `mct validate` reported **zero errors** for the invalid icon. This was caught
  only by loading the pack in game.
- The icon key is looked up in `item_texture.json`, not a path.
- The lang key is `item.<id>` - **no `.name` suffix**, unlike entities
  (`entity.<id>.name`) and blocks (`tile.<id>.name`).
- `menu_category` is what makes it findable in the creative inventory.
- Read the schema before writing any component. `minecraft:icon` was written
  from memory and was wrong; `../mcbe-schemas/behavior/items/items.json` had
  the answer in seconds. AGENTS.md rule 4a exists for exactly this and was
  still skipped.

## Open questions

- Durability, cooldown, food, weapon components - none authored yet.
- Recipes - none authored yet.
- Whether RP-side item definitions (`resource/items/items.json`) are ever
  needed alongside BP items.
