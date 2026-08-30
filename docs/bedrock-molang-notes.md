# Molang notes

**Planned skill:** `bedrock-molang`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-molang/SKILL.md` only after Molang has actually been used - render controller variants, query conditions, animation controllers. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

Query namespaces, context validity (what is valid where), and the
arrow-operator gotchas.

## Confirmed lessons

**Nothing verified yet.** No Molang has been written in this project. Do not
seed this file from documentation or recall - the point is to record what
actually surprised us.

## Open questions

- Which queries are valid in which context (render controller vs animation
  controller vs component).
- The arrow operator and when it is needed.
- How Molang errors surface, if at all.
