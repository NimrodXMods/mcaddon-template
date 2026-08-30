#!/usr/bin/env bash
#
# Package a release. Human-run: agents are denied `mct deploy` in
# .claude/settings.json.
#
# This does NOT bump manifest versions. bump_manifest corrupts script module
# dependencies (see AGENTS.md gotcha table), so versions are bumped by hand.
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
# mct 0.17.7 subcommands frequently write their output and then never exit
# (observed on create, exportaddon). Cap it and judge by the artifact, not
# by the exit status. See AGENTS.md section 3b.
timeout 180 mct exportaddon -i . -o build || true

echo
echo "==> artifacts"
find build -maxdepth 1 -name '*.mcaddon' -o -maxdepth 1 -name '*.mcpack' | sed 's/^/  /'
