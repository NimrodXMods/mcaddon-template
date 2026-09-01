# jsonte templating notes

**Planned skill:** `bedrock-jsonte`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-jsonte/SKILL.md` only after templates are actually generating content - a block family or a mob variant set. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

As of the `nimrodx_template:stalker` work, templates **are** generating content:
one entity from two modules. That is one mob, not a variant set, so the bar
above is approached but not met.

## What the skill must cover

`.templ` syntax, modules, and when to template versus write literal JSON.

**And nothing else.** Entity semantics belong in `bedrock-entity`, not here -
see the decision "Neither templating tool is standard" in `docs/decisions.md`.
jsonte is a replaceable layer; keeping its syntax quarantined in one skill
means swapping it later costs one skill, not all of them.

## Where jsonte sits in the ecosystem

Checked 2026-08-30. Worth knowing before treating it as authoritative:

- It is **not** in the Bedrock-OSS standard library. That repo holds twelve
  filters and jsonte is not one of them; three of this project's four filters
  (`bump_manifest`, `name_ninja`, `texture_list`) are, and jsonte is not.
- Searching the entire `Bedrock-OSS/regolith` repo for "jsonte" returns **zero**
  hits. There is no official endorsement; the docs' only install example is
  `regolith install name_ninja`.
- It is reachable only through the Bedrock-OSS filter **resolver**, an
  uncurated name→URL map. Being listed there means a short name resolves,
  nothing more.
- `MCDevKit/jsonte` had 8 stars and one findable public adopter
  (`r4isen1920/OriginsPE`) when checked. Actively maintained (last push
  2026-05-27), Go, MIT.

None of this is a reason to drop it - the alternative scored worse on every
axis that mattered - but do not write the skill as though jsonte were the
Bedrock standard. It is a defensible local choice.

## Known weakness: `$extend` is a string

`$extend: ["proximity_aggro"]` resolves by **name**. Rename or move a `.modl`
and nothing type-checks the reference; the module simply stops being applied.
Whether jsonte errors or silently skips has not been tested here - worth
finding out, since the silent case is the dangerous one.

This is the one place `modular_mc` is genuinely better: its `_resource_map.ts`
exports resources as TypeScript symbols, so a rename is a loud failure the
editor catches. Recorded, not solved. See `docs/decisions.md`.

## Confirmed lessons

- The filter is **self-contained**: it ships `jsonte.exe` / `jsonte-mac` /
  `jsonte-linux` and needs no separate install (unlike `command_lang`).
- It scopes **both** `data/jsonte` and `data/json_templating_engine`. A
  `Skipping non-existent scope file` warning for whichever you do not have is
  benign - do not rename your data folder chasing it.
- Filter output exists only in the export target, never in `packs/` - a
  `packs/` diff shows what you wrote, not what the game loads.
- The Regolith filter never invokes Java: its cached `filter.json` runs the
  bundled binary directly (`runWith: "exe"`), so a Regolith-only workflow
  needs no Java.

### Recognised extensions

Strings pulled from `jsonte.exe`: `.templ`, `.modl`, `.template`, plus plain
`.json` and `.lang`. This project uses `.templ` for files that generate an
output file and `.modl` for modules that do not.

### The invocation is fixed

The cached `filter.json` always runs:

```
jsonte.exe compile --remove-src --scope data/jsonte
                   --scope data/json_templating_engine
                   --cache-dir ../jsonte/cache  BP/ RP/
```

Two consequences that are easy to lose an hour to:

- **Only `BP/` and `RP/` are compiled.** Modules must live inside one of them.
  `data/jsonte` is a *scope* path - global variables - not a module search
  path. Putting `.modl` files there means they are never loaded, silently.
- `--include` / `--exclude` are real jsonte flags but **unreachable** here,
  because the filter hardcodes its arguments and Regolith's `settings` block
  does not pass extra ones through.

### Templates must be valid JSON

`{{ }}` interpolation only works **inside a string**. Writing

```json
"value": {{2 + 3}}
```

fails to parse before jsonte ever evaluates it:

```
[ERROR] Failed to parse JSON
[+]: Unexpected token '{' (U+007B) at line 11, column 40
      at #/$template/minecraft:entity/components/minecraft:health/value
```

Write `"value": "{{2 + 3}}"` instead. A string whose **entire** content is one
expression is **type-coerced** on output - that emits `"value": 5`, an
unquoted number, not `"5"`. This is what makes `$scope` usable for numeric
tuning values.

Comments (`//`) are accepted in `.templ` / `.modl` and are stripped from the
output, same as in `data/jsonte/data.json`.

### Modules

`$module` declares a named template that generates no file of its own;
`$extend: ["a", "b"]` merges them into the extending file. Confirmed working:

```
[INFO] Loaded module modules\wandering.modl
[INFO] Loaded module modules\proximity_aggro.modl
[INFO] Templating file BP\entities\stalker.behavior.templ
[INFO] Writing file BP\entities\stalker.behavior.json
```

- Merging is **deep**. Two modules both writing
  `component_groups.calm` merge their keys rather than one overwriting the
  other - that is what lets `wandering` contribute behaviours into a group
  `proximity_aggro` created.
- `$scope` on the extending file supplies variables the modules interpolate.
  This is the parameterisation mechanism: a second mob of the same shape
  differs by the numbers in `$scope`, not by a copied state machine.
- **Key order is not preserved.** Merged module content lands *before* the
  extending file's own keys, and `format_version` ended up last in the output.
  Legal JSON, and the game does not care, but do not diff expanded output
  against a hand-written file expecting order to line up.

### Global scope values are substituted ONCE; `$scope` gets another pass

The sharpest gotcha found so far, because it fails **silently into the output**
rather than erroring.

A value in `packs/data/jsonte/data.json` is substituted once. If that value
itself contains `{{...}}`, the inner reference is **not** resolved - it reaches
the generated file verbatim:

```jsonc
// data/jsonte/data.json
"studio": "nimrodx",
"pack": "template",
"asset_path": "{{studio}}/{{pack}}"      // <- do not do this
```

```jsonc
// in a .templ
"table": "loot_tables/{{asset_path}}/stalker.loot.json"
```

```json
"table": "loot_tables/{{studio}}/{{pack}}/stalker.loot.json"
```

That is valid JSON containing a path that cannot exist, so nothing downstream
complains - `mct validate` passed it, and only reading the built file caught it.

**It is not a syntax problem.** Writing the value as a single expression
(`"{{studio + '_' + pack}}"`) behaves identically. What matters is *where the
value is declared*:

| Declared in | Resolves nested refs? |
| --- | --- |
| `data/jsonte/data.json` (global) | **No** - one pass |
| a `.templ`'s own `"$scope"` | **Yes** |
| a `.modl` module, used by the extending file | **Yes** |

Modules work because `$extend` merges their content into the template, which is
then evaluated again - the merged text gets a second pass that the template's
own literals never get. That asymmetry is the trap: the *same* `{{namespace}}`
reference resolved correctly in `proximity_aggro.modl` and incorrectly in
`stalker.behavior.templ`, in the same build.

**The idiom this project uses:** keep primitives global (`studio`, `pack`) and
derive the joined forms in each template's `$scope`:

```jsonc
"$scope": {
  "namespace":  "{{studio + '_' + pack}}",   // nimrodx_template
  "asset_path": "{{studio + '/' + pack}}"    // nimrodx/template
}
```

Four lines repeated per template, in exchange for one place to change the
project identity. Modules then read `{{namespace}}` from the extending file's
scope and need no changes.

**Check the built output, not the template**, after any change to a derived
value. `grep -rl "{{" build/` should return nothing.

### Filter ordering - now observed, not inferred

Previously listed as unverified reasoning. jsonte now demonstrably runs first
and later filters consume its output: `name_ninja` generated
`entity.nimrodx_template:stalker.name` and
`item.spawn_egg.entity.nimrodx_template:stalker.name` for an entity that **only
exists after jsonte expands `stalker.behavior.templ`**. A filter running before
jsonte could not have seen that identifier.

### Wart, now fixed: `--remove-src` leaves the directory

`--remove-src` deletes the source `.modl` / `.templ` files but **not** the
directory holding them, so an empty `modules/` folder shipped inside the
behaviour pack. Minecraft ignores unknown directories, so this looked cosmetic
and was left alone.

It stopped being cosmetic when `sanity_check` was added: the very first run
flagged it, correctly, as a folder that is not part of the pack format.

```
[sanity_check] [WARNING] BP\modules is not a valid folder. Did you mean BP\volumes?
```

(The "did you mean volumes" suggestion is Levenshtein noise; the detection is
right.) It is not fixable from `config.json` - see "the invocation is fixed"
above - so the fix is a local filter, `filters/prune_empty_dirs.py`, which runs
after jsonte and removes *any* empty directory from the built packs. Generic
rather than special-cased, because the same wart appears for any filter that
consumes every file in a folder.

The general lesson: a "cosmetic" build artifact becomes a real cost the moment
something starts checking, because a permanent warning trains people to ignore
warnings.

## Inherited from research - NOT verified here

- The standalone jsonte CLI needs Java 11+. It has never been run in this
  project, and the Regolith filter does not use it.

## Open questions

- `$copy` and `getLatestBPFile(...)` for extending **vanilla** entities -
  documented upstream, not tried here.
- Whether `$files` (generating many files from one template) is the right tool
  for a mob variant set. Nothing here generates more than one file per
  template yet.
- Where the line is between templating and just writing the JSON. Current
  working answer: the BP entity is a `.templ` because its state machine is
  shared; the RP client entity is literal `.json` because every field in it is
  unique to the one mob.
