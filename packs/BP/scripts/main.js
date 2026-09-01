// Entry point declared by the script module in packs/BP/manifest.json.
// The manifest referenced this path before the file existed; mct validate
// does not catch a dangling script entry, so it only surfaced at load time.
import { world, system } from "@minecraft/server";

// GameTests only register if something imports them; the manifest's entry
// point is the only file the game loads on its own. This import is what puts
// "template:simulated_player_walks" on the /gametest run list.
//
// It also makes the pack depend on @minecraft/server-gametest, a beta module.
// To ship a production build without Beta APIs, drop this import AND the
// @minecraft/server-gametest dependency from the manifest - see
// docs/gametest-notes.md.
import "./gametests/ExampleTests.js";

system.run(() => {
  world.sendMessage("§aAddOnTemplate loaded.");
});
