# World generation and biome notes

**Planned skill:** `bedrock-worldgen`
**Status:** notes only - **nothing here is verified in this project.**

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-worldgen/SKILL.md` only after custom world generation
has actually shipped here and stopped surprising us. Right now the project has
**no worldgen content at all** - no `biomes/`, `features/`, `feature_rules/`,
`structures/` or `worldgen/` directory exists under `packs/BP`.

Treat this file the way `AGENTS.md` says to treat any unverified section: as a
research pointer, not as instructions. Every claim below is second-hand.

## What the skill must cover

Custom biomes, features and feature rules; the placement pipeline; the
BP-only file layout; and whether any of it needs experimental toggles.

## Why this is wanted here

The template has an entity, a block, an item and a loot table, but nothing
that touches terrain. A worldgen example is a genuine gap in the template's
coverage - and unlike the entity work, none of the existing notes transfer:
features and feature rules are a placement pipeline, not a state chart.

## Inherited from research - NOT verified here

From the Bedrock Wiki world-generation introduction
(<https://wiki.bedrock.dev/world-generation/world-generation-intro>),
retrieved 2026-08-30. None of this has been run.

- **All worldgen content is Behavior Pack.** There is no RP side. The
  directories are `biomes/`, `features/`, `feature_rules/`, `structures/`
  (holding `.mcstructure` files exported from Structure Blocks), and
  `worldgen/` for jigsaw structures.
- **Top-level identifiers** are per file type: `minecraft:biome`,
  `minecraft:ore_feature`, `minecraft:single_block_feature`,
  `minecraft:structure_template_feature`, `minecraft:feature_rules`.
- **Filenames must match the identifier** (the namespace is optional in the
  filename). This is a stricter rule than entities follow here, and worth
  testing early.
- **`format_version` again runs on independent lines.** The wiki gives biomes
  `1.26.40` and features / feature rules `1.13.0`. Given what
  `docs/bedrock-entity-notes.md` records about per-component silent drops at
  the wrong `format_version`, expect this to be the first thing that bites.
- **`replace_biomes`** is described as the most important biome component.
- **Do not use `noise_type` and `noise_params` together.** Called out
  explicitly as an error.
- Jigsaw structures may span up to 256 blocks.
- **Structure features cannot be found with `/locate`**; jigsaw structures
  can. That matters for verification - `/locate` is the obvious way to prove
  a structure generated, and for one of the two kinds it will not work.
- Custom generated structures are stated as possible since 1.16.20. Whether
  any of this needs an experimental toggle in the world settings is **not
  established** - the wiki does not say plainly, and a world-creation toggle
  is exactly the class of thing that `mct validate` cannot see. Compare the
  `domobspawning` case in the `AGENTS.md` gotcha table: the pack was fine and
  the world was wrong.

## Candidate filter: `minifeature`

<https://github.com/BigChungus21220/minifeature-regolith-filter> -
docs at <https://bigchungus21220.github.io/minifeature-regolith-filter/>.

**Note on reading those docs:** the site is client-rendered and returns an
empty shell to a plain fetch. It needs a JS-executing scrape to read at all.
Everything below came from such a scrape on 2026-08-30 and is **documentation,
not verified behaviour** - the filter is not installed here.

Self-described as *"a preprocessor for MCBE world gen features"*, giving inline
feature definition, templating, variables, namespacing, and multiple features
per file. It is in the default resolver:

```bash
regolith install minifeature --profile=default
```

`--profile=default` is not optional - see `docs/bedrock-regolith-notes.md`.

### Shape of it

- **Input** lives in `BP/minifeatures/` as `.yaml`, `.json` or `.jsonc`.
  **`.yaml` is recommended by the author** because multiline strings allow
  clean inline molang.
- **Output** is generated into `BP/features/` and `BP/feature_rules/` - so
  those directories become *derived*, not source. That is the same
  source/output split the rest of this project already runs on, and it means
  hand-editing a generated feature is the usual heisenbug.
- Settings, with defaults - omitted fields take the default:

  ```
  features_directory       ./BP/features        # output
  feature_rules_directory  ./BP/feature_rules   # output
  minifeatures_directory   ./BP/minifeatures    # input
  project_namespace        minifeature          # vanilla namespace for output
  namespaced_subfolders    true                 # split output by namespace
  ```

- A file opens with a `namespace`; several files may share one. Feature names
  are lowercase, starting with a letter or underscore.
- Features carry a `type`, and **the type names are the filter's own, not the
  vanilla identifiers** - `block` maps to `minecraft:single_block_feature`,
  `scatter` to `minecraft:scatter_feature`. Expect a translation step when
  cross-referencing the wiki. Types: `rule`, `aggregate`, `conditional_list`,
  `block`, `geode`, `growing_plant`, `ore`, `scatter`, `search`, `structure`,
  `surface_snap`, `vegetation_patch`, `weighted_random`.
- A feature may place another **four** ways: inline definition, local
  reference, namespaced reference (`otherfile.myblock`), or vanilla reference
  (`minecraft:oak_tree_feature`). The inline form is the interesting one -
  vanilla requires every feature to be its own file with its own identifier.
- Variables are `$name$` and hold any value, object or array. They also
  interpolate **inside molang strings**, which is the templated-molang claim.
  Variables are **scoped**: the docs' own example shows a reference failing to
  resolve because it is out of scope, silently. Templates are written
  `<name>` and expand to inline features rather than becoming features
  themselves.
- VSCode validation is available by pointing `json.schemas` / `yaml.schemas`
  at the repo's `feature_file.schema.json` for `**/*.minifeature.{json,yaml}`.

### Gotchas the schema itself records

Worth capturing because they are vanilla worldgen behaviour, not filter
quirks, and they will bite whether or not this filter is used:

- `vegetation_patch.waterlogged` - *"Do not set this to true, it's buggy. Use
  a scatter feature instead."*
- `growing_plant.allow_water` - *"this may be buggy."*
- `structure.facing_direction` - `south` is *"usually the most stable"*.
- `feature_rule.placement_pass` has eleven values from `pregeneration_pass`
  through `final_pass`; picking the wrong one is a plausible silent no-op.

### Decision still open

The overlap with `jsonte` is real but narrower than it first looked. `jsonte`
gives generic JSON templating; `minifeature` gives a **domain model** - typed
features, feature references, and the inline/nested composition vanilla will
not let you express in one file. Whether that is worth a second preprocessor
in the build is the actual question, and it cannot be settled without writing
a feature both ways.

Standard caution from `docs/decisions.md`: every filter in `filterDefinitions`
is a supply-chain dependency, and this is a single-author repo.

## Open questions

- Does any of this require an experimental toggle at world creation?
- Can `jsonte` express feature composition well enough that `minifeature` is
  redundant? Write one feature both ways before deciding.
- How is worldgen verified at all? `mct validate` checks structure and
  conventions, not behaviour, and `/locate` does not work for structure
  features. Proving a feature generated may need a fixed seed and manual
  inspection, which no existing gate here covers.
- Does the filename-matches-identifier rule interact with the Cooperative
  Add-On folder rules that already bit `loot_tables/`?
