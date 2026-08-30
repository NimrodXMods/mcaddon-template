# Model authoring for the agent

**Planned skill:** `bedrock-geometry`
**Status:** research notes only - **nothing in this file is verified by this
project.** No custom `.geo.json` has been authored here; the template
deliberately uses vanilla geometry (see `docs/decisions.md`), and
`mct rendermodel` has never been run against project geometry. Every rule
below is inherited from the research pass and the third-party sources
surveyed in `docs/model-authoring-human.md` sections 5a/5b. Per the skill
policy in `docs/decisions.md`, none of it becomes a skill until a real model
has shipped end to end. Treat it as plausible guidance, not authority.

Prior art: `Logeaddd/minecraft-ai-generate-bbmodel` (MIT, see
`model-authoring-human.md` section 5a) solves an adjacent problem for
`.bbmodel`. Several rules below are borrowed from it and marked. Nothing
exists that targets Bedrock `.geo.json` directly.

---

## What you are producing

A **first draft skeleton for Blockbench**, not a finished asset. Your job is
the bone tree, pivots, cube dimensions, and naming. Texturing is a human step.

## Plan before you emit JSON

Write the structure out first — parts, parent chain, pivot per bone, explicit
`[w,h,d]` per cube, and the geometry/texture classification below — then
produce the `.geo.json` from that plan. Emitting geometry token-by-token
without a plan is what produces broken proportions and float noise.

If the model has more than ~8 bones, write the plan to a `.md` or `.json`
scratch file first so the human can correct the skeleton before any geometry
exists. Cheap to fix at that stage, expensive after texturing.

## The silhouette gate

Before the expensive pass — before UVs, before rigging, before any texture
work — produce the geometry and render it:

```bash
mct rendermodel <file>.geo.json -i .
```

Present the silhouette and stop. The human approves the shape and proportions
or rejects them. Only after approval do you spend effort on UV offsets, bone
refinement, or animation scaffolding.

Rejecting a silhouette costs one cheap render. Rejecting a rigged and textured
model costs everything downstream of it.

## Model format

If producing a `.bbmodel` rather than `.geo.json`, set `model_format` to
`"bedrock"`, never `"free"`. Free format is unconstrained and is not a
Bedrock-ready model — it permits arbitrary three-axis cube rotations and
resolutions that will not survive conversion to `.geo.json` cleanly.

Keep `resolution` to Bedrock-conventional sizes (16, 32, 64, 128). A 512×512
atlas is a sign the pipeline has drifted away from Bedrock conventions.

## Hard rules

1. **Box UV only.** Emit `"uv": [x, y]`. Never emit the per-face object form
   (`{"north": {...}}`) unless explicitly instructed. Box UV derives all six
   faces from `size`, so it cannot be wrong; per-face UV can be wrong in ways
   that produce no error.
2. **Never modify a `.geo.json` that has a painted texture.** Geometry and
   texture are joined after UV packing. Changing cube sizes silently
   invalidates the UVs. If asked to change a textured model, say so and stop.
3. **Never invent `format_version`.** Read it from an existing model in the
   project. Geometry format versions (1.8.0, 1.12.0, 1.16.0, 1.21.0) differ
   structurally, not just cosmetically.
4. **Every bone declares a `pivot`.** No exceptions.
5. **Placeholder UV offsets are fine.** Blockbench auto-UV repacks them. Do
   not attempt to compute an atlas layout.
6. **Snap all coordinates to a 0.5-unit grid.** Never emit arbitrary fractional
   sizes or origins. Float noise is the signature of a bad auto-generated
   model — it causes Z-fighting and makes the file unpleasant to edit by hand.
   Deviate only when the design genuinely requires it, and say so.
7. **Every cube declares an explicit `size`.** Never leave a dimension to be
   "adjusted later". This single rule is what prevents guessed proportions.
8. **All identifiers and bone names ASCII.** Non-ASCII names corrupt to
   replacement characters (`?`) somewhere in the toolchain.
9. **No blanket Z-fight offsets.** If two cubes are coplanar and one must sit
   slightly proud, offset that one deliberately and note why. Never nudge
   coordinates globally to "avoid flicker".

## Pivots — the thing most often wrong

`pivot` is the rotation point. It is independent of cube geometry and belongs
at the **joint**, not the cube center.

From a model examined during the research pass (not one authored or verified
in this repo - no `.geo.json` exists here):

```json
{
  "name": "body",
  "parent": "root",
  "pivot": [0, 4.625, 0],
  "cubes": [{ "origin": [-4, 3, -4], "size": [8, 13, 8], "uv": [0, 20] }]
}
```

The pivot (`y=4.625`) is nowhere near the cube's center. That is correct.

- Arms pivot at the shoulder, near the top of the arm cube.
- Legs pivot at the hip, near the top of the leg cube.
- Head pivots at the neck, near the bottom of the head cube.

A wrong pivot produces a model that looks fine at rest and animates wrongly.
Nothing will warn you.

## Bone tree

- Exactly one root bone with no `parent`.
- Every other bone's `parent` chain must reach that root.
- Convention: `root` -> `body` -> `head`, `leftArm`, `rightArm`, `leftLeg`,
  `rightLeg`.
- A bone may have no cubes — a pure transform node is legitimate and useful
  (`{"name": "root", "pivot": [0, 3, 0]}`).
- **Names are an API.** Animations and render controllers address bones by
  name. Keep names identical across a mob family.

Reference shape for a quadruped/biped creature, segmented for animation:

```
root > body > hips, torso, chest
            > neck > neck_lower, neck_upper > head > upper_skull > jaw
            > tail_base > tail_mid > tail_tip
            > thigh_L > shin_L > foot_L        (mirrored right)
            > arm_L > forearm_L                (mirrored right)
```

Segment anything that needs to bend. A one-cube tail cannot swish; a three-
segment chain can. A jaw parented under head opens independently of head
rotation. This segmentation is a geometry decision made for animation's sake,
so decide it before writing cubes, not after.

## Description block

```json
"description": {
  "identifier": "geometry.<name>",
  "texture_width": 64, "texture_height": 64,
  "visible_bounds_width": 3,
  "visible_bounds_height": 3.5,
  "visible_bounds_offset": [0, 1.25, 0]
}
```

- `identifier` must match what the client entity / block definition references.
- `texture_width`/`height` are declarations of assumed atlas size, not
  constraints. Blockbench resizes during auto-UV.
- `visible_bounds_*` is the culling box in model-space units. Set it
  generously. Too small clips the model at distance — a bug that only appears
  when the player walks away.

## Classify every detail: geometry or texture

Before writing any cube, enumerate the model's distinguishing features and
label each one. (Borrowed from `minecraft-ai-generate-bbmodel`.)

| Kind | Test | Consequence |
| --- | --- | --- |
| `geometry` | It protrudes from the silhouette — ears, horns, handles, spikes, brims, tails | Must exist as a **real cube in a real bone** |
| `texture` | It is flat — eyes, mouths, labels, panel lines, stitching | Must be a note for the human painter, naming the **bone and face** it belongs on |

Report the classification list alongside the model. For every `texture`
detail, state which bone and which face (`north`/`south`/`east`/`west`/`up`/
`down`) it goes on.

This is the countermeasure to the most common silent failure: a detail that
gets painted into the atlas but was never bound to a face, or a protruding
feature that only ever existed as paint and so has no silhouette.

Do not model flat details as geometry. A 1-unit-thick cube for an eye is
wrong and causes Z-fighting.

## Proportions: advisory, not enforced

Sanity-check proportions against the archetype (humanoid, quadruped, prop,
block) and **report** anything that looks off — a body narrower than it is
tall by a wide margin, ears taller than the head, stilt legs.

Report; do not silently correct. Unusual proportions are frequently
deliberate: a long-eared alien, a totem, a bobble-head, a stylized mascot. The
check exists to catch a fat-fingered dimension, not to enforce a house style.
If the human confirms the look is intended, proceed unchanged.

## Units

Model space is 16 units per block. A 1.8-block-tall humanoid is ~29 units.
Blocks occupy `origin [-8, 0, -8]`, `size [16, 16, 16]`.

## Verification

```bash
mct rendermodel <file>.geo.json -i .
```

Renders untextured geometry to PNG. Inspect the silhouette and proportions
before anyone paints. This is the only automated check that catches a
structurally valid but visually wrong model.

For comparison baselines:

```bash
mct rendervanilla mob minecraft:creeper -o creeper.png
```

## Escalate, do not guess

- Any request touching a textured model.
- Any per-face UV work.
- Any non-uniform scaling of an existing model (a UV repacking problem —
  Blockbench's Inflate is uniform-only for exactly this reason).
- Organic or non-axis-aligned shapes. These are Blockbench-by-hand work.

## Preferred automation route

If asked to script model manipulation, write a **Blockbench plugin**
(<https://www.blockbench.net/wiki/docs/plugin/>; Context7
`/websites/web_blockbench_net`) rather than editing
`.geo.json` files. Wrap edits in `Undo.initEdit` / `Undo.finishEdit` and call
`Canvas.updateView`. Blockbench uses `from`/`to` in memory and emits
`origin`/`size` on export — do not assume they match.
