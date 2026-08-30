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
| Model authoring | Blockbench workflow for humans, then the geometry rules an agent must follow when drafting `.geo.json` skeletons |

The model-authoring part is split deliberately: Part 1 is human workflow
context, Part 2 is the ruleset destined for a `bedrock-geometry` skill.

## Status and provenance

The original draft was research output from other agents. Much of it has since
been checked against the installed toolchain and corrected; several claims that
sounded reasonable turned out to be wrong in ways that would have cost real
debugging time. Where a section records a defect or a surprising behaviour, it
was reproduced on this machine, not inferred.

Known-verified: the Regolith source/output direction, the `verify.sh` gate
(proven to fail on a broken project and pass on a clean one), the
`mct fix randomizealluids` module-UUID gap, the `mct create` hang, and the
`cmcc` licensing requirement.

Still carrying unverified research: the model-authoring survey sections (5a,
5b) and parts of the tooling commentary. Treat specific version numbers and
third-party claims there as of-their-time, not as current fact.

**When you find something here that is wrong, fix it in place** rather than
working around it. Delete sections that stop earning their space. The intent
is for this file to eventually shed material into focused skills under
`.claude/skills/`; until then it stays here, and staying accurate matters more
than staying short.

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
Per the official getting-started guide it is distributed through a client
panel and requires an active paid subscription:

> Download CMCC from Downloads page in client panel

> ...confirm that it's working by entering `cmcc` and hitting enter

> ...type `cmcc activate <license key>`

Install procedure (Windows), from that guide:

1. Sign in at <https://mcdevkit.com> and download CMCC from the client panel's
   Downloads page. This needs an active subscription.
2. "Move it to a folder, where it won't be accidentally removed or moved
   somewhere else."
3. Add that folder to PATH: Start menu -> *Edit the system environment
   variables* -> **Environment variables** -> select **Path** -> **Edit** ->
   **Add** the folder -> OK out of every window.
4. Open a new terminal and run `cmcc` to confirm it resolves.
5. Activate with `cmcc activate <license key>`.

**Decision for this project: CommandLang is not used.** `command_lang` stays
in `filterDefinitions` (harmless, and keeps the option open) but is deliberately
absent from every profile. Do not add it back without first installing and
activating `cmcc`; doing so breaks `regolith run` and therefore every build.

**Until `cmcc` is installed and activated, leave `command_lang` out of your
profile.** It is not needed unless you are actually authoring `.mcc` sources —
`packs/data/command_lang/main.mcc` is filter data seeded from the cache, not
authored source, and does not require the filter.

Standalone jsonte CLI is also useful for the agent to test expansion in
isolation: `jsonte eval <expr>` prints a result to console without a full
compile.

---

## 5. VS Code (human editor only)

Install **Blockception's Minecraft Bedrock Development** from the marketplace.

Note: the old `VSCode-Bedrock-Development-Extension` repo is archived. Active
development is at `Blockception/minecraft-bedrock-language-server`, a monorepo
containing the language server, diagnostics, and project utilities. It provides
`.mcfunction`, `.json`, `.lang`, and Molang support.

Design caveat to be aware of: Blockception deliberately avoids
experimental/beta/undocumented features unless vanilla files are seen using
them. If you work with experimental toggles, expect false negatives from its
diagnostics. mct validate is your authority, not the extension.

### JSON schemas

```bash
git clone https://github.com/Blockception/Minecraft-bedrock-json-schemas.git ../mcbe-schemas
```

**The schemas repo does not ship a `vscode-settings.json`** despite what
earlier drafts of this document said - checked against a current clone. Write
the `json.schemas` mappings yourself, pointing `fileMatch` globs at
`packs/BP/**` and `packs/RP/**` and `url` at the relevant schema file. See this
repo's `.vscode/settings.json` for a worked set of 27 mappings covering both
packs, `manifest.json`, and `*.geo.json`.

Schema filenames are not always what you would guess - for example
`behavior/animation_controllers/animation_controller.json` (singular) but
`behavior/animations/animations.json` (plural), and
`resource/animations/actor_animation.json`. Check the directory rather than
assuming.

Keep the clone on disk regardless of editor: the **agent** should read raw
schema files rather than rely on training-data recall of component names,
which drift every release.

---

## 6. Blockbench

Install from <https://blockbench.net>. Human-only tool for `.geo.json` geometry
and UV work. The agent's only interaction with models is reading them and
calling `mct rendermodel` to produce a PNG it can inspect.

Optional: Snowstorm (particles) — bridge. can hand off to it directly.

---

## 7. bridge. (optional, as an inspector)

Web app: <https://editor.bridge-core.app/> — native builds also published for
Windows/macOS/Linux.

Current state: v3.0.0 is a full rewrite; some things are missing for now
(model previews among them) and bugs are still shaking out. v2 (v2.7.x) is the
mature line. Both ship the Dash compiler, which replaced bridge.'s old
internal compiler as of v2.2.0.

**Do not make this the agent's workbench.** No terminal, no MCP, no file-level
agent access. Its core value — a tree editor that stops humans making
structure mistakes, plus completions and validations for all Minecraft JSON —
is aimed at manual authoring. Keep it installed to eyeball agent output in
tree view and to open particles in Snowstorm.

Interop note: Regolith follows the Project Config Standard, the shared
`config.json` format used by programs that interact with Minecraft projects
including bridge., adding its own `regolith` namespace on top. So the three
tools compose rather than conflict.

---

## 8. Claude Code harness config

### 8a. MCP server

`mct mcp` is plain stdio. It is not VS Code specific — the upstream docs just
use VS Code as the example client.

Project-scoped, `.mcp.json` at repo root:

```json
{
  "mcpServers": {
    "minecraft-creator-tools": {
      "command": "mct",
      "args": ["mcp", "-i", "."]
    }
  }
}
```

Verify inside Claude Code with `/mcp`.

Honest assessment: with a shell, this MCP server is a convenience, not a
dependency. The verify loop is `regolith run && mct validate addon`, which the
Bash tool already covers. Add the MCP server for structured project
introspection; don't architect around it.

For reference, the VS Code equivalent (`.vscode/mcp.json`) if you ever want it
there too:

```json
{
  "servers": {
    "minecraft-creator-tools": {
      "type": "stdio",
      "command": "mct",
      "args": ["mcp", "-i", "${workspaceFolder}"]
    }
  }
}
```

### 8b. Existing skills/plugins — what actually exists

I searched this specifically. Findings:

| Thing | Verdict |
| ------- | --------- |
| `mrquentin/minecraft-skills` | Only partially relevant. Bundle is Forge/NeoForge/GregTech focused, **but** it includes a `minecraft-gametest` skill covering the Bedrock GameTest framework. Worth installing for that one skill. |
| `chouzz/minecraft-mod-dev` | Java modding (NeoForge/Fabric). Not applicable. |
| `minecraft-plugin-development` (awesome-copilot) | Paper/Spigot/Bukkit. Its own description explicitly lists Bedrock add-ons as out of scope. |
| `Jahrome907/minecraft-agent-skills` | Mixed bundle, Java-leaning. Evaluate skeptically. |
| `setup-bedrock-server` (skills.rest) | BDS deployment, not add-on authoring. Useful only if you run a dedicated server. |
| Add-on-authoring MCP servers | **None exist** besides `mct mcp`. Everything in the MCP registries under "Minecraft" is in-game WebSocket bot control (player movement, block placement). Irrelevant. Stop looking. |

Install the GameTest one:

```
/plugin marketplace add mrquentin/minecraft-skills
/plugin install minecraft-skills@mrquentin
```

Or scope it manually by copying just the `minecraft-gametest` skill folder to
`.claude/skills/`.

**Conclusion: there is no meaningful prior art for Bedrock add-on authoring.
You are writing your own skills.** This is the real work of the harness.

### 8c. Skills you write

Put in `.claude/skills/<name>/SKILL.md`. Write these *after* you've watched
the agent fail a few times, so they encode real failure modes rather than
guesses.

**Status: none of these exist yet.** The only skill currently installed is
`minecraft-gametest`. The table below is a roadmap, not an inventory - do not
assume a skill is available because it is listed here.

| Skill | Covers |
| ------- | -------- |
| `bedrock-verify` | Mandatory gate. Run `scripts/verify.sh`, read `reports/<project>.mcr.json`, never claim done without a clean run. |
| `bedrock-entity` | Component-group/event wiring as a state chart. The "every component group must be reachable from an event" invariant. Spawn rules. |
| `bedrock-block` | Block states, permutations, geometry + culling, the `blocks.json` / `terrain_texture.json` / `textures/` three-way path contract. |
| `bedrock-rp-wiring` | Render controller ↔ client entity ↔ geometry ↔ texture graph. Highest-failure area. |
| `bedrock-molang` | Query namespaces, context validity, arrow-operator gotchas. |
| `bedrock-jsonte` | `.templ` syntax, modules, when to template vs when to write literal JSON. |
| `bedrock-regolith` | Filter pipeline, profiles, why `packs/` is never hand-edited. |

### 8d. Permissions

`.claude/settings.json`:

This is the file currently in the repo:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(regolith run:*)",
      "Bash(regolith install:*)",
      "Bash(regolith config:*)",
      "Bash(regolith --version)",

      "Bash(mct validate:*)",
      "Bash(npx mct validate:*)",
      "Bash(mct info:*)",
      "Bash(npx mct info:*)",
      "Bash(mct version:*)",
      "Bash(mct search:*)",
      "Bash(mct aggregatereports:*)",
      "Bash(mct fix:*)",
      "Bash(npx mct fix:*)",
      "Bash(mct rendermodel:*)",
      "Bash(mct rendervanilla:*)",
      "Bash(mct renderstructure:*)",
      "Bash(npx mct rendermodel:*)",
      "Bash(npx mct rendervanilla:*)",
      "Bash(npx mct renderstructure:*)",

      "Bash(./scripts/verify.sh)",

      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git show:*)",
      "Bash(git ls-files:*)",

      "Bash(node --version)",
      "Bash(npm --version)",
      "Bash(java -version)"
    ],
    "deny": [
      "Bash(mct deploy:*)",
      "Bash(npx mct deploy:*)",
      "Bash(mct deploytestworld:*)",
      "Bash(npx mct deploytestworld:*)",

      "Edit(.regolith/**)",
      "Write(.regolith/**)",
      "Edit(out/**)",
      "Write(out/**)",
      "Edit(build/**)",
      "Write(build/**)",
      "Edit(reports/**)",
      "Write(reports/**)",


      "Edit(**/*.geo.json)",
      "Write(**/*.geo.json)",
      "Edit(**/*.bbmodel)",
      "Write(**/*.bbmodel)",
      "Edit(**/*.png)",
      "Write(**/*.png)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(git commit:*)",
      "Bash(mct exportaddon:*)",
      "Bash(mct exportworld:*)",
      "Bash(mct ensureworld:*)",
      "Bash(mct create:*)",
      "Bash(mct set:*)",
      "Bash(mct add:*)"
    ]
  }
}
```

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

## 9. Smoke test before writing any agent config

Prove the toolchain end to end by hand first. If this doesn't work, no amount
of prompt engineering will save you.

```bash
npx mct create                                   # interactive scaffold
cd <project>
npx mct info -i .
npx mct validate addon -i . -v
npx mct deploy mcuwp -i . --test-world --launch
```

Then prove the compiler layer:

```bash
regolith init
regolith install texture_list
# add texture_list to the default profile in config.json
regolith run
```

Only after both pass should you write `CLAUDE.md` and skills.

---

## 10. Install order summary

1. Node 22+, npm 10+, Java 11+, Go, git
2. `npm i -g @minecraft/creator-tools` → `npx mct eula`
3. Regolith binary
4. `regolith install` std-lib filters + jsonte + command_lang
5. VS Code + Blockception extension; clone schemas repo
6. Blockbench
7. bridge. (optional, inspector role)
8. Manual smoke test (section 9)
9. `.mcp.json`, `.claude/settings.json`, `CLAUDE.md`, skills
10. `mrquentin/minecraft-skills` for the GameTest skill only

# Bedrock Add-On Repo Structure and Bootstrap

Companion to `01-bedrock-toolchain-setup.md`. This file describes the git repo
layout, the exact commands to bootstrap it, and the context an agent needs to
work in it safely.

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
├── tests/
│   └── gametest/               # GameTest specs
│
├── docs/
│   └── decisions.md            # why format_version X, why this wiring
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
swamp the report and emit spurious JSON parse errors from `bedrock-samples`.

### `.gitignore`

```
/build
/reports
/out
/.regolith
node_modules/
*.mcaddon
*.mcworld
```

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

```bash
# from: my-addon/
npx mct create
```

Non-interactive form, which is what an agent must use (the Bash tool cannot
answer prompts):

```bash
# from: my-addon/
mct create -y -o . <name> <template> <creator> "<description>"
mct create -y -o ./myproj                    # all defaults
```

**Known defect in mct 0.17.7 - `create` never exits.** It writes the template
files within a few seconds and then hangs forever; `--offline` makes no
difference, so it is not a network stall. Run it under a timeout and treat file
presence, not exit status, as the success signal:

```bash
timeout 90 mct create -y -o . myaddon addonStarter me "desc" || true
```

Worse, it hangs *partway through personalisation*. The log claims it wrote
`behavior_packs/<yourname>/manifest.json`, but on disk the folder is still the
raw template (`aop_mobs`) with `"name": "Sample Add-on Pack"` and Mojang's
placeholder UUIDs. **The name/creator arguments you pass do not land.** Treat
the output as an unmodified template that you must rename and re-UUID by hand.

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

**It does not live up to its name.** In mct 0.17.7 it randomizes only the two
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
          { "filter": "command_lang" },
          { "filter": "texture_list" },
          { "filter": "name_ninja", "settings": { "language": "en_US.lang" } }
        ],
        "export": { "target": "development", "readOnly": false }
      },
      "build": {
        "filters": [
          { "filter": "jsonte" },
          { "filter": "command_lang" },
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
regolith install bump_manifest          # build profile only; do not add to default
# regolith install command_lang --profile=default   # requires paid cmcc, see section 4
```

**Always pass `--profile=default`.** Without it, `regolith install` populates
`filterDefinitions` but leaves `profiles.default.filters` empty — the filters
are downloaded and pinned, but never run. Per the Regolith docs:

> you can append it to the end of the list of the filters of the profile by
> using the `--profile` flag

Two caveats learned the hard way:

- **`--profile` only works on first install.** If the filter is already in
  `filterDefinitions`, install refuses with *"The filter is already on the
  filter definitions list"* and suggests `--update`. Do not use `--update`
  just to wire a profile — it re-resolves and can bump your pinned versions.
  Edit `config.json` by hand instead; the docs endorse this ("Alternatively,
  manually add it to `config.json`").
- **Filter order in the profile is the run order.** Expansion (`jsonte`) must
  come before anything that scans the expanded result (`texture_list`,
  `name_ninja`).

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

### 3g. Verify script

This is the mandatory completion gate. The script below is the one actually in
this repo at `scripts/verify.sh`, verified to fail on a broken project and pass
on a clean one — not a sketch.

Three things about `mct validate` that the obvious implementation gets wrong:

- The report is written to `reports/<project>.mcr.json`, **not**
  `reports/info.json`. The filename is derived from the project folder.
- There is no `"type":"error"` string anywhere in it. Errors are counted in
  `info.errorCount` and appear as items with `"iTp": 3`. Grepping for
  `"type":"error"` matches nothing and the gate passes on a broken project —
  the worst possible failure mode for a completion gate.
- `mct validate` **does** exit nonzero on errors (4, observed). Beware
  measuring this through a pipe: `mct validate ... | tail` reports `tail`'s
  exit code, not mct's.

The script gates on both the exit code and the report counts, so a change in
either behaviour cannot silently turn it into a no-op.

```bash
#!/usr/bin/env bash
#
# Mandatory completion gate for this project.
#
# Compiles with regolith, validates with mct, and fails loudly on any error.
# No task is "done" until this exits 0.
#
# Checks BOTH the mct exit code and the counts inside the JSON report. mct
# does return a nonzero code on validation errors (4, observed), but the
# report is the authoritative record, and gating on both means a change in
# either behaviour cannot silently turn this into a no-op.

set -euo pipefail

cd "$(dirname "$0")/.."

REPORTS="reports"

# Optional profile argument. Default profile exports to com.mojang; CI has no
# com.mojang, so CI passes a profile whose export target is "local".
PROFILE="${1:-}"

echo "==> regolith run ${PROFILE}"
regolith run ${PROFILE}

# A "local"-target profile exports into build/, which mct would then scan
# alongside packs/ - double-validating everything and doubling error counts.
# build/ is derived and gitignored; produce release artifacts with
# `mct exportaddon` as a separate step, not from here.
rm -rf build

echo
echo "==> mct validate addon"
rm -rf "$REPORTS"
mkdir -p "$REPORTS"

set +e
mct validate addon -i . -ot json -o "$REPORTS" --threads 8
MCT_EXIT=$?
set -e

REPORT="$(ls "$REPORTS"/*.mcr.json 2>/dev/null | head -1)"
if [ -z "$REPORT" ]; then
  echo
  echo "FAIL: mct produced no report at $REPORTS/*.mcr.json (exit $MCT_EXIT)"
  exit 1
fi

echo
node -e '
const fs = require("fs");
const [report, mctExit] = process.argv.slice(1);
let d;
try {
  d = JSON.parse(fs.readFileSync(report, "utf8"));
} catch (e) {
  console.error("FAIL: could not parse " + report + ": " + e.message);
  process.exit(1);
}

const info = d.info || {};
const errors   = info.errorCount || 0;
const internal = info.internalProcessingErrorCount || 0;
// iTp === 3 marks an error item; cross-check it against errorCount.
const items = (d.items || []).filter(i => i.iTp === 3).length;

if (errors || internal || items) {
  console.error("VALIDATION FAILED  " + report);
  console.error("  errors:                    " + errors);
  console.error("  internal processing errors: " + internal);
  console.error("  error items (iTp=3):        " + items);
  if (info.errorSummary) {
    console.error("");
    console.error(info.errorSummary);
  }
  if (info.internalProcessingErrorSummary) {
    console.error(info.internalProcessingErrorSummary);
  }
  process.exit(1);
}

if (mctExit !== "0") {
  console.error("VALIDATION FAILED: report is clean but mct exited " + mctExit);
  console.error("Inspect " + report + " - this means mct signalled a failure");
  console.error("the report did not record, and the gate is not trustworthy.");
  process.exit(1);
}

console.log("clean  " + report);
console.log("  files scanned: " + (info.contentFileCounts || 0) +
            " content / " + (info.fileCounts || 0) + " total");
' "$REPORT" "$MCT_EXIT"
```

```bash
chmod +x scripts/verify.sh
```

Parsing is done with `node`, not `python3`, because Node 22+ is already a hard
requirement of `@minecraft/creator-tools` — no extra dependency.

It takes an optional profile argument: `./scripts/verify.sh` runs the `default`
profile, `./scripts/verify.sh ci` runs the `ci` profile. That exists because
`default` exports into `com.mojang`, which does not exist on a CI runner - see
3h.

Two scoping decisions worth not relitigating:

- It validates with `-i .`, and deletes `build/` first. A `local`-target
  profile exports into `build/`, which mct would then scan alongside `packs/`,
  double-validating everything and doubling error counts. Build release
  artifacts with `mct exportaddon` as a separate step instead.
- `mct validate addon -i packs` also works and catches the same errors (tested
  against a real `CADDONIREQ170`), but reports paths without the `packs/`
  prefix. Note that `behaviorPackManifestCount` / `resourcePackManifestCount`
  read `0` in the report even on a healthy project with both manifests
  present - do **not** use those counters as a health signal. `errorCount` is
  the field that matters.

Failing output looks like this:

```
VALIDATION FAILED  reports/test_mcaddon.mcr.json
  errors:                    1
  internal processing errors: 0
  error items (iTp=3):        1

ERROR: [CADDONIREQ170] (/packs/RP/manifest.json) Resource pack manifest does
not specify that header/pack_scope that should be 'world'
```

Passing output:

```
clean  reports/test_mcaddon.mcr.json
  files scanned: 4 content / 12 total
```

Note `--threads` defaults to 8 and caps at 16. Large projects benefit; small
ones will not notice.

### 3h. CI

`.github/workflows/validate.yml`:

```yaml
name: Validate Add-on

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'

      # Pinned rather than floating: @minecraft/creator-tools describes itself
      # as pre-release alpha.
      - name: Install Minecraft Creator Tools
        run: npm install -g @minecraft/creator-tools@0.17.7

      - name: Install Regolith
        run: |
          curl -sSL -o regolith.tar.gz \
            https://github.com/Bedrock-OSS/regolith/releases/latest/download/regolith-linux-x64.tar.gz
          tar -xzf regolith.tar.gz
          sudo mv regolith /usr/local/bin/
          regolith --version

      # The one gate. Do not reimplement the error check inline here - see
      # AGENTS.md section 3g for why the obvious grep silently passes.
      # The "ci" profile exports to a local target; the default profile would
      # try to write into com.mojang, which does not exist on a CI runner.
      - name: Verify
        run: ./scripts/verify.sh ci

      - name: Upload validation report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: validation-report
          path: reports/
          if-no-files-found: warn
```

Run `scripts/verify.sh` rather than reimplementing the gate inline — one gate,
one place to fix. The original version of this workflow greped
`'"type":"error"' reports/info.json`, which matches nothing and therefore
passed every broken build (see 3g). It also ran `mct validate` without
`regolith run`, so it validated unexpanded sources.

Java is needed only if a filter requires it. `--offline` on mct commands is
worth considering in CI: its own help calls it "useful for CI environments
where network is unreliable," though it notes some version checks may still
reach the network. Pin the `@minecraft/creator-tools` version rather than
floating on latest — the package describes itself as pre-release alpha.

Note: Mojang's published example pins Node 18, but the package requires 22+.
Use 22.

### 3i. Commit

```bash
git add -A
git commit -m "scaffold: mct template + regolith pipeline"
```

---

## 4. What the agent needs to know

This is the substance of `CLAUDE.md`.

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

```bash
# from: my-addon/
regolith run build          # profile with bump_manifest
npx mct exportaddon -i . -o build
```

Produces a `.mcaddon`. For a GameTest world:

```bash
npx mct exportworld -i . -o build
```

---

## 6. Things that will bite you

| Symptom | Cause |
| --------- | ------- |
| Mob is invisible or magenta | RP wiring graph break. No error is emitted. |
| Component silently ignored | `format_version` predates the component. |
| Entity never changes state | Component group not reachable from any event. |
| Two add-ons conflict on load | Duplicate UUIDs from an un-randomized template. |
| Edits vanish | Something hand-edited the `com.mojang` export target; the next `regolith run` overwrote it. Edit `packs/` instead. |
| Filter output missing from `packs/` | Expected, not a bug. Filters run against `.regolith/tmp`; generated files appear only in the export target. |
| Extension flags valid code | Blockception avoids experimental features by design. mct is the authority. |
| Custom item aux IDs unstable | Known ecosystem limitation: item ID assignment depends on pack stack order at world load, which is non-deterministic and unknowable at build time. Do not build logic on aux IDs. |

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

## PART 2 — For the agent

Content for `.claude/skills/bedrock-geometry/SKILL.md`.

Prior art: `Logeaddd/minecraft-ai-generate-bbmodel` (MIT, see section 5a)
solves an adjacent problem for `.bbmodel`. Several rules below are borrowed
from it and marked. Nothing exists that targets Bedrock `.geo.json` directly.

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

From a working model:

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
(<https://www.blockbench.net/wiki/docs/plugin/>) rather than editing
`.geo.json` files. Wrap edits in `Undo.initEdit` / `Undo.finishEdit` and call
`Canvas.updateView`. Blockbench uses `from`/`to` in memory and emits
`origin`/`size` on export — do not assume they match.
