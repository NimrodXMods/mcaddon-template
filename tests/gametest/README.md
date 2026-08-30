# GameTest

**Status: not wired up.** Nothing here runs yet. These are templates to copy
into the behavior pack, not a working suite.

## Where GameTests actually live

Not here. GameTest scripts ship **inside the behavior pack**, because the game
loads them from the pack at runtime:

```
packs/BP/
  scripts/
    index.js                  # entry point; imports every test file
    gametests/
      ExampleTests.js
  structures/
    addontemplate/
      example.mcstructure     # human-exported, see below
```

This `tests/gametest/` folder holds drafts and notes only. Moving a test here
does not disable it; wiring it into `packs/BP/scripts/index.js` is what makes
it run.

## Two blockers before any test can run

1. **Every test needs a `.mcstructure`**, and those can only be produced in
   game: build the environment in Creative, `/give @s structure_block`, set the
   block to Save mode, name it `addontemplate:<name>`, save, then copy the file
   out of `com.mojang/structures/`. An agent cannot author one.
2. **Beta APIs must be enabled** on the test world, and the BP manifest needs a
   `@minecraft/server-gametest` dependency. Neither is set on this project - the
   manifest currently depends only on `@minecraft/server` and
   `@minecraft/server-ui`, both stable. Adding a beta dependency changes what
   the pack requires to load, so it is a deliberate decision, not a default.

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
