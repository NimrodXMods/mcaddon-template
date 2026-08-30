# GameTest

**Status: not wired up.** Notes only, per the skill policy in `docs/decisions.md`. Nothing here runs yet. These are templates to copy
into the behavior pack, not a working suite.

## Where GameTests actually live

Not here. GameTest scripts ship **inside the behavior pack**, because the game
loads them from the pack at runtime:

```
packs/BP/
  scripts/
    main.js                   # the manifest's script entry point
                              #   ("entry": "scripts/main.js"); imports every
                              #   test file
    gametests/
      ExampleTests.js
  structures/
    addontemplate/
      example.mcstructure     # human-exported, see below
```

This file holds notes and drafts only - it is not code and nothing here runs.
Wiring a test into `packs/BP/scripts/index.js` is what makes it run. Per the
skill policy in `docs/decisions.md`, these notes become
`.claude/skills/bedrock-gametest/SKILL.md` once GameTests have actually been
authored and run against real content.

## Two blockers before any test can run

1. **Every test needs a `.mcstructure`**, and those can only be produced in
   game: build the environment in Creative, `/give @s structure_block`, set the
   block to Save mode, name it `addontemplate:<name>`, save, then copy the file
   out of `com.mojang/structures/`. An agent cannot author one.
2. **Beta APIs must be enabled** on the test world, and the BP manifest needs a
   `@minecraft/server-gametest` dependency. **The base template deliberately
   does not enable these** - it assumes production, and the manifest depends
   only on stable `@minecraft/server` and `@minecraft/server-ui`. Enabling Beta
   APIs is a per-project decision made at instantiation. See
   `docs/decisions.md`.

## Template

```javascript
import { register } from "@minecraft/server-gametest";

register("ExampleTests", "entitySpawns", (test) => {
  test.spawn("addontemplate:example_entity", { x: 1, y: 2, z: 1 });
  test.assertEntityPresentInArea("addontemplate:example_entity", true);
  test.succeed();
})
  .maxTicks(100)
  .structureName("addontemplate:example");
```

Conventions worth keeping: class names `PascalCase`, test names `camelCase`
reading as a sentence, structure names `snake_case`. One behavior per test -
if it needs ten assertions, split it. Keep `maxTicks` at the minimum that
passes; a generous budget hides performance regressions.

Run with `/gametest run ExampleTests:entitySpawns`, or `/gametest runset
ExampleTests` for the class.
