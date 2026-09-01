// SimulatedPlayer tests against the committed fixture.
//
// The fixture is packs/BP/structures/nimrodx_template/example.mcstructure,
// built from docs/fixtures/example.volume.json: a 5x5 stone pad at relative
// y=0 with three layers of air above it. Relative coordinates below are
// measured from that structure's origin, so y=1 is standing on the pad.
//
// These need the world's "Beta APIs" experiment - the `gametest` key in
// level.dat, which `mct exportworld` sets unconditionally. It is one toggle,
// not two. @minecraft/server-gametest is a beta module, so without it the
// pack fails to load rather than skipping the tests.
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

// CONTROL - this test MUST fail. It exists to prove the others mean something.
//
// simulated_player_breaks_block reported a pass while leaving its target block
// intact, which has two possible causes: either GameTest restores the
// structure after a run (so the pass is real and post-run blocks prove
// nothing), or assertBlockPresent is not evaluating what it appears to and the
// assertion passed vacuously.
//
// A green beacon here means the second: the harness is not discriminating, and
// every pass recorded so far is worthless. A red beacon means assertions do
// evaluate block types, which leaves structure restoration as the explanation
// and the break test's pass as genuine.
//
// Delete this once that question is settled - a permanently failing test in
// the suite is how a team learns to ignore red.
register("template", "control_must_fail", (test) => {
  // The pad is stone. It is never diamond. If this ever succeeds, the
  // assertion is not looking at the block.
  test.succeedWhen(() => {
    test.assertBlockPresent("minecraft:diamond_block", { x: 2, y: 0, z: 1 }, true);
  });
})
  .structureName(FIXTURE)
  // Short on purpose: it fails by timing out, and there is no reason to wait.
  .maxTicks(40);
