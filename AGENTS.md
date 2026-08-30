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
| cmcc | any | **paid, licensed** — only if using the `command_lang` filter (see section 4) |
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
regolith install github.com/MCDevKit/regolith-library/command_lang --profile=default
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

### command_lang requires `cmcc`, which is a paid product

This is the one prerequisite that will stop a build cold, and neither the
filter nor the MCDevKit tutorial says so. The filter is a thin
`runWith: "shell"` wrapper:

```json
{ "command": "cmcc", "arguments": ["regolith", "--bp-dir", "./BP", ...] }
```

`regolith install` fetches that wrapper but **does not install `cmcc`**.
Regolith's own docs only promise to install *language* dependencies, not
external binaries a filter shells out to. Without `cmcc` on PATH the filter
fails and takes the whole profile down:

```
[ERROR] [command_lang] cmcc : The term 'cmcc' is not recognized...
[+]: Failed to run profile ""
```

`cmcc` is **not open source**. The MCDevKit GitHub org publishes only
`cmcc-docs`; there is no compiler repo and no GitHub release to download.
It is distributed through the client panel at <https://mcdevkit.com>, needs an
active subscription, must be put on PATH by hand, and is then activated with
`cmcc activate <license key>`. See the MCDevKit getting-started guide.

**Decision for this project: CommandLang is not used.** `command_lang` stays in
`filterDefinitions` (harmless, keeps the option open) but is absent from every
profile. Do not add it back before installing and activating `cmcc` - it breaks
`regolith run`, and therefore every build. It is only needed if you author
`.mcc` sources; `packs/data/command_lang/main.mcc` is filter data seeded from
the cache, not authored source.

Standalone jsonte CLI is also useful for the agent to test expansion in
isolation: `jsonte eval <expr>` prints a result to console without a full
compile.

---

### JSON schemas

```bash
git clone --depth=1 https://github.com/Blockception/Minecraft-bedrock-json-schemas.git ../mcbe-schemas
```

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
| `bedrock-verify` | `docs/bedrock-verify-notes.md` | The gate: run it, read `reports/<project>.mcr.json`, never claim done without a clean run |
| `bedrock-entity` | `docs/bedrock-entity-notes.md` | Component groups and events as a state chart; spawn rules |
| `bedrock-block` | `docs/bedrock-block-notes.md` | States, permutations, culling, and the blocks.json / terrain_texture.json / textures three-way contract |
| `bedrock-item` | `docs/bedrock-item-notes.md` | Item components, the icon/texture contract, recipes |
| `bedrock-rp-wiring` | `docs/bedrock-rp-wiring-notes.md` | client entity -> geometry / texture / render controller graph. Highest-failure area |
| `bedrock-molang` | `docs/bedrock-molang-notes.md` | Query namespaces, context validity, arrow-operator gotchas |
| `bedrock-jsonte` | `docs/bedrock-jsonte-notes.md` | `.templ` syntax, modules, when to template vs write literal JSON |
| `bedrock-regolith` | `docs/bedrock-regolith-notes.md` | Filter pipeline, profiles, export targets, source/output direction |
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
4. `regolith install` std-lib filters + jsonte + command_lang
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
packs/data/           -- regolith filter data (dataPath)               (tracked)
.regolith/tmp/        -- scratch copy filters actually run against     (ignored)
com.mojang/           -- real output; outside the repo entirely
build/                -- packaged .mcaddon artifacts                   (ignored)
reports/              -- mct validator output                          (ignored)
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
│   │   ├── blocks/
│   │   ├── items/
│   │   ├── functions/          # .mcfunction, or .mcc for command_lang
│   │   └── scripts/            # Script API TypeScript
│   ├── RP/                     # resource pack
│   │   ├── manifest.json
│   │   ├── entity/             # client entity definitions
│   │   ├── render_controllers/
│   │   ├── models/entity/      # .geo.json from Blockbench (HUMAN ONLY)
│   │   └── textures/           # .png source art (HUMAN ONLY)
│   └── data/                   # regolith filter data (dataPath)
│       ├── jsonte/             # data.json - inputs consumed by templates
│       ├── command_lang/
│       └── bump_manifest/
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
```

Template and CommandLang sources live **inside** `packs/`, alongside the JSON
they expand into — jsonte and command_lang discover `.templ` and `.mcc` by
scanning the temp copy of the packs. There is no separate templates directory.

`../mcbe-schemas` is kept outside the project on purpose: anything under the
project root gets walked by `mct validate`, and the schema clone's ~1200 files
swamp the report (1221 files scanned vs 8) and emit spurious
`Could not load biome definition: SyntaxError` errors - mct tries to read the
biome *schemas* as biome *definitions*. Reproduce with
`mct validate addon -i ../mcbe-schemas`. Those particular errors are logged to
stderr but never reach `info.errorCount`, so they would not fail the gate;
the reason to move the clone out is report noise, not a false failure.

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
          { "filter": "name_ninja", "settings": { "language": "en_US.lang" } }
        ],
        "export": { "target": "development", "readOnly": false }
      },
      "build": {
        "filters": [
          { "filter": "jsonte" },
          { "filter": "texture_list" },
          { "filter": "name_ninja" },
          { "filter": "bump_manifest" }
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
name_ninja).

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
# regolith install command_lang --profile=default   # requires paid cmcc, see section 4
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

Why the obvious implementation is wrong, in brief: the report is
`reports/<project>.mcr.json` (not `info.json`) and contains no
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
| Component silently ignored | `format_version` predates the component. |
| Entity never changes state | Component group not reachable from any event. |
| Two add-ons conflict on load | Duplicate UUIDs from an un-randomized template. |
| Edits vanish | Something hand-edited the `com.mojang` export target; the next `regolith run` overwrote it. Edit `packs/` instead. |
| Filter output missing from `packs/` | Expected, not a bug. Filters run against `.regolith/tmp`; generated files appear only in the export target. |
| Extension flags valid code | Blockception avoids experimental features by design. mct is the authority. |
| Texture validation errors CADDONREQ102/104/108 | Cooperative Add-On rules: textures may not sit loose in common-named folders. Required layout is `textures/<creatorshortname>/<gamename>/blocks&#124;items&#124;entity/*.png` (one of those three), and `<creatorshortname>` may contain exactly **one** subfolder (plus optionally `common`). See the template under `packs/RP/textures/addontemplate/template/`. |
| Generated `.lang` file is empty | `name_ninja` emits nothing unless a `name` field is present in the BP description or `auto_name` is enabled per type. It needs separate `entities`/`blocks`/`items`/`spawn_eggs` settings blocks - enabling three of the four silently omits the fourth. |
| Item is **invisible** (not magenta) | The `minecraft:icon` component shape is wrong, so nothing resolved. Magenta means a texture path resolved but the file is missing; invisible means the component itself was rejected. `minecraft:icon` is either a bare string or `{"textures": {"default": "<key>"}}` - `textures` plural, `default` required, `additionalProperties: false`. `{"texture": "x"}` is silently invalid. |
| Validation passes but content is broken in game | `mct validate` does **not** deep-validate component payloads against the schemas. It checks manifests, pack conventions and file structure. A malformed component shape reports zero errors. Read `../mcbe-schemas/behavior/<type>/<type>.json` before writing a component - this is what rule 4a exists for, and it is easy to skip. |
| Pack changes do not appear after `/reload` | `/reload` reloads **functions and scripts only** - not entity/block/item definitions and not textures. Use `/reload all`, which reloads all behavior and resource packs. It is implemented as a quit-and-rejoin but is effectively instant and returns you to the same spot, so there is little reason to prefer plain `/reload`. Host player only on servers. |
| An mct command runs for minutes | Network, not the tool. mct resolves script module deps against registry.npmjs.org and a half-open connection stalls it; `--offline` does not stop those lookups. `--verbose` eventually shows `Could not load registry for '@minecraft/server'`. Both scripts wrap mct in `timeout` (60s, `MCT_TIMEOUT` to raise). npm's own `fetch-*` retry settings do not apply - mct is not npm. |
| Custom item aux IDs unstable | Known ecosystem limitation: item ID assignment depends on pack stack order at world load, which is non-deterministic and unknowable at build time. Do not build logic on aux IDs. |
