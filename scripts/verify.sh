#!/usr/bin/env bash
#
# Mandatory completion gate for this project.
#
# Compiles with regolith, validates with mct, and fails loudly on any error.
# No task is "done" until this exits 0.
#
# Checks BOTH the mct exit code and the counts inside the JSON report. mct
# does return a nonzero code on validation errors (4, observed), but the
# report is the authoritative record, and gating on both means a change in
# either behaviour cannot silently turn this into a no-op.

set -euo pipefail

cd "$(dirname "$0")/.."

REPORTS="reports"

# Optional profile argument. Default profile exports to com.mojang; CI has no
# com.mojang, so CI passes a profile whose export target is "local".
PROFILE="${1:-}"

# Clear the export target BEFORE running, not only after. Regolith refuses to
# overwrite files in the target it did not create ("Deletion safety check ...
# File is not on the list of files created by Regolith"), so a build/ left
# behind by an interrupted run - or by a manual `regolith run ci` - fails the
# NEXT verify with an error that looks like content corruption. Cleaning first
# makes the gate independent of whatever ran before it.
rm -rf build out

echo "==> regolith run ${PROFILE}"
regolith run ${PROFILE}

# A "local"-target profile exports into build/, which mct would then scan
# alongside packs/ - double-validating everything and doubling error counts.
# build/ is derived and gitignored; produce release artifacts with
# `mct exportaddon` as a separate step, not from here. out/ is mct's own
# default output directory and inflates the scan the same way.
rm -rf build out

echo
echo "==> mct validate addon"
rm -rf "$REPORTS"
mkdir -p "$REPORTS"

# Bounded. mct resolves script module dependencies (@minecraft/server, etc.)
# against the npm registry, and an unreachable-but-not-refusing network makes
# it stall for minutes rather than failing. A normal run is a few seconds.
MCT_TIMEOUT="${MCT_TIMEOUT:-60}"

set +e
timeout "$MCT_TIMEOUT" mct validate addon -i . -ot json -o "$REPORTS" --threads 8
MCT_EXIT=$?
set -e

if [ "$MCT_EXIT" = "124" ]; then
  echo
  echo "FAIL: mct validate exceeded ${MCT_TIMEOUT}s and was killed."
  echo "This is almost always a network stall, not a broken project: mct looks"
  echo "up script module dependencies on registry.npmjs.org. Check connectivity,"
  echo "or raise the budget with MCT_TIMEOUT=<seconds>."
  exit 1
fi

REPORT="$(ls "$REPORTS"/*.mcr.json 2>/dev/null | head -1)"
if [ -z "$REPORT" ]; then
  echo
  echo "FAIL: mct produced no report at $REPORTS/*.mcr.json (exit $MCT_EXIT)"
  exit 1
fi

echo
node -e '
const fs = require("fs");
const [report, mctExit] = process.argv.slice(1);
let d;
try {
  d = JSON.parse(fs.readFileSync(report, "utf8"));
} catch (e) {
  console.error("FAIL: could not parse " + report + ": " + e.message);
  process.exit(1);
}

const info = d.info || {};
const errors   = info.errorCount || 0;
const internal = info.internalProcessingErrorCount || 0;
// iTp === 3 marks an error item; cross-check it against errorCount.
const items = (d.items || []).filter(i => i.iTp === 3).length;

if (errors || internal || items) {
  console.error("VALIDATION FAILED  " + report);
  console.error("  errors:                    " + errors);
  console.error("  internal processing errors: " + internal);
  console.error("  error items (iTp=3):        " + items);
  if (info.errorSummary) {
    console.error("");
    console.error(info.errorSummary);
  }
  if (info.internalProcessingErrorSummary) {
    console.error(info.internalProcessingErrorSummary);
  }
  process.exit(1);
}

if (mctExit !== "0") {
  console.error("VALIDATION FAILED: report is clean but mct exited " + mctExit);
  console.error("Inspect " + report + " - this means mct signalled a failure");
  console.error("the report did not record, and the gate is not trustworthy.");
  process.exit(1);
}

console.log("clean  " + report);
console.log("  files scanned: " + (info.contentFileCounts || 0) +
            " content / " + (info.fileCounts || 0) + " total");

// Non-fatal. mct records recommendations as items with iTp 6 and counts
// warnings separately; neither affects errorCount, so both are invisible
// unless printed here. Human-readable text lives in info.summary[gId][gIx].
const summary = info.summary || {};
const text = (it) => ((summary[it.gId] || {})[String(it.gIx)] || {}).defaultMessage || it.gId;
const recs = (d.items || []).filter(i => i.iTp === 6);

if (info.warningCount) {
  console.log("  warnings: " + info.warningCount);
  if (info.warningSummary) console.log(info.warningSummary);
}
if (recs.length) {
  console.log("  recommendations: " + recs.length + " (non-fatal)");
  for (const r of recs) {
    console.log("    - " + (r.p ? r.p + ": " : "") + text(r));
  }
}
' "$REPORT" "$MCT_EXIT"
