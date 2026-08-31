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
docs at <https://bigchungus21220.github.io/minifeature-regolith-filter/>
(the docs site rendered as an empty JS shell on 2026-08-30; the README is
currently the usable source).

Self-described as *"a preprocessor for MCBE world gen features"*, offering
inline feature definitions, templating, variables, namespacing, and multiple
features defined per file. It is in the default resolver, so the short install
form works:

```bash
regolith install minifeature --profile=default
```

`--profile=default` is not optional - see `docs/bedrock-regolith-notes.md` for
why omitting it silently yields a pinned filter that never runs, and why it
only works on first install.

**Unknown and worth establishing before adopting it:** the input file
extension and syntax, the settings block shape, and whether it overlaps
`jsonte`, which already provides templating, variables and modules here. Two
preprocessors covering the same ground would be a real cost. Evaluate whether
plain `jsonte` can generate feature JSON acceptably before adding a
second-preprocessor dependency to the build.

Standard caution from `docs/decisions.md`: every filter added to
`filterDefinitions` is a supply-chain dependency of the build, and this is a
single-author repo.

## Open questions

- Does any of this require an experimental toggle at world creation?
- Can `jsonte` generate features well enough that `minifeature` is redundant?
- How is worldgen verified at all? `mct validate` checks structure and
  conventions, not behaviour, and `/locate` does not work for structure
  features. Proving a feature generated may need a fixed seed and manual
  inspection, which no existing gate here covers.
- Does the filename-matches-identifier rule interact with the Cooperative
  Add-On folder rules that already bit `loot_tables/`?
