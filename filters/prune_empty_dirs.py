#!/usr/bin/env python3
r"""Remove empty directories from the built packs.

jsonte's `--remove-src` deletes the .templ/.modl source files it consumes but
not the directory holding them, so `BP/modules/` ships inside the behaviour
pack as an empty folder. Minecraft ignores unknown directories, so this was
cosmetic until `sanity_check` started (correctly) flagging it:

    [WARNING] BP\modules is not a valid folder. Did you mean BP\volumes?

A warning on every build is how a team learns to ignore warnings, so remove
the cause rather than disabling the check. See docs/bedrock-jsonte-notes.md.

This is deliberately generic - it prunes *any* empty directory rather than
special-casing `modules/`, because the same wart appears for any filter that
consumes every file in a folder. Runs on the Regolith temp copy, never on
`packs/`.
"""

import os
import sys

removed = []

for pack in ("BP", "RP"):
    if not os.path.isdir(pack):
        continue
    # Bottom-up, so a directory that only contained empty directories is
    # itself empty by the time it is visited.
    for root, dirs, files in os.walk(pack, topdown=False):
        if root == pack:
            continue
        if not os.listdir(root):
            os.rmdir(root)
            removed.append(root.replace(os.sep, "/"))

for r in sorted(removed):
    print(f"[prune_empty_dirs] removed empty directory {r}")

if not removed:
    print("[prune_empty_dirs] no empty directories")
