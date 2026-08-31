# AGENTS.md

Operating manual for any agent working on Minecraft Bedrock add-ons in this
repo. This is the source of truth; `CLAUDE.md` holds only Claude-specific
notes and defers here for everything else.

This repo is a **template**. It is the starting point for every other Bedrock
project, so the guidance here is written to be general, not specific to
whatever content currently lives in `packs/`.

## Read this first

- **`packs/BP` and `packs/RP` are source, not build output.** Author there.
  Regolith copies them to `.regolith/tmp`, filters the copy, and exports to
  `com.mojang`. It never writes back. Section 1 of the repo-structure part
  covers this; getting it backwards is the single most consequential mistake
  available in this project.
- **Nothing is done until `./scripts/verify.sh` exits 0.** Not "looks right",
  not "should work". Section 3g.
- **Read schemas from `../mcbe-schemas/`, do not recall component names.**
  They drift every release. The clone is deliberately outside the repo root.
- **Do not author `.geo.json`, `.bbmodel`, or `.png`.** Those are human
  artifacts from Blockbench. Read and render them; never write them.

## What is in this file

| Part | Covers |
| --- | --- |
| Toolchain + harness setup (0-10) | Prerequisites, mct, Regolith, MCDevKit filters, VS Code, Blockbench, MCP wiring, permissions, install order |
| Repo structure and bootstrap (1-6) | The source/output invariant, directory layout, exact bootstrap commands, the verify gate, CI, the agent contract, and a table of silent failure modes |

Model authoring lives outside this file:

| Document | Audience |
| --- | --- |
| `docs/model-authoring-human.md` | Blockbench workflow, UV modes, tooling survey |
| `docs/model-authoring-agent.md` | Geometry rules for drafting `.geo.json` - destined for a `bedrock-geometry` skill |
| `docs/decisions.md` | Why the project is shaped as it is, with evidence |

## Status and provenance

The original draft was research output from other agents. Much of it has since
been checked against the installed toolchain and corrected; several claims that
sounded reasonable turned out to be wrong in ways that would have cost real
debugging time. Where a section records a defect or a surprising behaviour, it
was reproduced on this machine, not inferred.

Known-verified on this machine: the Regolith source/output direction, the
`verify.sh` gate (proven to fail on a broken project and pass on a clean one),
the `mct fix randomizealluids` module-UUID gap, `mct exportaddon` rewriting
source manifests, the `cmcc` licensing requirement, the Cooperative Add-On
texture layout, and the whole template rendering correctly in game.

Treat version numbers and third-party claims in the tooling commentary as
of-their-time rather than current fact.

**When you find something here that is wrong, fix it in place** rather than
working around it. Delete sections that stop earning their space. The intent
is for this file to eventually shed material into focused skills under
`.claude/skills/`; until then it stays here, and staying accurate matters more
than staying short.

Maintenance TODO:

- Link-rot pass over the external URLs in this file and `docs/` (the
  MCDevKit site, the Regolith docs, the Blockbench wiki, and especially the
  small third-party repos surveyed in `docs/model-authoring-human.md` 5a).

## Bedrock Add-On Toolchain + Claude Code Harness Setup

Target: a shell-driven agent harness (Claude Code CLI/TUI) with VS Code as the
human editor. Everything the agent touches is a CLI binary, so nothing depends
on the VS Code extension host.

---

## 0. Design constraints this setup assumes

- The agent authors pack content directly in `packs/BP` and `packs/RP` —
  plain JSON, or `.templ`/`.mcc` sources that regolith filters expand at run
  time.
- Regolith output goes to the profile's export target (`com.mojang`), never
  back into `packs/`. The export target and `.regolith/` are agent-read-only.
- Every agent turn ends with a validate run. No "looks right" completions.
- Blockbench remains human-only. Agents do not author `.geo.json`.

---

## 1. Prerequisites

| Dep | Version | Why |
| ----- | --------- | ----- |
| Node.js | 22+ | hard requirement of `@minecraft/creator-tools` |
| npm | 10+ | same |
| Go | recent | only if building Regolith from source; prebuilt binaries exist |
| Java | 11+ | required by jsonte (JSON Templating Engine) |
| git | any | Regolith's `install` command shells out to git |
| Python 3 | optional | writing custom Regolith filters |

Verify:

```bash
node --version    # must be >= 22
npm --version     # must be >= 10
java -version     # must be >= 11
git --version
```

---

## 2. Minecraft Creator Tools (Mojang, first-party)

The backbone: validator, renderer, deployer, scaffolder, and MCP server.
Source and issue tracker: <https://github.com/Mojang/minecraft-creator-tools>.

```bash
npm install -g @minecraft/creator-tools
npx mct version
```

Accept the EULA:

```bash
npx mct eula
```

This is interactive and cannot be driven by an agent - a human must run it.

Correction to a claim earlier drafts carried: **the MCP server does start
without the EULA accepted.** Verified by sending an `initialize` request to
`mct mcp` on a machine where `mct eula` still re-prompts; it returned a normal
handshake. Expect `deploy` and world commands to be the ones that actually
block. Accept it anyway, but do not treat a re-prompting EULA as the
explanation for an MCP problem.

Sanity check the command surface:

```bash
npx mct --help
npx mct --all-commands     # includes internal/advanced commands
```

Status note: the package README describes itself as pre-release alpha. Pin a
version in CI rather than floating on latest.

### When `mct` is not on PATH

A global install can end up **incomplete**, and `verify.sh` then dies at
`timeout: failed to run command 'mct'` while `regolith run` succeeds - the gate
half-runs and looks like a project problem when it is an install problem.

**The cause is usually not creator-tools.** npm's global prefix is a single
shared tree: `npm install -g <anything>` re-reifies the whole thing and runs
**every** installed package's install scripts. One unrelated postinstall
failing aborts the entire transaction - after tarballs are extracted but before
package metadata and bin shims are finalized - so unrelated packages are left
half-written. Diagnosed here (2026-08-30) from the npm debug log:

```
error path   ...\node_modules\glslang-validator-prebuilt
error command cmd.exe /d /s /c node build.js
error Error: Cannot find module 'rimraf'
silly unfinished npm timer build:run:postinstall:node_modules/glslang-validator-prebuilt
```

Those `unfinished ... timer` lines are the tell that npm died mid-reify.
`glslang-validator-prebuilt` was the poison pill; creator-tools was collateral
damage and had no `mct` shim as a result.

Two diagnostics, in order:

1. `npm ls -g --depth=0` - **a package printed with an empty version after the
   `@` is half-installed.** That names the victim.
2. The npm debug log path the failure prints. Grep it for `error code` and
   `unfinished npm timer` - that names the *cause*, which is a different
   package.

A second, compounding failure mode on Windows: if a process has one of the
package's native addons (`.node`) mapped, npm cannot unlink it
(`EPERM ... unlink ... node.napi.node`) and leaves a stranded
`node_modules/@minecraft/.creator-tools-<hash>/` staging copy. Here that was
this repo's own `mct mcp` MCP server. **Stop the MCP server before a global
install that touches creator-tools.** See the gotcha table.

The workaround that never writes to the global tree at all:

```bash
npx -y -p @minecraft/creator-tools mct validate addon -i . -ot json -o reports --threads 8
```

Do **not** try to fix this by dropping a shell-script `mct` shim on PATH:
`verify.sh` invokes mct through `timeout`, which `exec`s directly, and Windows
cannot exec a shebang script. The shim is invisible to it. Either repair the
global install or run the two halves of the gate by hand.

Note also that repairing the tree can silently **change versions of unrelated
packages** - four were rolled back here as a side effect. Re-check
`npm ls -g --depth=0` afterwards.

### Command groups worth memorizing

| Group | Commands |
| ------- | ---------- |
| Validate | `validate` (`val`), `search`, `aggregatereports` |
| Project | `create`, `add`, `fix`, `set`, `info`, `setup`, `deploy`, `exportaddon`, `exportworld` |
| View/Edit | `view` (read-only web UI), `edit` (read-write web UI) |
| Server | `serve`, `mcp`, `dedicatedserve`, `passcodes`, `setserverprops`, `eula` |
| Render | `rendermodel`, `rendervanilla`, `renderstructure`, `buildstructure` |
| World | `world`, `ensureworld`, `deploytestworld` |

Global flags available everywhere: `-i/--input-folder`, `-o/--output-folder`,
`-v`, `-q`, `--json`, `--debug`, `--force`, `--dry-run`, `--threads <n>`,
`--all-commands`.

`--json` and `-ot json` are the flags that make mct agent-legible. Prefer them
over parsing human output.

---

## 3. Regolith (add-on compiler)

Install from <https://github.com/Bedrock-OSS/regolith/releases> (prebuilt
binaries), or from source with Go. Verify:

```bash
regolith --version
```

Regolith gives you a non-destructive filter pipeline. On `regolith run` it
copies `packs/BP` and `packs/RP` into `.regolith/tmp`, runs the filter chain
against that copy, and exports the result to the profile's export target. Your
source packs are never modified — which is what makes it safe to introduce new
syntax (`.templ`, `.mcc`) into add-ons, and is the layer that makes a DSL
possible on top of Bedrock's JSON.

Docs: <https://regolith-docs.readthedocs.io/>. The older
`bedrock-oss.github.io/regolith` URL now serves only a redirect notice.

### Standard library filters

```bash
regolith install texture_list      # generates texture_list.json
regolith install name_ninja        # generates .lang entries from JSON
regolith install bump_manifest     # auto-increments manifest versions
```

Filters not in the resolver repo install by full path:

```bash
regolith install github.com/<user>/<repo>/<folder>
```

Add extra resolvers:

```bash
regolith config resolvers --append github.com/bedrock-core/regolith-filters/resolver.json
```

---

## 4. MCDevKit (the DSL layer)

```bash
regolith install github.com/MCDevKit/regolith-library/jsonte --profile=default
```

- **jsonte** - JSON templating with its own query language. Source files use
  the `.templ` extension. Supports modules (predefined templates merged into
  others) for recurring structures. **Self-contained**: the filter ships
  platform binaries (`jsonte.exe` / `jsonte-mac` / `jsonte-linux`) and runs
  with no separate install. It scopes both `data/jsonte` and
  `data/json_templating_engine`; a `Skipping non-existent scope file` warning
  for whichever you do not have is benign — do not rename your data folder to
  chase it.
- **CommandLang** - a language over mcfunction. Provides annotations such as
  `query`, which binds a Molang query boolean to a field and injects the
  needed animation controller for you.

### The entity-authoring pattern

jsonte modules are how this repo gets a DSL-like authoring surface without a
custom filter. The rule that makes it worth doing:

> **A module owns a whole state machine — every component group, every event,
> and every sensor that references them — or it declares a dependency on one.**

The failure this prevents is the one nothing warns you about: a component
group that no event ever adds is dead code, and neither the engine nor
`mct validate` says a word. A module that can emit a group without its event
makes that failure *possible*; one that emits the closed loop makes it
*unrepresentable*. Tuning values come from `$scope` on the extending file, so
a second mob of the same shape differs by numbers, not by a copied state
machine.

Worked example: `packs/BP/modules/proximity_aggro.modl` +
`wandering.modl` → `packs/BP/entities/stalker.behavior.templ`. Note that
`wandering` deliberately does *not* own a state machine — it only contributes
behaviours into a group `proximity_aggro` defines, which is why its header
says to always `$extend` both together.

Where the line falls: the BP entity is a `.templ` because its state machine is
shared; the RP client entity stays literal `.json` because every field in it
is unique to that one mob.

**Every content type ships two worked examples** — one using only Regolith
standard-library filters, one using jsonte — so anyone who declines the
non-standard layer can still copy a working example. Entities have both
(`example_entity` plain, `stalker` templated); blocks and items do **not** yet.
See `docs/decisions.md`.

The selection criterion behind that, and behind rejecting `modular_mc`:
**prefer what the official tools understand.** mct classifies content by
pack-relative location, so a layer that relocates source out of `packs/`
silently drops it from `mct validate`. jsonte expands in place and keeps the
gate honest.

### Alternatives: evaluated and rejected

`system_template` is **superseded** by `modular_mc` (same author; its docs call
it "a TypeScript-based successor"). Do not evaluate `system_template`.

`modular_mc` was installed, probed against a real mob, and **reverted** on
2026-08-30. It works and coexists with jsonte, but it overlaps jsonte rather
than complementing it, and files moved into its modules stop being validated by
`mct`. Full reasoning in `docs/decisions.md`.

**Neither jsonte nor `modular_mc` is a Bedrock standard** — jsonte is absent
from the Bedrock-OSS standard library and unmentioned anywhere in the Regolith
repo. jsonte is a defensible local choice, not the industry default. The rule
this implies is in `docs/decisions.md`: a `bedrock-<thing>` skill teaches
Bedrock semantics, never tool syntax.

### command_lang requires `cmcc`, which is a paid product

**Decision for this project: CommandLang is not used**, and is not referenced
in `config.json` at all. `cmcc` is commercially licensed and `regolith
install` never fetches it, so wiring the filter into a profile without a
licence breaks every build. Rationale and what was removed:
`docs/decisions.md`. Templating is `jsonte`.

### jsonte

Standalone jsonte CLI is also useful for the agent to test expansion in
isolation: `jsonte eval <expr>` prints a result to console without a full
compile.

---

### JSON schemas

```bash
git clone --depth=1 https://github.com/Blockception/Minecraft-bedrock-json-schemas.git ../mcbe-schemas
cd ../mcbe-schemas
git submodule update --init --depth 1 bedrock-samples
```

**Always initialize the `bedrock-samples` submodule.** It is not optional
extra: a plain clone leaves `bedrock-samples/` empty (`git submodule status`
shows a leading `-`), and that directory is the project's only local copy of
**what vanilla actually contains** - reference and test assets both. The
schemas tell you the *shape* a component may take; `bedrock-samples` tells you
the *values* that really exist. Use `--depth 1`; the full history is large and
nothing here needs it.

Worked example of why: switching the template entities off `geometry.frog`
required real geometry identifiers and texture paths. mct's bundled data
suggested candidates, but only `bedrock-samples/resource_pack/` confirmed that
skeleton is `geometry.skeleton.v1.8` with
`textures/entity/skeleton/skeleton` - and that both are declared in the legacy
`1.8.0` format where the identifier is a **top-level key**, not an
`"identifier"` field, so grepping for `"identifier"` finds neither.

Useful paths inside it:

| Path | Holds |
| --- | --- |
| `bedrock-samples/resource_pack/entity/*.entity.json` | vanilla client entities - the authoritative geometry/texture/material/render-controller pairing for any vanilla mob |
| `bedrock-samples/resource_pack/models/entity/*.geo.json` | geometry definitions |
| `bedrock-samples/resource_pack/textures/entity/**` | vanilla texture paths safe to reference from your own RP |
| `bedrock-samples/behavior_pack/entities/*.json` | vanilla BP entities - component groups and events as Mojang writes them |

Schema filenames are not always what you would guess - for example
`behavior/animation_controllers/animation_controller.json` (singular) but
`behavior/animations/animations.json` (plural), and
`resource/animations/actor_animation.json`. Check the directory rather than
assuming.

Keep the clone on disk regardless of editor: the **agent** should read raw
schema files rather than rely on training-data recall of component names,
which drift every release.

### Canonical documentation

| Reference | Context7 ID | Use for |
| --- | --- | --- |
| [Minecraft Creator docs](https://learn.microsoft.com/en-us/minecraft/creator/) | `/microsoftdocs/minecraft-creator` | The documentation of record: component references, Molang, manifests, tutorials. First-party (Microsoft/Mojang). |
| [Script API reference](https://learn.microsoft.com/en-us/minecraft/creator/scriptapi/) | `/websites/learn_microsoft_en-us_minecraft_creator_scriptapi` | `@minecraft/server*` module APIs, GameTest. |
| [Bedrock Wiki](https://wiki.bedrock.dev/) | `/websites/wiki_bedrock_dev` | Community tutorials and gotchas the official docs skip. |
| [bedrock.dev](https://bedrock.dev/) | `/websites/bedrock_dev` | Community docs auto-generated from vanilla data - "what does vanilla actually contain". |
| [minecraft-creator-tools](https://github.com/Mojang/minecraft-creator-tools) | `/mojang/minecraft-creator-tools` | mct itself - command surface, defect reports, source of truth for its behaviour. |
| [Regolith docs](https://regolith-docs.readthedocs.io/) | `/bedrock-oss/regolith` | Filter pipeline, profiles, `config.json` format. |
| [Blockbench plugin docs](https://www.blockbench.net/wiki/docs/plugin/) | `/websites/web_blockbench_net` | The scripted model-manipulation route (see the model-authoring docs). |
| [MCDevKit](https://mcdevkit.com) | *(not on Context7)* | jsonte, CommandLang, cmcc licensing. |

The Context7 IDs are plain library identifiers usable by any agent with a
Context7 MCP client (Claude's wiring is noted in `CLAUDE.md`); all resolved
successfully on 2026-08-30. Prefer them over web search when digging into
any of these tools.

Precedence when sources disagree: what this project has **observed** beats
all documentation (see the gotcha table - e.g. the official docs call the
`{"texture": ...}` form of `minecraft:icon` merely *deprecated*, but here it
rendered the item invisible); the schemas in `../mcbe-schemas/` beat prose
docs for component shapes; the official docs beat community docs; and any of
these beats recall. Prefer `en-us` URLs when linking - other locales
(`en-ca`) redirect but are not canonical.

### VS Code mappings

The upstream repo ships `vscode-settings.json` at its root with 60+
`json.schemas` entries whose `url`s are remote `raw.githubusercontent.com`
links - so the editor needs no local clone.

Its `fileMatch` globs key off `behavior_packs/*/` or a leading `*BP*/` segment,
which does **not** match this project's `packs/BP/` layout. This repo therefore
keeps its own `.vscode/settings.json` with 27 explicit mappings using
`packs/BP` / `packs/RP` prefixes, pointed at those same remote URLs. Remote
rather than `../mcbe-schemas/...` on purpose: the mappings then survive the
clone being moved or deleted. Copy patterns from upstream when adding a content
type; keep the prefixes.

## 8. Claude Code harness config

### 8a. MCP server

`mct mcp` is plain stdio. It is not VS Code specific — the upstream docs just
use VS Code as the example client.

Project-scoped, `.mcp.json` at repo root.

### 8b. Existing skills/plugins — what actually exists

The `minecraft-gametest` skill is installed in`.claude/skills/`.

### 8c. Skills you write

Put in `.claude/skills/<name>/SKILL.md`. Write these *after* you've watched
the agent fail a few times, so they encode real failure modes rather than
guesses.

**Status: none of these exist yet.** The only skill currently installed is
`minecraft-gametest`. The table below is a roadmap, not an inventory - do not
assume a skill is available because it is listed here.

**A skill is written only after a real example of that thing has been authored
end to end** - built, validated, and confirmed in game. Until then, notes go in
`docs/<thing>-notes.md` and grow as things break. When the notes stop growing
on the next example, convert them to `.claude/skills/bedrock-<thing>/SKILL.md`.
Writing the skill first encodes guesses that read as authority; see
`docs/decisions.md`.

| Planned skill | Notes file | Covers |
| --- | --- | --- |
| `bedrock-verify` | `docs/bedrock-verify-notes.md` | The gate: run it, read the globbed `reports/*.mcr.json`, never claim done without a clean run |
| `bedrock-entity` | `docs/bedrock-entity-notes.md` | Component groups and events as a state chart; spawn rules |
| `bedrock-block` | `docs/bedrock-block-notes.md` | States, permutations, culling, and the blocks.json / terrain_texture.json / textures three-way contract |
| `bedrock-item` | `docs/bedrock-item-notes.md` | Item components, the icon/texture contract, recipes |
| `bedrock-rp-wiring` | `docs/bedrock-rp-wiring-notes.md` | client entity -> geometry / texture / render controller graph. Highest-failure area |
| `bedrock-molang` | `docs/bedrock-molang-notes.md` | Query namespaces, context validity, arrow-operator gotchas |
| `bedrock-jsonte` | `docs/bedrock-jsonte-notes.md` | `.templ` syntax, modules, when to template vs write literal JSON |
| `bedrock-regolith` | `docs/bedrock-regolith-notes.md` | Filter pipeline, profiles, export targets, source/output direction |
| `bedrock-worldgen` | `docs/bedrock-worldgen-notes.md` | Custom biomes, features and feature rules; BP-only, and unverified here |
| `bedrock-packaging` | `docs/bedrock-packaging-notes.md` | Manifest module types per format_version, the .mcpack/.mcaddon/.mctemplate/.mcworld split, world templates vs worldgen |
| `bedrock-geometry` | `docs/model-authoring-agent.md` | Bone trees, pivots, box UV, the silhouette gate |
| `bedrock-gametest` | `docs/gametest-notes.md` | GameTest structure, registration, assertions |

Each notes file separates lessons verified here from inherited research, and
says plainly where nothing has been verified - `bedrock-molang` records that
no Molang has been written rather than paraphrasing documentation.

### 8d. Permissions

See `.claude/settings.json`. The verify loop is allowed unprompted; commands
that mutate project identity or history (`git commit`/`push`, `mct create`/
`set`/`add`, the exports) are in `ask`; the rest is denied.

**Do not add `Edit(packs/**)` / `Write(packs/**)` to the deny list.** Earlier
drafts of this document did, on the false premise that `packs/` is compiler
output. It is source (see the repo-structure part, section 1), and denying it
blocks all authoring.

Rationale for what *is* denied:

- `deploy` / `deploytestworld` write into `com.mojang`. Keep that a deliberate
  human action until you trust the loop.
- `.regolith/`, `build/`, `reports/` are derived. Hand-editing them produces
  the classic heisenbug where the next run silently discards your change.
- `.geo.json`, `.bbmodel` and `.png` are matched **by extension, not by
  directory**. Models and textures live under `packs/RP/models/` and
  `packs/RP/textures/`, which must stay writable for ordinary pack authoring;
  a directory-wide deny there would be too broad. Relax the extension denies
  per-file while a model is still a draft.

**Know what these denies actually constrain.** `Write(**/*.png)` binds the
**Write and Edit tools** - not the filesystem. A Bash command
(`magick -size 16x16 xc:'#4A7C3F' out.png`, `python -c "...PIL..."`) writes a
`.png` without tripping it. Both ImageMagick and Pillow are installed here, so
this is reachable, not theoretical.

The policy that resolves this: **`Bash(magick:*)` is in the `ask` list**, and
the `.png` extension denies stay. So generating a placeholder texture is
allowed but always prompts - never silent - while the Write/Edit tools still
cannot touch art at all.

Why this shape rather than narrowing the deny to specific paths:

- **`deny` beats `allow` in Claude Code.** An allow cannot carve an exception
  out of `Write(**/*.png)`; the deny wins. Narrowing would mean replacing the
  extension deny with path denies, and protection would become path-based -
  every new art directory would have to be added to the deny list, and a
  forgotten one is unprotected.
- **The Write tool cannot emit binary anyway.** PNG creation necessarily goes
  through Bash, so gating the Bash command is where the real control is. The
  extension deny is what stops an agent clobbering a real texture with text.

Placeholder textures go in `packs/RP/textures/nimrodx/common/entity/`.
**Both halves of the CADDONREQ rule are confirmed by experiment here**
(2026-08-30), not just documented:

| Path | `./scripts/verify.sh ci` |
| --- | --- |
| `nimrodx/common/entity/*.png` | clean; content file count 16 -> 17, so it really was scanned |
| `nimrodx/testdir/entity/*.png` | **CADDONREQ108** - "Secondary folder 'nimrodx_template' in textures has more than one subfolder (besides 'common')" |

So `common` is genuinely special-cased, and a second ordinary subfolder fails
the gate. Note `magick` is the ImageMagick entry point - on Windows,
`convert` resolves to `C:\Windows\System32\convert`, the disk utility.

The `ask` list covers things that mutate project identity or history
(`git commit`/`push`, `mct create`/`set`/`add`, the export commands) - allowed,
but with a confirmation step.

---

## 9. Smoke test

Prove the toolchain by hand before trusting any agent loop. In this repo that
is just `./scripts/verify.sh` - it runs regolith and mct end to end and exits
nonzero on anything wrong.

For a fresh machine, prove each layer separately: `mct --version`,
`mct eula --status`, `regolith --version`, then `regolith run` and
`mct validate addon -i . -v` on a scaffolded project.

---

## 10. Toolchain install order summary

1. Node 22+, npm 10+, Java 11+, Go, git
2. `npm i -g @minecraft/creator-tools` → `npx mct eula`
3. Regolith binary
4. `regolith install` std-lib filters + jsonte
5. VS Code + Blockception extension; clone schemas repo
6. [Blockbench](https://www.blockbench.net/)
7. [bridge.](https://bridge-core.app) (optional, inspector role)
8. Manual smoke test
9. `.mcp.json`, `.claude/settings.json`, `CLAUDE.md`, skills
10. `mrquentin/minecraft-skills` for the GameTest skill only

# Bedrock Add-On Repo Structure and Bootstrap

---

## 1. The central invariant

```
packs/BP/, packs/RP/  -- SOURCE OF TRUTH; humans and agents write here (tracked)
packs/data/           -- filter data AND filter-written state (dataPath) (tracked)
.regolith/cache/      -- downloaded filter code + edited_files.json    (ignored)
.regolith/tmp/        -- scratch copy filters actually run against     (ignored)
com.mojang/           -- real output; outside the repo entirely
build/                -- `local`-target export trees, and the packaged
                         .mcaddon from `mct exportaddon`               (ignored)
reports/              -- mct validator output, wiped each run          (ignored)
```

**Regolith is not a `source/` -> `packs/` compiler.** `packs/BP` and `packs/RP`
are the source you edit. On `regolith run`, regolith copies them into
`.regolith/tmp`, runs the filter chain against that copy, and exports the
result to the profile's export target — by default the `development_*_packs`
folders under `com.mojang`. It never writes back into `packs/`.

**Where `com.mojang` is** (verified 2026-08-30: regolith exports here and the
game loads the add-on from here):

```
%APPDATA%\Minecraft Bedrock\Users\Shared\games\com.mojang
```

An old UWP install can leave a second, stale tree at
`%LOCALAPPDATA%\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang`
that the current game does **not** read — on this machine its
`development_behavior_packs` sits empty while the path above receives the
exports. If a deployed pack never shows up in game, check which tree is
receiving writes (file timestamps) before blaming the pipeline.

Two exceptions, neither of them regolith's doing:

- `bump_manifest` updates its `packs/data/bump_manifest/version.json` state
  file so versions persist between builds. Expected.
- `mct exportaddon` rewrites script module dependency versions in
  `packs/BP/manifest.json`, and gets the format wrong. See the gotcha table;
  `scripts/deploy.sh` guards against it.

Verified empirically: with `texture_list` wired into the profile, a run left
`packs/` byte-identical, and the generated `textures_list.json` appeared only
in the export target.

The consequence for agents is the opposite of what a "generated output" reading
would suggest: `packs/` is the **only** place to author content, and it must
stay writable. Do **not** put `Edit(packs/**)` or `Write(packs/**)` in the deny
list of `.claude/settings.json` — that blocks all work.

What is genuinely off-limits is the derived side: `.regolith/`, `build/`,
`reports/`, and the `com.mojang` export target. Hand-editing any of those
produces the classic heisenbug, because the next `regolith run` overwrites it.
Enforce that in `.claude/settings.json`, not just in prose.

---

## 2. Layout

```
my-addon/
├── .claude/
│   ├── settings.json           # permissions; packs/ must stay WRITABLE
│   ├── settings.local.json     # MCP enablement (machine-local)
│   └── skills/
│       ├── bedrock-verify/SKILL.md
│       ├── bedrock-entity/SKILL.md
│       ├── bedrock-block/SKILL.md
│       ├── bedrock-rp-wiring/SKILL.md
│       ├── bedrock-molang/SKILL.md
│       ├── bedrock-jsonte/SKILL.md
│       └── bedrock-regolith/SKILL.md
├── .vscode/
│   ├── settings.json           # Blockception json.schemas mappings
│   └── mcp.json                # optional; only if using VS Code MCP
├── .mcp.json                   # Claude Code -> mct mcp
├── AGENTS.md                   # agent operating rules (source of truth)
├── CLAUDE.md                   # Claude-specific notes only
├── config.json                 # Project Config Standard + regolith namespace
├── .gitignore
│
├── packs/                      # SOURCE OF TRUTH - authored here, git tracked
│   ├── BP/                     # behavior pack
│   │   ├── manifest.json
│   │   ├── entities/           # .json, or .templ for jsonte
│   │   ├── modules/            # .modl - jsonte $module definitions
│   │   ├── blocks/
│   │   ├── items/
│   │   ├── functions/          # .mcfunction
│   │   └── scripts/            # Script API TypeScript
│   ├── RP/                     # resource pack
│   │   ├── manifest.json
│   │   ├── entity/             # client entity definitions
│   │   ├── render_controllers/
│   │   ├── models/entity/      # .geo.json from Blockbench (HUMAN ONLY)
│   │   └── textures/           # .png source art (HUMAN ONLY)
│   └── data/                   # regolith filter data (dataPath)
│       ├── jsonte/             # data.json - inputs consumed by templates
│       └── bump_manifest/
│
├── filters/                    # local regolith filters (runWith + script)
│   └── prune_empty_dirs.py
│
├── scripts/
│   ├── verify.sh
│   └── deploy.sh
│
├── docs/                       # notes that are not yet skills
│   ├── decisions.md            # why the project is shaped this way
│   ├── gametest-notes.md
│   └── model-authoring-*.md
│
├── .regolith/                  # gitignored - filter cache + tmp
├── build/                      # gitignored
└── reports/                    # gitignored

../mcbe-schemas/                # sibling clone, deliberately OUTSIDE the repo
└── bedrock-samples/            # submodule - MUST be init'd; vanilla assets
```

Template and CommandLang sources live **inside** `packs/`, alongside the JSON
they expand into — jsonte discovers `.templ` by
scanning the temp copy of the packs. There is no separate templates directory.

`packs/BP/modules/` is a *requirement*, not a preference: the jsonte filter
compiles only `BP/` and `RP/`, so a `.modl` module placed in `packs/data/jsonte/`
is never loaded and fails silently. `data/jsonte` is a variable *scope* path,
not a module search path. See `docs/bedrock-jsonte-notes.md`.

`../mcbe-schemas` is kept outside the project on purpose. The gate now
validates `build/` rather than the project root, so the clone is no longer in
the scan path of `verify.sh` — but keep it outside anyway: any ad-hoc
`mct validate -i .` still walks it, and the schema clone's ~1200 files
swamp the report (1221 files scanned vs 8) and emit spurious
`Could not load biome definition: SyntaxError` errors - mct tries to read the
biome *schemas* as biome *definitions*. Reproduce with
`mct validate addon -i ../mcbe-schemas`. Those particular errors are logged to
stderr but never reach `info.errorCount`, so they would not fail the gate;
the reason to move the clone out is report noise, not a false failure.

Initializing the `bedrock-samples` submodule makes this **much** more
important: it adds the whole vanilla resource and behaviour pack to that tree.
Keeping it a sibling is what lets the gate stay at "16 content / 37 total
files scanned" instead of tens of thousands.

### `.gitignore`

Derived output only: `/build`, `/reports`, `/out`, `/.regolith`,
`node_modules/`, `*.mcaddon`, `*.mcworld`. See the file.

Keep `packs/` **tracked** — it is your source, so this is ordinary version
control rather than a special case.

Note what this means for review: a PR diff of `packs/` shows what you authored,
**not** what the game loads. Filter-generated files (`textures_list.json`,
name_ninja's `.lang` entries, bumped manifest versions) exist only in the
export target and never appear in a diff. To review expanded output, inspect
the export target or run a `local`-target profile into `build/`.

---

## 3. Bootstrap: exact commands, exact directories

Run each from the directory shown.

### 3a. Create the git repo

```bash
# from wherever you keep projects
mkdir my-addon && cd my-addon
git init
```

### 3b. Scaffold with mct

Non-interactive form, which is what an agent must use (the Bash tool cannot
answer prompts):

```bash
# from: my-addon/
mct create -y -o . <name> <template> <creator> "<description>"
mct create -y -o ./myproj                    # all defaults
```

**`create` can appear to hang for many minutes.** That is a network stall,
not an mct defect - see "An mct command runs for minutes" in the gotcha table
(section 6 of the repo-structure part) for the diagnosis. Run mct under
`timeout` so a stall fails loudly - `scripts/verify.sh` and
`scripts/deploy.sh` both do, defaulting to 60s.

Separately, and unrelated to the network: **`create` does not apply the name and
creator arguments you pass.** The log claims it wrote
`behavior_packs/<yourname>/manifest.json`, but on disk the folder is the raw
template (`aop_mobs`) with `"name": "Sample Add-on Pack"` and Mojang's
placeholder UUIDs. Treat the output as an unmodified template to rename and
re-UUID by hand. Confirmed on 0.17.7 and 0.17.8.

Interactive. Prompts for **name, template, creator, and description**.
Templates are grouped by experience level. Pick the closest match to your
target (entity-heavy vs block-heavy) — you are going to restructure the output
anyway, so favor a template that demonstrates the systems you care about.

If you prefer to scaffold into a subfolder and lift it, run it in a scratch
dir and move `BP/`/`RP/` into `packs/`.

### 3c. Add content scaffolds

```bash
# from: my-addon/
npx mct add entity -i .
npx mct add block -i .
npx mct add item -i .
npx mct add spawnLootRecipes -i .
npx mct add worldGen -i .
npx mct add visuals -i .
npx mct add singleFiles -i .
```

Run only the ones you need. These generate correct, current-format skeletons —
which is exactly the thing you do not want an agent inventing from memory.

### 3d. Normalize versions and UUIDs immediately

```bash
# from: my-addon/
npx mct fix setnewestformatversions -i .
npx mct fix setnewestminengineversion -i .
npx mct fix randomizealluids -i .
npx mct setup -i .
```

`randomizealluids` is important: templates ship with placeholder UUIDs, and two
projects sharing a UUID is a confusing failure.

**It does not live up to its name.** In mct 0.17.7 and 0.17.8 it randomizes only the two
`header.uuid` values and prints "Randomized all UUIDs in project" - every
`modules[].uuid` keeps its template value. Verify afterwards and randomize the
module UUIDs yourself:

```bash
mct fix randomizealluids -i .
node -e 'const fs=require("fs");for(const p of ["packs/BP/manifest.json","packs/RP/manifest.json"]){const d=JSON.parse(fs.readFileSync(p));d.modules.forEach(m=>m.uuid=crypto.randomUUID());fs.writeFileSync(p,JSON.stringify(d,null,2)+"\n");}'
```

It does correctly preserve the BP<->RP `dependencies` cross-links (BP depends
on RP's header uuid and vice versa), rewriting them to match the new headers.
Check that anyway - a broken cross-link is silent at validate time. `setup` ensures project config
files are up to date and healthy.

Set project identity:

```bash
npx mct set name -i .
npx mct set title -i .
npx mct set description -i .
npx mct set bpuuid -i .
npx mct set rpuuid -i .
npx mct set bpscriptentrypoint -i .
```

### 3e. Initialize Regolith

```bash
# from: my-addon/
regolith init
```

Then edit `config.json` so `packs` points at the mct-generated folders:

```json
{
  "name": "my_addon",
  "author": "you",
  "packs": {
    "behaviorPack": "./packs/BP",
    "resourcePack": "./packs/RP"
  },
  "regolith": {
    "profiles": {
      "default": {
        "filters": [
          { "filter": "jsonte" },
          { "filter": "texture_list" },
          { "filter": "name_ninja", "settings": { "language": "en_US.lang" } },
          { "filter": "prune_empty_dirs" },
          { "filter": "sanity_check" }
        ],
        "export": { "target": "development", "readOnly": false }
      },
      "build": {
        "filters": [
          { "filter": "jsonte" },
          { "filter": "texture_list" },
          { "filter": "name_ninja" },
          { "filter": "bump_manifest" },
          { "filter": "prune_empty_dirs" },
          { "filter": "sanity_check" }
        ],
        "export": { "target": "local", "readOnly": false }
      }
    },
    "filterDefinitions": {},
    "dataPath": "./packs/data"
  }
}
```

Filter order matters — filters run top to bottom. Template expansion (jsonte)
must precede anything that scans the resulting files (texture_list,
name_ninja), and checking filters (`sanity_check`) go **last**, so they see the
final state.

`prune_empty_dirs` is a **local** filter — no repo, no resolver entry. Local
filters are declared directly in `filterDefinitions`:

```json
"prune_empty_dirs": { "runWith": "python", "script": "./filters/prune_empty_dirs.py" }
```

`runWith` also accepts `shell`, `nodejs`, `deno`, `bun`, `exe`, `java`, `nim`
and `dotnet`, and `script` is relative to `config.json`.

Use a short project name like `dragons`, not `My Dragon Adventure Map` — with
the `development` export target the project name becomes the export folder
name.

Install filters:

```bash
# from: my-addon/
regolith install jsonte --profile=default
regolith install texture_list --profile=default
regolith install name_ninja --profile=default
regolith install bump_manifest          # build profile only
regolith install sanity_check --profile=default
```

**Always pass `--profile=default`.** Without it, `regolith install` populates
`filterDefinitions` but leaves `profiles.default.filters` empty — the filters
are downloaded and pinned, but never run. Per the Regolith docs:

> you can append it to the end of the list of the filters of the profile by
> using the `--profile` flag

One caveat learned the hard way: **`--profile` only works on first install.**
If the filter is already in `filterDefinitions`, install refuses with *"The
filter is already on the filter definitions list"* and suggests `--update`.
Do not use `--update` just to wire a profile — it re-resolves and can bump
your pinned versions. Edit `config.json` by hand instead; the docs endorse
this ("Alternatively, manually add it to `config.json`").

Note `name_ninja`'s `language` setting is deprecated in favour of `languages`,
which takes a list:

```json
{ "filter": "name_ninja", "settings": { "languages": ["en_US.lang"] } }
```

### 3f. Create the world for testing

```bash
# from: my-addon/
npx mct ensureworld -i .
npx mct world set -i . --betaApis true      # only if you need beta APIs
npx mct deploytestworld -i . --launch
```

### 3g. The verify gate

`scripts/verify.sh` is the mandatory completion gate. Read the script; it is
short. Nothing is done until it exits 0.

```bash
./scripts/verify.sh          # default profile
./scripts/verify.sh ci       # any profile name
MCT_TIMEOUT=120 ./scripts/verify.sh
```

**It validates `build/`, not `packs/`.** `packs/` is source and holds `.templ`
and `.modl` files the game never loads, while everything jsonte generates
exists only in the export target — so validating source both inspected files
Minecraft never sees and skipped every templated file. Switching to the
compiled output surfaced three latent errors on the first run. A profile whose
export target is not `local` leaves nothing in `build/`, so the gate builds a
second time with `ci` to have something to validate.

Why the obvious implementation is wrong, in brief: the report is named from the
input folder (`reports/build.mcr.json`; **glob it, never hardcode**) and
contains no
`"type":"error"` string — errors live in `info.errorCount` and in items with
`"iTp": 3`, so the obvious grep matches nothing and passes every broken
build. The gate therefore checks the mct exit code **and** the report
counts, so a change in either cannot silently disable it. The rest of the
report format and the gate's workarounds (summary fields, the misleading
manifest-count fields, the `build/`/`out/` pre-delete, the `timeout`
wrapper) are catalogued in `docs/bedrock-verify-notes.md`.

**The gate does not deep-validate component payloads.** A malformed component
reports zero errors. Only loading the pack in game catches that.

### 3h. CI

`.github/workflows/validate.yml`. It installs a pinned mct plus Regolith and
runs `./scripts/verify.sh ci` - one gate, not a reimplementation.

Two things it must keep doing:

- Use the **`ci` profile**. The default profile exports to `com.mojang`, which
  does not exist on a runner.
- Call `verify.sh` rather than inlining an error check. The original version of
  this workflow greped `'"type":"error"' reports/info.json`, which matches
  nothing, so CI passed every broken build.

Pin the `@minecraft/creator-tools` version rather than floating - the package
describes itself as pre-release alpha. Keep the pin in step with what you run
locally, or CI and your machine drift.

### 3i. Commit

```bash
git add -A
git commit -m "scaffold: mct template + regolith pipeline"
```

---

## 4. What the agent needs to know

### 4a. Hard rules

- **Author content in `packs/BP` and `packs/RP`.** These are source, not
  output. Never hand-edit the derived side — `.regolith/`, `build/`,
  `reports/`, or the `com.mojang` export target; run `regolith run` instead.
- **Never hand-write a `format_version`.** Read one from an existing file, or
  run `mct fix setnewestformatversions`.
- **Never hand-write a UUID.** Use `mct fix randomizealluids`.
- **Never edit `.geo.json` or `.png`.** Geometry and textures are human
  artifacts from Blockbench. Read them; do not write them.
- **Never declare a task complete without a clean `scripts/verify.sh`.**
- **Never invent a component name.** Read the schema at
  `../mcbe-schemas/behavior/<type>/<type>.json` first. Component sets
  change every release; recall is unreliable.

### 4b. Mental model to give it explicitly

Bedrock entities are **not objects with properties**. They are state charts:

- Component groups are states.
- Events are the only transitions.
- A component group with no event that adds it is unreachable dead code.
- The engine will not warn you about this. Neither will schema validation.

Include this verbatim. Agents default to the object model and produce
schema-valid entities that never change state.

The RP side is a graph, not a tree:

```
client_entity  ->  geometry key   ->  .geo.json identifier
               ->  texture key    ->  textures/... path
               ->  render_controller id
                     -> resolves geometry/texture keys via Molang
```

A break anywhere in that chain renders an invisible or magenta entity with no
error message. This is the single highest-value thing to encode in a skill.

### 4c. Feedback signals available to the agent

| Signal | Command | Catches |
| -------- | --------- | --------- |
| Schema/rule validation | `mct validate addon -i . -ot json -o reports` | structural errors, deprecated fields, rule violations |
| Compile | `regolith run` | template errors, filter failures |
| Visual — model | `mct rendermodel <file>.geo.json -i .` | broken geometry, bad bones |
| Visual — reference | `mct rendervanilla mob minecraft:creeper -o out.png` | comparison baseline |
| Visual — structure | `mct renderstructure <file>.mcstructure` | build placement |
| Runtime | GameTest via `mct exportworld` / `deploytestworld` | actual behavior |
| Runtime - manual | load the pack, then `/reload all` after each change | the only check that catches a malformed component payload; `mct validate` reports zero errors for those |

The render commands emit PNGs. A multimodal agent can inspect them. Treat that
as the closest thing this ecosystem has to a visual regression test — it is the
only automated check that catches "valid JSON, invisible mob".

### 4d. The loop

```
1. read schema for the thing being authored
2. edit packs/BP or packs/RP
3. regolith run
4. mct validate addon -> reports/<project>.mcr.json
5. if errors: fix packs/, goto 3
6. render affected models -> inspect PNG
7. report diff of packs/ to the human
```

Step 7 matters, but know its limit: the `packs/` diff shows what you authored,
not the expanded output the game loads. Filter-generated files exist only in
the export target. When a change turns on template expansion, check the export
target too.

### 4e. Escalate to the human, do not guess

- Any change to `.geo.json`, UVs, or textures.
- Any change to `format_version` or `min_engine_version`.
- Any use of experimental/beta toggles.
- Any validation error the agent cannot resolve in two attempts — dig into
  `reports/<project>.mcr.json` (`info.errorSummary` gives the human-readable
  list) and report, do not thrash.

---

## 5. Packaging and release

`scripts/deploy.sh` verifies, builds with the `build` profile, and packages a
`.mcaddon` into `build/`. It fails if no artifact appears rather than exiting 0
having produced nothing.

The `build` profile runs `bump_manifest`, so versions increment on release.
The script also restores the source manifests afterwards, because
`mct exportaddon` rewrites dependency versions incorrectly (gotcha table).

For a GameTest world: `mct exportworld -i . -o build`.

## 6. Things that will bite you

| Symptom | Cause |
| --------- | ------- |
| Mob is invisible or magenta | RP wiring graph break. No error is emitted. |
| CI fails with `Permission denied` on a script | Windows git sets `core.filemode=false`, so a local `chmod +x` is never recorded and the file commits as `100644`. Fix with `git update-index --chmod=+x <script>`; verify with `git ls-files -s scripts/`. CI also invokes scripts as `bash ./script.sh` so a missing bit cannot break the run. |
| `mct fix` reports success but changes nothing | `setnewestminengineversion` prints "Updated 2 min_engine_version(s)" and returns `{"updatedCount": 2}` from `--json` while the file is byte-identical (md5-verified, 0.17.8). `setnewestformatversions` claims "No format versions to update" on files that are behind. Do not trust either; set versions by hand and confirm with `git diff`. `randomizealluids` does write, so check per-fix rather than assuming. |
| `packs/BP/manifest.json` changed after a build | `mct exportaddon` resolves the latest registry version of each script module dependency and writes it back as an **array** (`[2, 9, 0]`) where a semver **string** (`"2.0.0"`) is correct for `module_name` deps. Arrays are only right for pack-UUID deps. It also strips the trailing newline. `scripts/deploy.sh` snapshots and restores the manifests; after a hand-run `exportaddon`, check `git diff packs/`. Only bites when the registry is reachable, which makes it look intermittent. |
| `bump_manifest` writes into `packs/` | Expected, not corruption. It updates `packs/data/bump_manifest/version.json` so versions persist between builds - the documented exception to "filters never write to source". It does **not** touch dependency versions. |
| Custom mob never spawns naturally | Check the **world**, not the file. Here it was `domobspawning = 0` - a world-creation setting no pack change can overcome and `mct validate` cannot see. Read it straight off disk: `level.dat` is NBT with an 8-byte header, so the byte after the gamerule's name is its value. Worlds are under `Users/<id>/games/com.mojang/minecraftWorlds/`, **not** `Users/Shared/` (that one is empty); `levelname.txt` names each. Rule out in order: `domobspawning`, difficulty above peaceful, light ≤ the `brightness_filter` max, **>24 blocks** from the player, then the monster cap. Only then edit the spawn rule. |
| Entity does not appear at all after a `format_version` bump | A component was **removed** by the newer schema, and that is fatal to the whole entity, not partial. Bumping 1.20.80 → 1.26.40 here produced `minecraft:pushable: this component was found in the input, but is not present in the Schema` followed by `Entity 'x' failed to load from JSON: parse errors occurred`. `minecraft:pushable` split into `minecraft:pushable_by_entity` / `minecraft:pushable_by_block` (empty objects, presence-based) between 1.26.0 and 1.26.40. **`mct validate` reported 0 errors on the unloadable file** - only the in-game Content Log shows it. Bumping `format_version` is a migration, not a clerical edit. |
| Component silently ignored | `format_version` predates the component - **confirmed in game 2026-08-30**, and `mct validate` reported **0 errors** on the broken file, so the gate cannot catch it. Isolated with an A/B: two entities built from the same jsonte modules, byte-identical `component_groups` and `events`, differing only in `format_version`. At 1.8.0 the mob still wandered, still fled when hit, still re-entered `calm` afterwards - but `minecraft:environment_sensor` was dead, so it never aggroed. The drop is **per-component at parse time**, not whole-file. A mob that is "mostly working but one thing does nothing" is a `format_version` suspect first. Note this project declares 1.20.80 while vanilla is on 1.26.x. See `docs/bedrock-entity-notes.md`. |
| Entity never changes state | Component group not reachable from any event. |
| Two add-ons conflict on load | Duplicate UUIDs from an un-randomized template. |
| Edits vanish | Something hand-edited the `com.mojang` export target; the next `regolith run` overwrote it. Edit `packs/` instead. |
| Filter output missing from `packs/` | Expected, not a bug. Filters run against `.regolith/tmp`; generated files appear only in the export target. |
| `regolith run` fails with `Couldn't read filter data from path` | The filter cache is gone - fresh clone, or someone ran `regolith clean`. **`regolith run` does not auto-install**; it fails and tells you to run `regolith install-all`. Verified 2026-08-30 by cleaning and re-running. `.regolith/` is gitignored, so CI hits this on every checkout. |
| `Deletion safety check for ... failed. File is not on the list of files created by Regolith` | `regolith clean` wiped `.regolith/cache/edited_files.json`, which is the record of what regolith wrote into each export target. Without it regolith refuses to overwrite an export it can no longer prove it owns. Bites when a `local`-target `build/` survives a clean. **Fix: delete the export directory** (`build/`, or the `com.mojang` `development_*_packs` folder) and re-run. `scripts/verify.sh` self-heals because it now removes `build`/`out` **before** every run as well as after - removing only afterwards was not enough, since a run that never reached the cleanup left the export behind for the next one to trip over. |
| Extension flags valid code | Blockception avoids experimental features by design. mct is the authority. |
| CADDONREQ102/104 on a **loot table** | The Cooperative Add-On folder rule is not textures-only. `loot_tables/entities/foo.json` - **vanilla's own layout** - fails, because `entities` is a common term. Use `loot_tables/<creatorshortname>/<mygamename>/<file>.json`. Note `spawn_rules/` is *not* subject to this and passes flat, so the rule is per-folder: check rather than assume. |
| Texture validation errors CADDONREQ102/104/108 | Cooperative Add-On rules: textures may not sit loose in common-named folders. Required layout is `textures/<creatorshortname>/<gamename>/blocks&#124;items&#124;entity/*.png` (one of those three), and `<creatorshortname>` may contain exactly **one** subfolder (plus optionally `common`). See the template under `packs/RP/textures/nimrodx/template/`. |
| Generated `.lang` file is empty | `name_ninja` emits nothing unless a `name` field is present in the BP description or `auto_name` is enabled per type. It needs separate `entities`/`blocks`/`items`/`spawn_eggs` settings blocks - enabling three of the four silently omits the fourth. |
| Item is **invisible** (not magenta) | The `minecraft:icon` component shape is wrong, so nothing resolved. Magenta means a texture path resolved but the file is missing; invisible means the component itself was rejected. `minecraft:icon` is either a bare string or `{"textures": {"default": "<key>"}}` - `textures` plural, `default` required, `additionalProperties: false`. `{"texture": "x"}` is silently invalid. |
| Validation passes but content is broken in game | `mct validate` does **not** deep-validate component payloads against the schemas. It checks manifests, pack conventions and file structure. A malformed component shape reports zero errors. Read `../mcbe-schemas/behavior/<type>/<type>.json` before writing a component - this is what rule 4a exists for, and it is easy to skip. |
| Pack changes do not appear after `/reload` | `/reload` reloads **functions and scripts only** - not entity/block/item definitions and not textures. Use `/reload all`, which reloads all behavior and resource packs. It is implemented as a quit-and-rejoin but is effectively instant and returns you to the same spot, so there is little reason to prefer plain `/reload`. Host player only on servers. |
| An mct command runs for minutes | Network, not the tool. mct resolves script module deps against registry.npmjs.org and a half-open connection stalls it; `--offline` does not stop those lookups. `--verbose` eventually shows `Could not load registry for '@minecraft/server'`. Both scripts wrap mct in `timeout` (60s, `MCT_TIMEOUT` to raise). npm's own `fetch-*` retry settings do not apply - mct is not npm. |
| `timeout: failed to run command 'mct'` while `regolith run` succeeds | The global install is half-written, but creator-tools is rarely the culprit - **npm's global prefix is one shared tree**, and `npm i -g <anything>` re-reifies all of it and runs every package's install scripts. One unrelated postinstall failing aborts the whole transaction after extraction but before bin shims are linked. Observed here: `glslang-validator-prebuilt` died with `Cannot find module 'rimraf'`, leaving creator-tools with no `mct` shim. Diagnose from `npm ls -g --depth=0` - **a package printed with an empty version after the `@` is half-installed** - then the npm debug log the failure names. Recovery: remove the failing package, reinstall, re-check. See section 2. |
| `npm warn cleanup ... EPERM: operation not permitted, unlink ...node.napi.node` | A running process has the native addon (`.node` = a DLL) mapped, and Windows will not unlink a loaded DLL. Almost always the **`mct mcp` MCP server this repo's `.mcp.json` starts**, holding `bufferutil`. npm finishes the install but cannot swap or clean its staging directory, stranding a ~55 MB `node_modules/@minecraft/.creator-tools-<hash>/` copy - whose truncated `dist lib node_modules res` contents are easily mistaken for a corrupt package. Stop the MCP server before any global install touching creator-tools, or use `npx -y -p @minecraft/creator-tools mct ...` which never writes to the global tree. Find leftovers with `find "$(npm config get prefix)/node_modules" -maxdepth 2 -name '.*-*' -type d`. |
| jsonte: `Failed to parse JSON ... Unexpected token '{'` | `{{ }}` was used outside a string. A `.templ` must be valid JSON *before* templating, so write `"value": "{{expr}}"`. A string that is entirely one expression is type-coerced on output, so this still emits an unquoted number. |
| A `.modl` module is never loaded, with no warning | It is outside `BP/` or `RP/`. The jsonte filter hardcodes `compile ... BP/ RP/`; `data/jsonte` is a variable **scope** path, not a module search path. Put modules in `packs/BP/modules/`. |
| Empty `modules/` folder ships inside the pack | `--remove-src` deletes the source `.modl` files but not their directory, and the filter's arguments are hardcoded so `--exclude` is unreachable. Cosmetic - Minecraft ignores unknown directories. |
| `config.json` fully rewritten after `regolith install` | Expected, and unrelated to your change. It reserializes the whole file: 2-space indent becomes **tabs**, profiles and settings keys are **reordered alphabetically**, and the **trailing newline is stripped** - so the diff swamps the one line you wanted. It also adds only the `filterDefinitions` entry; **adding the filter to each profile's `filters` array is manual.** Snapshot `config.json` first if you want a readable diff, the way `scripts/deploy.sh` snapshots manifests around `mct exportaddon`. |
| Model looks floating / sunk, and `collision_box` does not fix it | `minecraft:collision_box` is the **physical hitbox only** - it never positions the model. Feet land where the geometry's `0,0,0` origin puts them, so vertical placement is fixed in the `.geo.json`, not the BP. A mismatched box means you swing at visible air (or hit nothing where the model looks solid), which is a real bug but a different one. |
| A `behavior.*` goal appears absent from the schemas | AI goals live in `source/behavior/entities/format/behaviors/` (e.g. `behaviors/melee_attack.json`), **not** in the sibling `components/` directory. Grepping `components/` finds nothing and looks like the component does not exist. |
| Custom item aux IDs unstable | Known ecosystem limitation: item ID assignment depends on pack stack order at world load, which is non-deterministic and unknowable at build time. Do not build logic on aux IDs. |
