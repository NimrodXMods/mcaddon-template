## Bedrock Model Authoring: Blockbench Workflow + Agent Geometry Rules

Companion to files 01 and 02. Scope: `.geo.json` block and entity models.
Blender is explicitly out of scope. Blockbench is the only 3D tool.

---
---

## PART 1 — For humans

---

## 1. Terminology

Bedrock does not use Java Edition's `elements[]` / `from` / `to`. Bedrock
geometry is:

```
minecraft:geometry[]
  description   -> identifier, texture_width/height, visible_bounds_*
  bones[]       -> name, parent, pivot, rotation
    cubes[]     -> origin, size, uv, inflate, rotation, pivot
```

- `origin` is a corner, `size` is an extent. (Java's `to` is an absolute
  corner — any Java-derived tool needs a real transform, not a rename.)
- `identifier` (e.g. `geometry.ghost`) is what entity client files and custom
  block definitions reference.
- Custom block geometry and entity geometry use the **same** `.geo.json`
  format. There is no separate block model format on Bedrock.

Searching for "minecraft block model element scale" returns Java tooling.
Search `geo.json bones cubes origin size` instead.

---

## 2. The two UV forms — the single most important distinction

### Box UV (use this by default)

```json
{ "origin": [-4, 3, -4], "size": [8, 13, 8], "uv": [0, 20] }
```

One `[x, y]` offset into the atlas. The layout of all six faces is **derived**
from `size`. Correct by construction — you cannot mis-map a face.

### Per-face UV

```json
"uv": {
  "north": {"uv": [0, 0],   "uv_size": [16, 8]},
  "east":  {"uv": [0, 0],   "uv_size": [16, 8]},
  "up":    {"uv": [16, 16], "uv_size": [-16, -16]},
  "down":  {"uv": [16, 16], "uv_size": [-16, -16]}
}
```

Full manual control. Note the **negative `uv_size`** values — those are
deliberate axis flips (mirroring a face). Any naive scaling routine destroys
them silently.

### Why this matters for automation

Scaling a cube's `size` does **not** update its UVs. In box UV that's fine,
because the unwrap is recomputed from size. In per-face UV it means stretched
or misplaced textures with no error message.

Blockbench's own answer to this is deliberately narrow: the **Inflate** feature
scales cubes uniformly on all axes while keeping UV mapping intact regardless
of UV mode. Uniform-only, because non-uniform scaling with correct UV
repacking is genuinely hard.

**Practical rule: box UV until you have a specific reason not to.**

---

## 3. The workflow

```
1. Agent writes bone tree + cubes + pivots, box UV, placeholder offsets
2. mct rendermodel -> check the silhouette before anyone paints
3. Blockbench: auto-UV to pack offsets and size the atlas
4. Blockbench: export texture template (a labeled blank PNG)
5. Paint the template in 2D
6. Model is now "owned" - agent never rewrites this .geo.json again
```

Step 4 is why "no image model paints UVs" is not a blocker. The texture
template **is** the UV layout rendered as a blank canvas with every face as a
labeled rectangle in a known position. Painting it is an ordinary 2D inpainting
task with no 3D correspondence to solve.

Verify by hand: exact menu paths for auto-UV and template export, and whether
auto-UV repacks all cubes or only the selection.

### The one-directional handoff

Once a texture is painted, geometry and texture are joined. An agent
regenerating cube sizes silently invalidates the UVs. Make this a hard rule:
**agent authors the skeleton, human takes ownership at first texture, agent
never writes that file again.** Enforce in `.claude/settings.json`:

```json
{
  "permissions": {
    "deny": [
      "Edit(**/*.geo.json)", "Write(**/*.geo.json)",
      "Edit(**/*.bbmodel)", "Write(**/*.bbmodel)",
      "Edit(**/*.png)",     "Write(**/*.png)"
    ]
  }
}
```

Match on extension rather than directory: models and textures live inside
`packs/RP/models/` and `packs/RP/textures/`, which must otherwise stay
writable. A directory-wide deny there would block ordinary pack authoring.

Relax it per-file only while a model is still in draft.

---

## 4. Blockbench plugin API — the automation surface

If you want scripted model manipulation, write a Blockbench plugin rather than
editing `.geo.json` on disk. You get undo, viewport updates, and format
normalization free. The official wiki's introductory example is almost exactly
the "scale the elements of a template" use case:

```javascript
Plugin.register('height_randomizer', {
    title: 'Height Randomizer',
    author: 'YourName',
    description: 'This plugin can randomize the height of all selected cubes',
    icon: 'bar_chart',
    version: '0.0.1',
    variant: 'both',
    onload() {
        button = new Action('randomize_height', {
            name: 'Randomize Height',
            icon: 'bar_chart',
            click: function() {
                Undo.initEdit({elements: Cube.selected});
                Cube.selected.forEach(cube => {
                    cube.to[1] = cube.from[0] + Math.floor(Math.random()*8);
                });
                Canvas.updateView({
                    elements: Cube.selected,
                    element_aspects: {geometry: true},
                    selection: true
                });
                Undo.finishEdit('Randomize cube height');
            }
        });
        MenuBar.menus.tools.addAction(button);
    },
    onunload() { button.delete(); }
});
```

Docs: <https://www.blockbench.net/wiki/docs/plugin/>

Note Blockbench uses `from`/`to` internally across all formats and emits
Bedrock `origin`/`size` on export. Do not assume the in-memory representation
matches the file.

Also relevant: Blockbench supports math expressions in several places in the
animation workflow (see the Animation Expressions guide), which covers a
different slice of parametric work.

This is a good agent task. Plugins are plain JS with a documented API, they
are testable by hand, and the agent never touches a `.geo.json` directly.

---

## 5. Other tooling surveyed

| Tool | Verdict |
| --- | --- |
| **Blockbench Plugin API** | Recommended automation surface. |
| **Logeaddd/minecraft-ai-generate-bbmodel** | **A Claude Code skill.** Same architecture as ours, arrived at independently. Read it; don't depend on it. See section 5a. |
| **Orca (orcaclient.com)** | Commercial AI mod pipeline + server host, with a 19-tool MCP server. Not usable as a component, but its staging and its published sample are instructive. See section 5b. |
| **Nusiq/mcblend** | Blender. Out of scope per your decision. |
| **SNHuan/BlockBench-tool** | Small Python `geometry.py`. Unvetted. |
| ~20 ad-hoc `tools/gen_*.py` scripts across unrelated addon repos | The actual state of the art. Nobody has published a shared library. |
| NetEase China Edition Bedrock skill | `netease_blocks` / `netease_items_beh` folder conventions. Item/block JSON, not geometry. Not applicable. |

The absence of a shared library is a signal, not neglect: the hard part is UV
repacking, and everyone routes around it by hand-authoring templates.

---

## 5a. Logeaddd/minecraft-ai-generate-bbmodel — read this one

<https://github.com/Logeaddd/minecraft-ai-generate-bbmodel> (MIT)

Calibration before you invest: 5 stars, one author, commits spanning **two days**
(2026-05-30 to 05-31), 40 KB total, and the `SKILL.md` still ends with two
leftover `<!-- __CONTINUE_HERE__ -->` authoring markers. It is a weekend
project, not infrastructure. **Do not install it as a dependency.**

Read it anyway. The `SKILL.md` is 13 KB of well-reasoned design that reaches
the same conclusions as this document independently, and states the core
rationale more sharply:

> A language model cannot reliably estimate `from`/`to`/`origin`/`uv`; doing so
> produces the classic failures: broken proportions, float noise that looks
> like an auto-reconstructed mesh, Z-fighting, and texture detail that was
> painted into the atlas but never bound to the correct cuboid face.

Its pipeline:

```
input (text / image)
  -> [AI]     author asset spec JSON
  -> [script] validate_schema      (structure, ids, ascii, references)
  -> [script] validate_geometry    (archetype proportion anchors)
  -> [script] build .bbmodel       (grid-snapped cuboids, hierarchy, UVs)
  -> [script] render atlas
  -> [script] validate_bbmodel     (faces, uv bounds, detail binding)
  -> .bbmodel -> Blockbench for manual polish
```

### Important scope limit

It targets **`.bbmodel`, not `.geo.json`.** That is Blockbench's native format,
so it fits a Blockbench-centric workflow — you would export Bedrock geometry
from Blockbench afterward. But it is not a Bedrock geometry generator and has
no Bedrock export path. Our pipeline needs `.geo.json` directly, because that
is what Regolith and `mct validate` consume.

### Ideas worth lifting outright

| Idea | Why |
| --- | --- |
| **Box UV as the default** (`uv_mode: box` with single `uv_origin`; `per_face` opt-in) | Independent confirmation of the rule in section 2. |
| **`face_details` as a data checklist** | Each detail tagged `kind: geometry` (protrudes — ears, handles, spikes; must exist as a real part) or `kind: texture` (flat — eyes, labels; must name a real part + face inside the atlas). Both validated. This is a concrete mechanism against "painted in the atlas but bound to no face". |
| **0.5px grid snapping** | Kills float noise. This is the difference between a clean model and one that looks auto-reconstructed. Adopt it. |
| **Two-tier validation** | HARD failures are structural only (duplicate/missing ids, unresolved `parent`, UV outside atlas, non-ASCII names, missing `size`). Proportion checks are ADVISORY, with `--strict` to promote them. |
| **Advisory-by-default proportions** | Rationale: a long-eared alien, a totem, a bobble-head are legitimate. Proportion rules should catch fat-fingering, not enforce style. |
| **Targeted Z-fight offsets** | Applied only to parts explicitly tagged `z_offset_tag`, never sprinkled globally. |
| **Explicit `size` on every part** | Stated as the single rule that "kills AI guessed the proportions". `pos` is the min corner; the script computes the far corner. |

### The reverse path

`scripts/bbmodel_to_spec.py` reverses an existing `.bbmodel` into an editable
spec — your template-parameterization route. Documented honestly:

- **Round-trips losslessly:** pos/size/pivot/rotation/inflate, hierarchy, UV
  layout, resolution.
- **Lossy:** texture pixels (use `--dump-texture`), `face_details` (returns
  empty, re-declare), `target`/`archetype` (guessed or blank).

It also sanitizes non-ASCII and duplicate element names to unique ASCII ids and
recovers non-box UVs as explicit `per_face` — useful when ingesting foreign
models.

### Image input

Supported, but through the spec, never by tracing. Its framing is worth
repeating: read the image's *structure* (major volumes, footprint, repeated
parts), decide which features are geometry vs texture, then write explicit
pixel sizes into the spec. Perspective, shading, ambient occlusion and edge
highlights are lighting, not shape — copying them is what produces mesh noise
and phantom blocks.

### What to do with it

Read `SKILL.md` and `schema/asset_spec.schema.json`. Steal the spec-schema
concept for our own `bedrock-geometry` skill, targeting `.geo.json` directly.
The grid snap, the `face_details` binding checklist, and the hard/advisory
split are the three highest-value borrowings.

---

## 5b. Orca (orcaclient.com) — a commercial pipeline, examined

A Minecraft server host with an AI build pipeline attached. Caveat on
sourcing: the site is ~150 pages of heavy programmatic SEO, including 20+
"orca-vs-competitor" pages and a page per named public server. The docs and
the downloadable artifacts are the signal; the rest is marketing.

### Their build loop

Stated pipeline: the AI writes code for the chosen loader and version,
generates textures and 3D models, compiles to a `.jar` (Fabric/Forge/
NeoForge), a plugin `.jar`, a Bedrock add-on, or a packed `.zip`, then
**boots a real test server and load-tests the build**. On failure it reads the
actual error, patches code or art pack, and rebuilds until the jar compiles
and every texture and model the mod references is present.

This is the same generate → validate → auto-patch → repeat architecture as
file 01, at commercial scale. One thing they do that is strictly stronger than
`mct validate`: load-testing against a real running server. Worth aspiring to
via `mct deploy --test-world --launch` once the basic loop is trusted.

On Bedrock specifically, their description of the failure mode matches ours:
the AI generates BP and RP, writes manifests, builds entity components,
generates model and texture, then validates — *because a Bedrock pack that
fails to load usually fails silently*.

### Their MCP server

Public endpoint `app.orcaclient.com/api/mcp`, 19 tools, **OAuth 2.1 rather
than API keys**. Named tools visible: `scaffold_project`, `generate_model`,
`finalize_model`, `load_test`, `apply_to_my_server`, `get_file`,
`package_creation`. Also a CLI:

```
orca tool run generate_model --name cave_lizard --description "armored cave lizard"
```

Useful as a tool-decomposition reference. Note the separation of
`generate_model` from `finalize_model` — a draft stage and a commit stage,
which mirrors our texture-ownership handoff.

### Their model staging — copy this

1. **Approve the concept.** Check silhouette and anatomy *before the expensive
   model pass*.
2. **Build geometry.** Convert the shape into textured cuboids and meaningful
   bones.
3. **Rig and inspect.** Animations, pivots, head movement, and orbit views get
   visual QA.

The silhouette gate in step 1 is a better-specified version of our
"plan first, scratch file if >8 bones" rule. Make it explicit: cheap render,
human approves or rejects, only then spend effort on bones and UVs.

### The T-rex sample — evidence, not copy

They publish a real `.bbmodel` at `/capabilities/models/trex.bbmodel`. It is
worth examining because it both validates and complicates our rules.

**Good — the bone tree, which is the part we delegate:**

```
root > body > hips, torso, chest
            > neck > neck_lower, neck_upper > head > upper_skull > jaw
            > tail_base > tail_mid > tail_tip
            > thigh_L > shin_L > foot_L        (mirrored right)
            > arm_L > forearm_L                (mirrored right)
```

Segmented tail and limb chains, jaw correctly parented under head, clean ASCII
names throughout. Two animations ship with it: a walk driving thigh/shin/tail/
head, and a bite driving only the jaw. Animation keyframe values are clean
integers (-24, 24, 10, -20, 22).

**Concerning — the geometry:**

| Field | Value | Problem |
| --- | --- | --- |
| `model_format` | `"free"` | **Not `"bedrock"`.** Free format is unconstrained; this is not a Bedrock-ready entity model |
| `box_uv` | `false` | Per-face UV throughout |
| `resolution` | 512×512 | Far beyond Bedrock convention |
| cube coords | `-5.398`, `11.9988`, `-8.236` | Float noise, no grid snap |
| cube rotations | `[166.9966, 0, 0]`, `[61.2961, 14.1475, 8.4105]` | Arbitrary three-axis rotations |
| name | `trex-minecraft-oriented-v6` | "minecraft-*oriented*", and a v6 |

The coordinate noise is exactly what Logeaddd's `SKILL.md` warns about:
"float noise that looks like an auto-reconstructed mesh." A funded commercial
product ships it in its flagship sample. **This is the strongest available
evidence that the 0.5-unit grid-snap rule is both correct and non-obvious.**

The `free` model format matters practically: reaching `.geo.json` from this
file requires a conversion pass, and arbitrary three-axis cube rotations may
not survive it cleanly.

### Honest tension with our box-UV rule

At 512×512 with per-face UV, Orca gets far finer texture control than box UV
permits. Our box-UV-only rule is a **workflow constraint, not a universal
truth**: it is correct because we hand off to Blockbench auto-UV and paint a
template by hand. A pipeline that generates the atlas programmatically
alongside the geometry — as Orca's and Logeaddd's both do — can use per-face
sensibly. If this project ever grows a deterministic atlas generator, revisit
section 2.

### Not determined

Which models they use; whether their Bedrock path emits `.geo.json` natively
or converts from `.bbmodel`; whether Bedrock output is first-class or a
Java-first pipeline with an adapter. The sample being `free` format rather
than `bedrock` suggests the latter, but one artifact is not proof. Their
crossplay is Geyser on a Java server.

---

## 6. Recommended scope: block-family generator

Do not write a general model generator. Write a block-family generator as a
Regolith filter:

```
packs/data/geo_gen/blocks.json   {"name": "oak", "variants": ["slab","stair"]}
        |  filter: geo_gen  (runs against .regolith/tmp)
RP/models/blocks/*.geo.json
BP/blocks/*.json
RP/blocks.json + terrain_texture.json entries
        |  export
com.mojang/development_*_packs/
```

Filter inputs belong under `packs/data/<filter_name>/` — that is what
`dataPath` in `config.json` is for. Generated geometry lands in the export
target, not back in `packs/`, so it is never committed.

Start from hand-authored template `.geo.json` files with correct UVs, and have
the filter do substitution and axis-scaling with paired UV adjustment — not
free-form geometry synthesis. The hard UV problem stays inside a few templates
a human got right once.

This works for blocks specifically because block textures are 16x16 and
generally tileable, geometry is axis-aligned, and slabs/stairs/panels/fences
are one template deformed on one or two axes.

Reference — a vanilla-correct slab, where UV height tracks geometry height:

```json
{
  "format_version": "1.12.0",
  "minecraft:geometry": [{
    "description": {
      "identifier": "geometry.slab",
      "texture_width": 16, "texture_height": 16,
      "visible_bounds_width": 2, "visible_bounds_height": 2.5,
      "visible_bounds_offset": [0, 0.75, 0]
    },
    "bones": [{
      "name": "bottom_slab",
      "pivot": [0, 0, 0],
      "cubes": [{
        "origin": [-8, 0, -8],
        "size": [16, 8, 16],
        "uv": {
          "north": {"uv": [0, 8], "uv_size": [16, 8]},
          "east":  {"uv": [0, 8], "uv_size": [16, 8]},
          "south": {"uv": [0, 8], "uv_size": [16, 8]},
          "west":  {"uv": [0, 8], "uv_size": [16, 8]},
          "up":    {"uv": [16, 16], "uv_size": [-16, -16]},
          "down":  {"uv": [16, 16], "uv_size": [-16, -16]}
        }
      }]
    }]
  }]
}
```

Community note worth knowing: vanilla trapdoors have two known defects — wrong
texture direction on some faces, and an actual height of 3 displayed as 2.95.
Community templates fix both. Do not assume vanilla geometry is a correct
reference.

For anything organic or non-axis-aligned: Blockbench, by hand.

---
---
