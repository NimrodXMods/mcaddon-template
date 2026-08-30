# Entity authoring notes

**Planned skill:** `bedrock-entity`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-entity/SKILL.md` only after a real mob - one with behaviors, spawn rules, and loot - has shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

`addontemplate:stalker` now has behaviours and a **playtest-confirmed** state
machine (2026-08-30). It has **no spawn rules and no loot**, so the bar above
is still not met - but the central claim this file existed to test is settled.

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
  `.lang` lines. Re-confirmed for `stalker`: both keys appeared with no
  hand-written `.lang` at all.
- `format_version` on the BP entity (1.20.80 here) and the RP client entity
  (1.10.0) are **different numbering lines**. One value does not work for both
  files.

### A mob needs more than the minimal entity carries

`example_entity` is a *stub*, not a starting point for anything that moves.
Going from it to a walking, attacking mob required adding, none of which it
has: `minecraft:movement.basic`, `minecraft:navigation.walk`,
`minecraft:jump.static`, `minecraft:attack`, `minecraft:behavior.float`, and a
`minecraft:movement` value (which lives per-state, see below).

`example_entity` also declares `type_family: ["addontemplate", "inanimate"]`.
Copying that onto a mob is wrong - vanilla filters key off family, and a thing
that walks and attacks is not inanimate. `stalker` uses
`["addontemplate", "stalker", "monster", "mob"]`.

### Schema locations are not where you would guess

In `../mcbe-schemas/source/behavior/entities/format/`, plain components live
in `components/` but AI goals live in a sibling `behaviors/` directory -
`behaviors/melee_attack.json`, not `components/minecraft:behavior.melee_attack.json`.
Grepping `components/` for a `behavior.*` goal finds nothing and looks like the
component does not exist.

### Entities are state charts - confirmed in game

Component groups are **mutually exclusive states**; events are the only
transitions. A group that no event adds is dead code, and nothing warns you -
not the engine, not `mct validate`. This was the project's most-repeated
inherited claim; `addontemplate:stalker` confirmed it in game on 2026-08-30.

The decisive observation was summoning the mob **directly on top of the
player**, which made it attack instantly. That is provable by elimination:
`melee_attack` and `nearest_attackable_target` exist *only* inside the `aggro`
group, so an attack requires the whole chain to have executed -

```
/summon -> minecraft:entity_spawned fired -> added `calm`
        -> calm's environment_sensor existed and evaluated
        -> distance 0 <= aggro_range -> fired addontemplate:become_aggro
        -> removed `calm`, added `aggro` -> melee_attack existed -> hit player
```

Two further results from the same session:

- After the player died and respawned at range, the mob **went back to
  ignoring them**. A mob still holding `aggro` would have targeted from up to
  `within_radius` (12), so `aggro` was genuinely removed - groups are
  exclusive, not additive.
- Approaching again re-aggroed it. Transitions fire **repeatedly in both
  directions**, not once.

Corollary worth keeping: **`minecraft:entity_spawned` does fire for
`/summon`.** This had been flagged as the most likely failure mode - a
summoned entity plausibly not firing the same event as a naturally spawned one
would have left the mob with no state at all and no sensor to rescue it. It is
not a problem.

### Driving state transitions from data

`minecraft:environment_sensor` takes a `triggers` list of
`{event, target, filters}`, and `distance_to_nearest_player` takes
`{test, operator, value}` (both verified against the schemas). Together they
flip component groups on proximity with no scripting involved.

The pattern used by `stalker`: **each state carries its own sensor**, so the
"player got close" watcher only exists while calm and the "player got away"
watcher only exists while aggro. Ranges are asymmetric (4 in, 12 out) to give
hysteresis - equal thresholds would oscillate at the boundary.

## Inherited from research - NOT verified here

Carried over from the original AGENTS.md research pass. Plausible, widely
repeated, and untested by this project. Do not promote to a skill on this
basis - confirm it first, then move it up.

- A component predating the file's `format_version` is silently ignored. That
  is the quiet failure behind "I added the component and nothing happened".
- `is_summonable` gates `/summon` and `is_spawnable` gates the spawn egg. Both
  are `true` on both entities here and were never toggled independently, so
  which flag gates what is documentation, not observation.
- Enabling `name_ninja`'s `entities` block but not `spawn_eggs` would leave
  the egg unnamed. Inferred from the per-type settings structure; all four
  blocks were enabled in a single commit, so a partial configuration never
  ran.

## Open questions

- Spawn rules - still nothing authored, for either entity.
- Loot tables - same.
- **The exact transition distances are unmeasured.** The playtest confirmed the
  cycle behaviourally, not numerically - "close enough" was not measured
  against the configured 4-in / 12-out. To pin them down, stand at a known
  distance and step in one block at a time; `/tp` to fixed coordinates beats
  walking. Worth doing before treating the hysteresis gap as tuned rather than
  merely working.
- Component-group patterns worth templating beyond this one (tamed/wild,
  baby/adult).
