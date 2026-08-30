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

- A working entity is very small. The one here is `identifier`,
  `is_spawnable`, `is_summonable`, plus five components - `minecraft:health`,
  `collision_box`, `type_family`, `physics`, `pushable` - and it renders in
  game. Whether any of the five can be dropped has not been tested; the file
  has carried all five since its first commit.
- The spawn egg is defined on the **RP** side (`spawn_egg` in the client
  entity), not the BP.
- `name_ninja` names the spawn egg from its own `spawn_eggs` settings block,
  separate from `entities`. Both are enabled here and both lines appear in the
  generated `.lang`.
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
- `is_summonable` gates `/summon` and `is_spawnable` gates the spawn egg. Both
  are `true` here and were never toggled independently, so which flag gates
  what is documentation, not observation.
- Enabling `name_ninja`'s `entities` block but not `spawn_eggs` would leave
  the egg unnamed. Inferred from the per-type settings structure; all four
  blocks were enabled in a single commit, so a partial configuration never
  ran.

The entity built here has **no component groups and no events** - it is five
components and nothing else. The state-chart model is the single most repeated
claim about Bedrock entities and is very likely right, but this project has not
exercised it. Verifying it is the main reason to author a real mob next.

## Open questions

- Component-group/event patterns worth templating (tamed/wild, baby/adult).
- How much of this jsonte should generate vs. be written literally.
- Spawn rule tuning - nothing authored yet.
