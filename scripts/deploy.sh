#!/usr/bin/env bash
#
# Package a release. Human-run: agents are denied `mct deploy` in
# .claude/settings.json.
#
# The build profile runs bump_manifest, so manifest versions increment here.
#
# This does NOT install into com.mojang. `regolith run` already does that on
# every verify via the default profile's "development" export target. This
# produces a distributable .mcaddon in build/.

set -euo pipefail

cd "$(dirname "$0")/.."

# Never package something that does not validate.
echo "==> verify"
./scripts/verify.sh

echo
echo "==> regolith run build   (local export)"
regolith run build

echo
echo "==> mct exportaddon"
# Bounded for the same reason as verify.sh: mct can hang, and a hang must fail
# loudly rather than block. --offline is safe here - byte-identical archive.
MCT_TIMEOUT="${MCT_TIMEOUT:-60}"

# mct exportaddon REWRITES the source manifests as a side effect: it resolves
# the latest registry version of each script module dependency and writes it
# back as an array ([2,9,0]) where a semver string ("2.0.0") is correct. That
# corrupts packs/BP/manifest.json on every run, so snapshot and restore.
MANIFESTS="packs/BP/manifest.json packs/RP/manifest.json"
SNAP="$(mktemp -d)"
for m in $MANIFESTS; do cp "$m" "$SNAP/$(echo "$m" | tr '/' '_')"; done

set +e
timeout "$MCT_TIMEOUT" mct exportaddon -i . -o build --format mcaddon --offline
EXPORT_EXIT=$?
set -e

for m in $MANIFESTS; do
  snap="$SNAP/$(echo "$m" | tr '/' '_')"
  if ! cmp -s "$snap" "$m"; then
    echo "  note: restoring $m (mct exportaddon rewrote it)"
    cp "$snap" "$m"
  fi
done
rm -rf "$SNAP"

if [ "$EXPORT_EXIT" = "124" ]; then
  echo
  echo "FAIL: mct exportaddon exceeded ${MCT_TIMEOUT}s and was killed."
  echo "mct has hung. Raise the budget with MCT_TIMEOUT=<seconds> if the"
  echo "project is genuinely large, otherwise treat it as a hang."
  exit 1
fi

echo
echo "==> artifacts"
ARTIFACTS="$(find build -maxdepth 1 \( -name '*.mcaddon' -o -name '*.mcpack' \) 2>/dev/null)"
if [ -z "$ARTIFACTS" ]; then
  echo "FAIL: exportaddon exited $EXPORT_EXIT but produced no .mcaddon/.mcpack."
  echo "Nothing was packaged. Do not treat this as a successful release."
  exit 1
fi
echo "$ARTIFACTS" | sed 's/^/  /'
