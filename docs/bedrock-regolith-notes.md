# Regolith pipeline notes

**Planned skill:** `bedrock-regolith`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-regolith/SKILL.md` only after the pipeline has been reshaped at least once for real needs - a custom filter, or a non-trivial profile. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

The filter pipeline, profiles, export targets, and the source/output
direction.

## Confirmed lessons

- **`packs/BP` and `packs/RP` are source, not output.** Regolith copies them to
  `.regolith/tmp`, filters the copy, and exports to the target. It never writes
  back. Do not deny writes to `packs/`.
- One thing does write into `packs/`, and it is not a filter: `mct
  exportaddon` rewrites manifest dependency versions incorrectly -
  `scripts/deploy.sh` guards it. (It was initially blamed on `bump_manifest`;
  see `docs/decisions.md`.)
- `regolith install <filter> --profile=default` wires the filter into the
  profile. **Without `--profile` you get a populated `filterDefinitions` and an
  empty profile** - filters downloaded, pinned, and never run.
- `--profile` only works on first install. Afterwards install refuses and
  suggests `--update`, which re-resolves and can bump pins. Edit `config.json`
  by hand instead; the docs endorse this.
- Profiles: `default` exports to `com.mojang`; `ci` and `build` export to
  `local` (CI runners have no `com.mojang`). `build` additionally runs
  `bump_manifest`; `default` and `ci` differ only by export target.
- `.regolith/` is gitignored, so CI needs `regolith install-all` before running
  anything - the filter cache does not exist on a fresh checkout.
- `regolith run <profile>` selects a profile; bare `regolith run` uses
  `default`.
- The `local` export target writes into `build/` **inside the project**, which
  `mct validate` then scans alongside `packs/` and double-counts. Clear it
  before validating.
- Filter settings are per-filter and easy to under-specify: `name_ninja`
  emitted an empty `.lang` until per-type settings blocks (`entities` /
  `blocks` / `items` / `spawn_eggs`, each with `auto_name`) were added.
- `name_ninja`'s `language` setting is deprecated in favour of `languages`,
  which takes a list.
- Regolith names the export folder from `config.json`'s `name`, so a
  placeholder name ships packs called "Project name_bp" into `com.mojang`.

### Export targets are hardcoded in the binary

Verified 2026-08-30 on regolith 1.8.0. `"target"` takes a **keyword**, not a
path, and the path it maps to is compiled into regolith - it is not in
`config.json`, not in `%LOCALAPPDATA%\regolith\user_config.json`, and not in
`regolith config --full` (which prints defaults too, and lists no export-path
key of any kind).

- `development` - platform detection finds the Minecraft install. Here it
  resolves to
  `%APPDATA%\Minecraft Bedrock\Users\Shared\games\com.mojang\development_*_packs`.
  The legacy UWP tree
  (`%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\...`)
  is **empty** - do not go looking there.
- `local` - `./build/<name>_bp` and `./build/<name>_rp`, project-relative.
  Confirmed by running the `ci` profile into a nonexistent `build/`:
  `Exporting behavior pack to "build/AddOnTemplate_bp/"`.

The consequence: `development` is **non-portable** - it resolves to whatever
that machine's install is, and to nothing usable without Minecraft. That is
the whole reason `ci` and `build` exist. To name a directory yourself the
escape hatch is not a config key but a different target: `exact`, with a
`path`.

### The cache holds filters; `packs/data` holds state

Three distinct things, easily conflated:

- `.regolith/cache/filters/<name>/` - the downloaded filter **code**, pinned to
  the `version` in `filterDefinitions` (`jsonte.exe`, `bump_manifest.py`, ...).
  The `data/` folder inside each is **seed** data, a template copied out to
  `dataPath` on install - a source to copy from, not live state.
- `packs/data/<name>/` - the real state, and git-tracked so it survives a cache
  wipe. Mixes data you author for reuse (`jsonte/data.json`) with state filters
  write back (`bump_manifest/version.json`).
- `.regolith/tmp/` - per-run scratch, rebuilt from `packs/` every run.

The one stateful file in the cache is `.regolith/cache/edited_files.json`,
which lists every file regolith wrote into each export target so the next run
can delete stale ones instead of orphaning them. Losing it causes the deletion
safety check failure in the gotcha table.

### Cleaning and reinstalling

- `regolith clean` is the sanctioned way to wipe the cache; `regolith
  install-all` restores it from `filterDefinitions`.
- **`install-all` prunes.** It installs only what `filterDefinitions` lists, so
  cache directories for removed filters disappear. This is how the stale
  `command_lang` and `modular_mc` directories were cleared.
- Regolith never prunes the cache on its own - removing a filter from
  `config.json` leaves its cache directory behind indefinitely.
- `regolith clean` prints a path under
  `%LOCALAPPDATA%\regolith\project-cache\<hash>` even with
  `use_project_app_data_storage: false`. Not investigated.

### Resolvers are an install-time index only

`user_config.json` lists resolvers; regolith keeps each as a **full git clone**
at `%LOCALAPPDATA%\regolith\resolver-cache\<md5-of-url>\`, refreshed subject
to `resolver_cache_update_cooldown` (5m default).

A `resolver.json` is just a name -> repo-URL phone book:

```json
{ "filters": { "name_ninja": { "url": "github.com/Bedrock-OSS/regolith-filters" },
               "jsonte":     { "url": "github.com/MCDevKit/regolith-library" } } }
```

Note `jsonte` resolves out to a different org than the resolver listing it -
the resolver is an index, not a host. The list is **ordered, first match
wins**: `[0]` is the user-added `bedrock-core` resolver, `[1]` regolith's
built-in `Bedrock-OSS` default.

This only matters for `regolith install <bare-name>`, which expands the name
and writes a pinned `url` + `version` into `filterDefinitions`. **Builds never
consult a resolver** - a fresh clone builds from `filterDefinitions` alone.

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- `bump_manifest` updates its `packs/data/bump_manifest/version.json` state
  file so bumped versions persist between builds. Documented filter
  behaviour, but that file is byte-identical to its initial commit, so no
  bump has ever been observed here.
- Enabling three of `name_ninja`'s four per-type blocks silently omits the
  fourth. Inferred from the per-type settings structure; all four were
  enabled in a single commit, so a partial configuration never ran.

## Open questions

- Writing a custom filter (Python or Node) - none written yet.
- `filterDefinitions` version pinning strategy over time.
- Whether `dataPath` is worth using for more than filter state.
