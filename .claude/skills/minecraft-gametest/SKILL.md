---
name: Minecraft GameTest Framework
description: This skill should be used when the user wants to create, run, or manage Minecraft GameTest Framework tests for Bedrock Edition behavior packs. Covers project setup, test registration, structure creation, assertion API, simulated players, async tests, and test organization best practices.
version: 1.0.0
---

# Minecraft GameTest Framework

You are an expert in the Minecraft GameTest Framework for Bedrock Edition. You write clear, minimal tests that validate specific behaviors — not integration marathons.

## Documentation References

Always fetch fresh docs before writing test code — the API is versioned and beta APIs evolve:

- **Getting started guide**: `https://learn.microsoft.com/en-ca/minecraft/creator/documents/gametestgettingstarted`
- **Building your first GameTest**: `https://learn.microsoft.com/en-ca/minecraft/creator/documents/gametestbuildyourfirstgametest`
- **`@minecraft/server-gametest` API reference**: `https://learn.microsoft.com/en-ca/minecraft/creator/scriptapi/minecraft/server-gametest/minecraft-server-gametest`
- **Scripting setup (TypeScript)**: `https://learn.microsoft.com/en-ca/minecraft/creator/documents/scriptinggettingstarted`
- **Official example tests**: `https://github.com/microsoft/minecraft-gametests`
- **Scripting samples (TypeScript starter)**: `https://github.com/microsoft/minecraft-scripting-samples`

See `references/gametest-links.md` for a curated link list.

## Project Setup

### Prerequisites

- Node.js LTS (`https://nodejs.org/`)
- Visual Studio Code
- Minecraft Bedrock Edition with **Beta APIs experiment** enabled
- World settings: **Creative mode**, **Flat world**, **Normal difficulty**, **Cheats enabled**

### Behavior Pack Structure

```
my-tests/
├── manifest.json
├── structures/
│   └── my-tests/
│       └── my_structure.mcstructure   # exported from in-game structure block
└── scripts/
    └── MyTests.js                      # or MyTests.ts with build step
```

Deploy to:
```
%APPDATA%\Roaming\Minecraft\development_behavior_packs\my-tests\
```

### manifest.json

```json
{
  "format_version": 2,
  "header": {
    "description": "My GameTests",
    "name": "My Tests",
    "uuid": "<generate-unique-uuid>",
    "version": [1, 0, 0],
    "min_engine_version": [1, 21, 0]
  },
  "modules": [
    {
      "description": "GameTest scripts",
      "type": "script",
      "language": "javascript",
      "uuid": "<generate-unique-uuid>",
      "version": [1, 0, 0],
      "entry": "scripts/MyTests.js"
    }
  ],
  "dependencies": [
    {
      "module_name": "@minecraft/server",
      "version": "1.13.0-beta"
    },
    {
      "module_name": "@minecraft/server-gametest",
      "version": "1.0.0-beta"
    }
  ]
}
```

**Always use separate UUIDs for `header` and each `modules` entry.** Generate via `uuidgen` or an online tool.

### TypeScript Setup (preferred)

```bash
# Clone starter or copy ts-starter from minecraft-scripting-samples
npm install
```

Configure `.env`:
```ini
PROJECT_NAME="my-tests"
MINECRAFT_PRODUCT="BedrockGDK"   # or PreviewGDK
```

Build commands:
```bash
npx just-scripts local-deploy          # one-shot deploy
npx just-scripts local-deploy --watch  # watch + auto-deploy on save
npx just-scripts lint                  # check errors
npx just-scripts lint --fix            # auto-fix
npx just-scripts mcaddon               # package as .mcaddon
```

## Registering Tests

### Basic synchronous test

```typescript
import { register } from '@minecraft/server-gametest';

register('MyTestClass', 'myTestName', (test) => {
  // setup & assertions
  test.succeed();
})
  .maxTicks(200)
  .structureName('my-tests:my_structure');
```

- **First arg**: class name — groups related tests, used in `/gametest run` commands
- **Second arg**: test name — unique within the class
- **Third arg**: test function receiving a `Test` object

### Async test

```typescript
import { registerAsync } from '@minecraft/server-gametest';

registerAsync('MyTestClass', 'asyncTest', async (test) => {
  test.spawn('minecraft:creeper', { x: 2, y: 2, z: 2 });
  await test.idle(40);   // wait 40 ticks
  test.assertEntityPresentInArea('minecraft:creeper', true);
  test.succeed();
})
  .maxTicks(300)
  .structureName('my-tests:my_structure');
```

### RegistrationBuilder chaining

```typescript
register('MyClass', 'myTest', fn)
  .maxTicks(400)                   // fail if not complete within N ticks
  .structureName('ns:name')        // structure to load (namespace:name)
  .rotateTest(true)                // run test in all 4 rotations
  .batch('myBatch')                // group for batch execution
  .required(true)                  // mark as required (default)
  .tag('myTag');                   // tag for selective running
```

## Test API — Core Methods

### Spawning

```typescript
test.spawn('minecraft:fox', { x: 5, y: 2, z: 5 });           // entity by type id
test.spawnItem(new ItemStack(MinecraftItemTypes.Apple), pos);  // item entity
```

### Assertions

```typescript
test.assertEntityPresentInArea('minecraft:chicken', true);     // true = must exist
test.assertEntityPresentInArea('minecraft:chicken', false);    // false = must NOT exist
test.assertBlockPresent(MinecraftBlockTypes.Stone, pos, true);
test.assertEntityHasComponent(entity, 'minecraft:health');
test.assertRedstonePower(pos, 15);
test.assertIsWaterlogged(pos, true);
```

### Completion

```typescript
test.succeed();                      // pass immediately
test.fail('reason string');          // fail immediately

test.succeedWhen(() => {             // poll until condition passes or maxTicks hit
  test.assertEntityPresentInArea('minecraft:chicken', false);
});

test.succeedOnTick(100);             // pass at tick N
test.succeedWhenEntityPresent('minecraft:chicken', pos, false);
test.succeedWhenBlockPresent(MinecraftBlockTypes.Stone, pos, true);
```

### Utilities

```typescript
test.idle(20);                       // async: wait N ticks (use with await)
test.walkTo(player, pos, 1);         // async: simulated player walks to pos
test.print('debug message');         // log to test output
```

### Simulated Player

```typescript
const player = test.spawnSimulatedPlayer({ x: 2, y: 2, z: 2 }, 'TestPlayer');

player.lookAtEntity(entity);
player.attack();
player.jumpUp();
player.moveToLocation({ x: 5, y: 2, z: 5 }, { strafingSpeed: 1 });
player.useItemInSlot(0);
player.interact();
```

## Creating Structures

Every test needs a `.mcstructure` file that defines the environment:

1. Build your test environment in-game in Creative mode
2. Run `/give @s structure_block`
3. Place the structure block adjacent to your build
4. Open its UI → set mode to **Save**
5. Name it (e.g., `my-tests:my_structure`) — **namespace must match your pack id**
6. Set bounds to encompass the build
7. Click **Save**
8. Copy the exported `.mcstructure` from:
   ```
   %APPDATA%\Roaming\Minecraft\games\com.mojang\structures\
   ```
9. Place in `structures/my-tests/my_structure.mcstructure`

**Keep structures minimal.** Test environments should be the smallest space that exercises the behavior. Oversized structures slow test runs and obscure failures.

## Running Tests

| Command | Effect |
|---------|--------|
| `/gametest run <class>:<name>` | Run one test |
| `/gametest runset <class>` | Run all tests in a class |
| `/gametest runall` | Run every registered test |
| `/gametest runthis` | Run test the player is inside |
| `/gametest clearall` | Remove all active test structures |
| `/gametest runbatch <batchName>` | Run tests tagged with a batch |

Tests spawn structures starting at your position. Use a flat, open area.

## Test Organization Guidelines

### Naming

- Class names: `PascalCase`, descriptive category (`CombatTests`, `RedstoneTests`)
- Test names: `camelCase`, reads as a sentence (`foxAttacksChicken`, `pistonPushesBlock`)
- Structure names: `snake_case`, match the test (`fox_attacks_chicken`)

### One behavior per test

Each test validates exactly one thing. If a test needs 10 assertions to pass, split it into multiple tests. A failed test name should immediately communicate what broke.

### Tick budgets

| Scenario | Suggested `maxTicks` |
|----------|----------------------|
| Instant assertion | 20–50 |
| Mob AI interaction | 200–400 |
| Redstone circuit | 40–100 |
| Simulated player sequence | 300–600 |

Set `maxTicks` to the minimum needed — tests that run long mask performance regressions.

### Async vs sync

- Use **sync** (`register`) + `succeedWhen` for event-driven conditions (mob dies, block changes)
- Use **async** (`registerAsync`) + `await test.idle()` when you need precise tick control or sequential player actions

### Batch grouping

Group related tests with `.batch('batchName')` so you can run subsets:
```
/gametest runbatch combatSuite
```

### Before/after batch hooks

```typescript
import { setBeforeBatchCallback, setAfterBatchCallback } from '@minecraft/server-gametest';

setBeforeBatchCallback('combatSuite', () => {
  // reset shared state before the batch
});

setAfterBatchCallback('combatSuite', () => {
  // cleanup
});
```

### Do not

- Do not rely on world state outside the structure — tests run concurrently and can interfere
- Do not hardcode absolute coordinates — use relative positions within the structure volume
- Do not leave `test.print()` calls in committed tests — remove debug output before shipping
- Do not use `maxTicks` as a timeout hack — if a condition is never met, the test design is wrong

## File Organization for Multiple Test Suites

```
scripts/
├── index.js           # imports all test files (entry point)
├── combat/
│   ├── FoxTests.js
│   └── CreeperTests.js
├── redstone/
│   └── PistonTests.js
└── player/
    └── InventoryTests.js
```

`index.js`:
```javascript
import './combat/FoxTests.js';
import './combat/CreeperTests.js';
import './redstone/PistonTests.js';
import './player/InventoryTests.js';
```

Manifest `entry` points only to `scripts/index.js`.
