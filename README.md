# mcaddon-template

A template repository for Minecraft **Bedrock Edition** add-ons, built to be
worked on by coding agents (Claude Code) with a human in the loop for art
assets. It wires together:

- **[Regolith](https://regolith-docs.readthedocs.io/)** — non-destructive
  filter pipeline: `packs/BP` and `packs/RP` are the committed source of
  truth; builds are compiled copies, never written back.
- **[Minecraft Creator Tools](https://github.com/Mojang/minecraft-creator-tools)**
  (`mct`) — Mojang's validator, renderer, and packager.
- **A hard verify gate** — `./scripts/verify.sh` compiles and validates, and
  nothing is "done" until it exits 0. CI runs the same script.

The template ships one working entity, one block, and one item — deliberately
minimal, using vanilla geometry, all confirmed rendering in game.

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
