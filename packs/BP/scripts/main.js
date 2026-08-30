// Entry point declared by the script module in packs/BP/manifest.json.
// The manifest referenced this path before the file existed; mct validate
// does not catch a dangling script entry, so it only surfaced at load time.
import { world, system } from "@minecraft/server";

system.run(() => {
  world.sendMessage("§aAddOnTemplate loaded.");
});
