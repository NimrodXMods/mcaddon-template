# Entity authoring notes

**Planned skill:** `bedrock-entity`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-entity/SKILL.md` only after a real mob - one with behaviors, spawn rules, and loot - has shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

## What the skill must cover

Component groups and events as a state chart. Spawn rules. The BP/RP split
for a single entity.

## Confirmed lessons

- A minimal working entity is very small: `identifier`, `is_spawnable`,
  `is_summonable`, plus `minecraft:health`, `collision_box`, `type_family`,
  `physics`. Start there and add.
- `is_summonable` gates `/summon`; `is_spawnable` gates the spawn egg. Set both
  while iterating or you will think the entity is broken when it is not
  reachable.
- The spawn egg is defined on the **RP** side (`spawn_egg` in the client
  entity), not the BP.
- `name_ninja` needs a separate `spawn_eggs` settings block; enabling
  `entities` alone silently leaves the egg unnamed.
- Lang keys are per-type and not guessable: `entity.<id>.name` for the entity,
  `item.spawn_egg.entity.<id>.name` for its egg. `name_ninja` with `auto_name`
  generates both correctly from the identifier - prefer that to hand-writing
  `.lang` lines.
- `format_version` on the BP entity (1.20.80 here) and the RP client entity
  (1.10.0) are **different numbering lines**. One value does not work for both
  files.

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- Entities are **state charts, not objects**. Component groups are states,
  events are the only transitions. A group no event adds is dead code, and
  nothing warns you - not the engine, not `mct validate`.
- A component predating the file's `format_version` is silently ignored. That
  is the quiet failure behind "I added the component and nothing happened".

The entity built here has **no component groups and no events** - it is four
components and nothing else. The state-chart model is the single most repeated
claim about Bedrock entities and is very likely right, but this project has not
exercised it. Verifying it is the main reason to author a real mob next.

## Open questions

- Component-group/event patterns worth templating (tamed/wild, baby/adult).
- How much of this jsonte should generate vs. be written literally.
- Spawn rule tuning - nothing authored yet.
