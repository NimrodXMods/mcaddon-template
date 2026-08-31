# mcaddon-template

Note: this is a work in progress and is still far from complete.

A template repository for Minecraft **Bedrock Edition** add-ons, built to be
usable by coding agents (Claude Code) with a human for direction, art assets,
overall design, and general masterminding.

It wires together:

- **[Regolith](https://regolith-docs.readthedocs.io/)** — non-destructive
  filter pipeline: `packs/BP` and `packs/RP` are the committed source of
  truth; builds are compiled copies, never written back.
- Optional `jsonte` templating examples.
- **[Minecraft Creator Tools](https://github.com/Mojang/minecraft-creator-tools)**
  (`mct`) — Mojang's validator, renderer, and packager.
- **A hard verify gate** — `./scripts/verify.sh` compiles and validates, and
  nothing is "done" until it exits 0. CI runs the same script.

The goal is to deliver at least one example of everything, possibly more than
one depending on feature — deliberately minimal, using vanilla geometry, all
confirmed rendering in game.

A secondary goal is to include some more complex examples of specific behaviors
and game features.

## Where the real documentation is

**[`AGENTS.md`](AGENTS.md)** is the operating manual and source of truth:
toolchain setup, repo layout, authoring rules, and a table of the silent
failure modes this project has actually hit. `CLAUDE.md` holds only
Claude-Code-specific harness notes. `docs/` holds working notes per content
type, each split into lessons verified here versus inherited research —
see `docs/decisions.md` for why the project is shaped the way it is.

## Quick start

Prerequisites and exact install steps are in `AGENTS.md` (sections 1–3).
Once the toolchain is in place:

```bash
./scripts/verify.sh          # compile + validate; the completion gate
./scripts/verify.sh ci       # same gate, CI profile (no com.mojang needed)
./scripts/deploy.sh          # verify, build, and package a .mcaddon into build/
```

## Using this as a template

When instantiating a new project from this repo, at minimum:

1. Rename the project (`config.json` `name`, manifest names/descriptions —
   the directory `packs/RP/textures/<creator>/<gamename>/` layout too).
2. **Randomize every UUID** in both manifests, including `modules[].uuid`
   (`mct fix randomizealluids` misses those — see the gotcha table in
   `AGENTS.md`).
3. Decide per-project whether to enable Beta APIs (required for GameTest;
   deliberately off here — see `docs/decisions.md`).

## Brief human reference for the files

- `config.json` - Regolith's project file. Regolith is a pre-processor which
  helps to assemble the json definitions used by the game. It consists of
  "filters" which generate different data from a single source of truth
  so that references are not constantly getting out of sync and you're not
  having to retype the same stuff in several places all the time.

- `packs/BP` and `packs/RP` - These directories contain the json data used
  by the game, but in addition to plain data they can also contain `.templ`
  and `.modl` files that can contain substitution and expansion directives
  to make various things (like multiple variants) more maintainable.

- `packs/data` - contains macro definitions used by the preprocessor, such
  as the project version number. Any data needed by multiple files can be
  defined here once and used as single source of truth for insertion
  everywhere. The data is in filter-specific subdirectories.

- `scripts` - contains the build/deploy/ci scripts used to invoke regolith
  which do `regolith run`, `mct validate`, plus some workarounds.

## Build artifact directories

- `reports` - contains verification reporting from `mct validate` and gets
  wiped and recreated on each run.
- `.regolith` - the regolith filters and soem data files end up here.
  Deleting the whole directory means the filters must be reinstalled.
- `.regolith/tmp` - this is the per-run working directory and it can be
  safely deleted and rebuilt by running regolith.
- `build` - when the regolith profile's target is set to `local` the addon
  BP/RP files of the final form consumed by minecraft end up here. `deploy.sh`
  also runs `mct exportaddon` to place the output artifacts here. (When
  regolith is run with a profile that has target set to `development` the
  output files are placed in the `com.mojang/devel*` directories directly
  instead for more easy testing.)
- `out` - this only appears if you run `mct exportaddon` manually with the
  default output directory name.
