#!/usr/bin/env bash
#
# Build a GameTest world (.mcworld) from the COMPILED packs.
#
# Produces build/worlds/testworld.mcworld, containing the behavior and
# resource packs plus every .mcstructure fixture under BP/structures/.
# Double-click it to import, or unzip it into a folder under
# com.mojang/minecraftWorlds/.
#
# Why "-i build" and not "-i .":
#
#   mct's -i defaults to the working directory, so a bare `mct exportworld`
#   packs packs/ - the SOURCE - and the world then lacks everything the
#   filters generate: the templated entities, render controllers, en_US.lang
#   and textures_list.json. Pointing at build/ ships what the game actually
#   loads. Same source/output invariant verify.sh follows.
#
#   It also keeps mct's manifest rewrite off the source tree. exportworld,
#   like exportaddon, resolves script module dependencies against the registry
#   and writes them back as arrays ([2,9,0]) where a semver string ("2.9.0")
#   is correct. With -i build that lands on derived output, so unlike
#   deploy.sh this script needs no snapshot-and-restore. It is asserted below
#   rather than assumed.
#
# EXPERIMENTS - one toggle, not two.
#
#   The exported world always has experiments.gametest = 1. Despite the key
#   name that is the toggle shown in world settings as "Beta APIs", and it is
#   the one @minecraft/server-gametest needs. Evidence: `mct world set` reads
#   this world and prints "Beta APIs: true" while `gametest` is the only
#   experiment key present in level.dat.
#
#   So a world from this script should need no experiment set by hand. The
#   global --betaapis/--no-betaapis flags are inert on exportworld, and so is
#   `mct world set --betaApis` (see below) - neither is needed here.
#
#   Not confirmed in game. If an imported world loads without the add-on,
#   check the experiment toggles first. See docs/gametest-notes.md.

set -euo pipefail

cd "$(dirname "$0")/.."

# Skip the validation gate for fast iteration. The world still gets built from
# build/, so build/ must already exist and be current.
VERIFY=1
if [ "${1:-}" = "--no-verify" ]; then
  VERIFY=0
fi

if [ "$VERIFY" = "1" ]; then
  echo "==> verify"
  ./scripts/verify.sh
else
  echo "==> skipping verify (--no-verify); build/ must already be current"
fi

if [ ! -d build ]; then
  echo
  echo "FAIL: no build/ to export."
  echo "Run ./scripts/verify.sh (or 'regolith run ci') first - this script"
  echo "packs the compiled output, not packs/."
  exit 1
fi

OUT="build/worlds/testworld.mcworld"

echo
echo "==> mct exportworld   (-i build)"

# Bounded for the same reason as verify.sh and deploy.sh: mct can hang, and a
# hang must fail loudly rather than block.
MCT_TIMEOUT="${MCT_TIMEOUT:-60}"

# Insurance, not ceremony: if a future mct version starts reaching past -i,
# this catches it instead of letting a rewritten manifest reach a commit.
MANIFESTS="packs/BP/manifest.json packs/RP/manifest.json"
SNAP="$(mktemp -d)"
for m in $MANIFESTS; do cp "$m" "$SNAP/$(echo "$m" | tr '/' '_')"; done

mkdir -p build/worlds

set +e
timeout "$MCT_TIMEOUT" mct -i build exportworld --of "$OUT"
EXPORT_EXIT=$?
set -e

for m in $MANIFESTS; do
  snap="$SNAP/$(echo "$m" | tr '/' '_')"
  if ! cmp -s "$snap" "$m"; then
    echo "  WARNING: mct rewrote $m despite -i build; restoring."
    echo "  This contradicts docs/gametest-notes.md - update it."
    cp "$snap" "$m"
  fi
done
rm -rf "$SNAP"

if [ "$EXPORT_EXIT" = "124" ]; then
  echo
  echo "FAIL: mct exportworld exceeded ${MCT_TIMEOUT}s and was killed."
  echo "mct has hung. Raise the budget with MCT_TIMEOUT=<seconds> only if the"
  echo "project is genuinely large."
  exit 1
fi

if [ ! -f "$OUT" ]; then
  echo
  echo "FAIL: exportworld exited $EXPORT_EXIT but produced no $OUT."
  echo "Do not treat this as a successful build. Note that 'mct ensureworld'"
  echo "reports success while writing nothing - see docs/gametest-notes.md."
  exit 1
fi

echo
echo "==> world"
echo "  $OUT"

# The in-game world name is derived from the -i folder basename and there is
# no flag for it, so this reports what you will actually see in the world list.
echo "  in-game name: \"build World\" (derived from -i; not configurable)"
echo
echo "  build/ is gitignored and verify.sh clears it, so this world is"
echo "  ephemeral - re-run this script rather than archiving it."
