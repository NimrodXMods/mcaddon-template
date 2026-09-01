// SimulatedPlayer tests against the committed fixture.
//
// The fixture is packs/BP/structures/nimrodx_template/example.mcstructure,
// built from docs/fixtures/example.volume.json: a 5x5 stone pad at relative
// y=0 with three layers of air above it. Relative coordinates below are
// measured from that structure's origin, so y=1 is standing on the pad.
//
// These require BOTH the "GameTest Framework" and "Beta APIs" experiments on
// the world. @minecraft/server-gametest is a beta module; without Beta APIs
// the pack fails to load rather than skipping the tests.
import { register } from "@minecraft/server-gametest";

const FIXTURE = "nimrodx_template:example";

// Ticks. Walking two blocks takes well under a second, but a simulated player
// spawns falling and the pathfinder does not start until it lands, so the
// budget is generous rather than tight - a failure here should mean "never
// arrived", not "was still on its way".
const WALK_TIMEOUT = 200;

// The simulated player walks from one corner of the pad to another.
// This is the movement primitive everything else builds on: if this passes,
// an agent can position a player deliberately instead of teleporting it.
register("template", "simulated_player_walks", (test) => {
  const spawn = { x: 1, y: 1, z: 1 };
  const target = { x: 3, y: 1, z: 3 };

  const player = test.spawnSimulatedPlayer(spawn, "WalkTester");

  // moveToLocation is continuous - it sets the player walking and returns
  // immediately. The assertion is what waits.
  player.moveToLocation(target);

  test.succeedWhen(() => {
    test.assertEntityInstancePresent(player, target);
  });
})
  .structureName(FIXTURE)
  .maxTicks(WALK_TIMEOUT);

// The simulated player breaks a block it is standing next to.
// Movement alone only proves the entity exists; this proves it can act on the
// world, which is what add-on behaviour testing actually needs.
register("template", "simulated_player_breaks_block", (test) => {
  const spawn = { x: 1, y: 1, z: 1 };
  const targetBlock = { x: 2, y: 0, z: 1 };

  const player = test.spawnSimulatedPlayer(spawn, "BreakTester");

  // A simulated player must be facing a block to break it; breakBlock does
  // not aim on its own.
  player.lookAtBlock(targetBlock);
  player.breakBlock(targetBlock);

  test.succeedWhen(() => {
    test.assertBlockPresent("minecraft:air", targetBlock, true);
  });
})
  .structureName(FIXTURE)
  .maxTicks(WALK_TIMEOUT);
