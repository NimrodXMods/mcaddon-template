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

- You can borrow vanilla assets: a vanilla `geometry` identifier plus
  `"render_controllers": ["controller.render.default"]` give a working entity
  with no custom `.geo.json` at all. This is how an agent can produce a
  verifiable entity without Blockbench. Vanilla **textures** can be borrowed
  the same way (`textures/entity/skeleton/skeleton`), which is the only way to
  recolour a mob when `.png` writes are denied to agents.
- **Get vanilla identifiers from `bedrock-samples`, never from memory.** The
  submodule under `../mcbe-schemas/` holds the real client entities, so the
  correct geometry/texture pairing is a file read rather than a guess:
  `bedrock-samples/resource_pack/entity/skeleton.entity.json` gives
  `geometry.skeleton.v1.8` + `textures/entity/skeleton/skeleton`.
- Many vanilla models use the legacy `1.8.0` format, where the geometry
  identifier is a **top-level JSON key** rather than an `"identifier"` field.
  Grepping `models/entity/` for `"identifier"` finds `geometry.zombie.drowned`
  but **not** `geometry.zombie.v1.8`, which looks like the latter does not
  exist. Grep for the quoted identifier itself instead.
- A **solid-colour texture ignores UV layout**, so it maps onto any geometry.
  The 16x16 flat `#4A7C3F` placeholder here renders correctly on frog, zombie
  and skeleton models alike. Convenient for placeholders - and a trap, because
  it means a geometry swap that *would* garble a real texture looks fine.
- **`minecraft:collision_box` does not position the model.** A mob's feet sit
  where the geometry's `0,0,0` origin puts them - the collision box is the
  physical hitbox and nothing else. A box that disagrees with the model means
  you swing at visible air, or hit nothing where the model looks solid; it
  never makes the mob float or sink. Confirmed in game after the frog ->
  skeleton/zombie swap: `example_entity` kept a 1x1 box under a 1.9-tall
  zombie model and still stood correctly on the ground.

  Worth keeping them in agreement anyway, for hitboxes that match what players
  see. Vanilla skeleton/zombie are 1.9 x 0.6. But it is a BP component and
  nothing links the two, so no tooling will tell you they diverged.
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

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- It is a **graph, not a tree**: `client_entity` names geometry and texture
  *keys*; the render controller resolves those keys via Molang. A break
  anywhere renders an invisible or magenta entity **with no error message**.
- `materials` is required; `entity_alphatest` is the usual default.

The entity here wires up correctly and renders, so the graph *shape* is
confirmed. The failure behaviour is not: nothing was deliberately broken, and
no custom render controller was written - `controller.render.default` does the
resolving. `materials` was always present, so "required" is assumed rather than
tested.

## Open questions

- Custom render controllers - none authored yet.
- Molang in render controllers for variant selection.
- Attachables, and how they differ from client entities.
