# Resource pack wiring notes

**Planned skill:** `bedrock-rp-wiring`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-rp-wiring/SKILL.md` only after an entity with a custom model, texture, and render controller has shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

The client entity -> geometry / texture / render controller graph. The
highest-failure area in Bedrock add-ons.

## Confirmed lessons

- It is a **graph, not a tree**: `client_entity` names geometry and texture
  *keys*; the render controller resolves those keys via Molang. A break
  anywhere renders an invisible or magenta entity **with no error message**.
- You can borrow vanilla assets: `"geometry": {"default": "geometry.frog"}` and
  `"render_controllers": ["controller.render.default"]` give a working entity
  with no custom `.geo.json` at all. This is how an agent can produce a
  verifiable entity without Blockbench.
- `materials` is required; `entity_alphatest` is the usual default.
- Texture values are **paths** (`textures/<creator>/<game>/entity/foo`), unlike
  block and item textures which are **keys** into a `*_texture.json`. Mixing
  these up is easy.
- Textures must sit under `textures/<creator>/<gamename>/...` with exactly one
  folder beneath the creator namespace, or Cooperative Add-On validation fails
  (`CADDONREQ102/104/108`). This applies to entity textures too.
- `texture_list` discovers textures automatically and writes
  `textures_list.json` into the export target only - it never appears in
  `packs/`.
- After an RP change, `/reload` is **not** enough: it reloads functions and
  scripts only. Use `/reload all`, which reloads both packs and is effectively
  instant.

## Open questions

- Custom render controllers - none authored yet.
- Molang in render controllers for variant selection.
- Attachables, and how they differ from client entities.
