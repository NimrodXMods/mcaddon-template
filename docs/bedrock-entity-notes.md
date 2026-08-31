# Entity authoring notes

**Planned skill:** `bedrock-entity`
**Status:** notes only - not written yet.

Per the skill policy in `docs/decisions.md`, this becomes
`.claude/skills/bedrock-entity/SKILL.md` only after a real mob - one with behaviors, spawn rules, and loot - has shipped. Until then, add to it as
things break. Failures and non-obvious details are the point; anything that
could be guessed from the schema does not need writing down.

**The content bar is now met** (2026-08-30). `addontemplate:stalker` has a
three-state behaviour machine, spawn rules and a loot table, and all three are
confirmed in game - it wanders, aggros on proximity, flees on damage, spawns
naturally, and drops loot.

**But do not write the skill yet.** The policy has two parts, and the second is
unmet: notes convert once they *stop growing on the next example of the same
thing*. This is one mob. These notes grew substantially while building it -
two `format_version` failure modes, the CADDONREQ loot-table rule, the
`pushable` split - and there is no evidence yet that a second mob would not
grow them again. Build another entity first; if this file barely changes, it
has converged.

## What the skill must cover

Component groups and events as a state chart. Spawn rules. The BP/RP split
for a single entity.

## The general pattern

Read this before the lessons below; everything else assumes it.

```
entity
  components              always active
  component_groups        named sets of components, added/removed at runtime
    component
      trigger(s)          "when <condition> fire <event>"
        -> event
             action(s)    what actually changes: add/remove groups, and more
```

Four levels, and the two easy mistakes are collapsing the middle two:

- A **trigger** is the `{condition..., "event": "...", "target": "self"}`
  object. It *names* an event. It changes nothing itself.
- An **event** is the named entry in the entity's `events` block. Its
  **actions** are what mutate the entity.

Worked example, from `stalker`:

```json
"minecraft:environment_sensor": {                      // component
  "triggers": [{                                       // trigger
    "event": "addontemplate:become_aggro",
    "target": "self",
    "filters": { "test": "distance_to_nearest_player",
                 "operator": "<=", "value": 4 }
  }]
},

"addontemplate:become_aggro": {                        // event
  "remove": { "component_groups": ["calm"] },          // actions
  "add":    { "component_groups": ["aggro"] }
}
```

`target` is worth noting: it is `self` in everything here, but it does not
have to be - an event can be fired on another entity.

**The condition is not spelled the same way everywhere.** `environment_sensor`
uses a `filters` block; `damage_sensor` uses `cause` / `deals_damage` with the
event nested under `on_damage`. Same when/then structure, different shape per
component. Read the schema for the component in hand rather than generalising.

### Event actions

Actions are the verbs an event may perform. Two are structural rather than
effectful, and are the reason an event is not just a flat list:

- **`sequence`** - executes a list of actions in order. Each entry is itself a
  full action set, so it can carry its own `filters`; this is how one event
  branches on conditions.
- **`randomize`** - picks exactly *one* entry from a list to execute, by
  `weight` (default 1.0). Weights are relative: 4.0 against 8.0 gives 33% and
  67%.

The rest, one line each:

| Action | Does |
| --- | --- |
| `add` | Adds component groups to this entity. |
| `remove` | Removes component groups from this entity. |
| `trigger` | Fires another entity event - this is how events chain. |
| `set_property` | Sets an entity property value. |
| `queue_command` | Queues a slash command, or an array of them, to run at end of tick. |
| `play_sound` | Plays a sound as part of the response. |
| `emit_particle` | Emits a particle. |
| `emit_vibration` | Emits a vibration with this entity as the source. |
| `reset_target` | Clears the entity's current target. |
| `drop_item` | Drops an item. |
| `first_valid` | Executes the first entry whose filters pass. |
| `set_home_position` | Sets the entity's home position. |
| `execute_event_on_home_block` | Fires an event on the entity's home block. |
| `stop_movement` | Stops movement; `stop_horizontal_movement` and `stop_vertical_movement` restrict it to one axis. |
| `unleash` | Releases a leash; `unleash_self` and `unleash_others` pick which side. |

**Do not trust the docs page for the key names.** The Event Actions page
(<https://learn.microsoft.com/en-us/minecraft/creator/reference/content/entityreference/examples/eventactions>)
calls them `add_component_group`, `remove_component_group`, `sequence_node`
and `randomize_node`. The actual JSON keys are `add`, `remove`, `sequence`,
`randomize` - which is what `../mcbe-schemas/` defines and what the working
entities in this project use. That page also omits `first_valid`, `drop_item`,
`set_home_position`, `execute_event_on_home_block`, and the `stop_movement` /
`unleash` families entirely, lists `set_property` twice under two names, and
describes `trigger` as firing events "when hit" - which is boilerplate leaked
from a component page, not a property of `trigger`. It is marked
AI-assisted. Table above reconciled against the schema on 2026-08-31.

### Component groups are NOT mutually exclusive

An entity holds a **set** of active component groups. The set may hold several
at once, and may be empty - which it is on spawn, before
`minecraft:entity_spawned` fires, when only base components exist.

Nothing in the engine enforces one-at-a-time. Exclusivity, where this project
has it, is **authored**: every event pairs its `add` with an explicit `remove`.
From `stalker`:

```
minecraft:entity_spawned    -> add:    [calm]
addontemplate:become_aggro  -> remove: [calm]         add: [aggro]
addontemplate:calm_down     -> remove: [aggro]        add: [calm]
addontemplate:flee          -> remove: [calm, aggro]  add: [fleeing]
addontemplate:stop_fleeing  -> remove: [fleeing]      add: [calm]
```

`flee` names both `calm` and `aggro` because it can be reached from either.
The engine will not clear them for it.

**The gotcha: adding a state means editing every other event's `remove` list.**
Miss one and two states' components are live simultaneously - navigation from
one, attack goals from another - which reads as bizarre behaviour rather than
a missing line. Nothing warns you: not the engine, not `mct validate`. Same
silent-failure family as a component group no event ever adds.

A `remove` naming an absent group is a **silent no-op**, so over-removing is
safe and cheap. Prefer listing every sibling state in every transition to
reasoning about which are reachable.

### Built-in events, and components that are only a trigger

Two things break the "component -> trigger -> event" chain, in opposite
directions.

**Built-in events fire with no trigger at all.** The engine calls them from
internal code. The schema defines exactly four:

```
minecraft:entity_born
minecraft:entity_spawned
minecraft:entity_transformed
minecraft:on_prime
```

Every other event in an entity is fired by a trigger someone wrote.
`minecraft:entity_spawned` is confirmed to fire for `/summon` here.

**"Built-in triggers" are really components.** `minecraft:on_death`,
`minecraft:on_hurt`, `minecraft:on_hurt_by_player` and friends live in the
components schema and go in the `components` block like anything else. What
makes them feel different is that the component's *entire body* is a trigger,
not one property among several:

```json
{ "title": "On Death",
  "description": "Adds a trigger to call on this entity's death.",
  "$ref": "../types/trigger.json" }
```

Compare `environment_sensor`, which is a real component with a `triggers`
array among its data. The official docs file these under a separate "Triggers"
category, which is where the impression of a third kind of object comes from.

**Naming will not tell you which is which.** `minecraft:on_prime` is a
built-in *event*; `minecraft:on_death` is a *component*. Same `on_*` prefix,
opposite sides of the model. Check which side of the components/events split
any `minecraft:on_*` name falls on before using it.

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
- `format_version` runs on **independent numbering lines per file type**, and
  one value never works across them. Current values here: BP entity `1.26.40`,
  RP client entity `1.10.0`, spawn rules `1.8.0`, render controllers `1.8.0`.

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

Component groups behave as states and events are the only transitions. A
group that no event adds is dead code, and nothing warns you - not the engine,
not `mct validate`. This was the project's most-repeated inherited claim;
`addontemplate:stalker` confirmed the state-chart behaviour in game on
2026-08-30.

Read "state" here as an authored convention, not an engine rule - the groups
are exclusive because every event explicitly removes its siblings. See
"Component groups are NOT mutually exclusive" above before adding a state.

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
  `within_radius` (12), so `aggro` was genuinely removed. Note what this
  proves: that `become_aggro`'s explicit `remove` executed, **not** that the
  engine enforces exclusivity. It does not.
- Approaching again re-aggroed it. Transitions fire **repeatedly in both
  directions**, not once.

Corollary worth keeping: **`minecraft:entity_spawned` does fire for
`/summon`.** This had been flagged as the most likely failure mode - a
summoned entity plausibly not firing the same event as a naturally spawned one
would have left the mob with no state at all and no sensor to rescue it. It is
not a problem.

### `format_version` has TWO failure modes, and mct catches neither

**Both confirmed in game 2026-08-30.** This is the most important section in
this file. `format_version` does not merely gate features - it selects a
**schema**, and a component can be wrong in either direction:

| Mismatch | Symptom | Loud? |
| --- | --- | --- |
| Component **newer** than the declared version | that component is **silently dropped**; the rest of the entity works | no - nothing, anywhere |
| Component **removed** by the declared version | the **entire entity fails to load** | yes, but only in the in-game Content Log |

`mct validate` reported **0 errors** for both. It passed a file whose entity
could not load at all. Treat that as the hard limit of the gate: it does not
evaluate components against the declared `format_version` in either direction.

**Correction worth recording.** An earlier draft of this file said "a component
*predating* the file's `format_version` is silently ignored". I judged that
garbled and rewrote it to the opposite direction, having confirmed only the
first mode. The second mode then proved the original wording was pointing at
something real - a component older than the declared version *does* break, just
loudly rather than silently. Both directions matter; neither statement alone
was complete.

The evidence is a controlled A/B. Three entities were built from the **same
three jsonte modules** with the same `$scope`, so their `component_groups` and
`events` are byte-identical - verified by diffing the expanded JSON, not by
inspection. The **only** difference is `format_version`:

| Entity | `format_version` | wanders | aggros | flees |
| --- | --- | --- | --- | --- |
| `stalker` | 1.20.80 | yes | **yes** | yes |
| `fmtprobe_ancient` | 1.8.0 | yes | **no** | yes |

(The probe entities were deleted once the result was in - do not go looking for
them. Reproducing the experiment is a copy of `stalker.behavior.templ` with one
field changed.)

So at 1.8.0 everything works *except* `minecraft:environment_sensor`:

- it **wanders** → `minecraft:entity_spawned` fired and applied `calm`
- it **flees when hit** → `minecraft:damage_sensor`, the `flee` event,
  `minecraft:timer` and `minecraft:behavior.panic` all work
- it **wanders again afterwards** → `stop_fleeing` fired and re-applied `calm`
- it **still never aggros** → the sensor inside `calm` is dead

That last row is what makes this conclusive. `calm` was applied **twice**, by
two different mechanisms, and the sensor failed both times - so this is not a
one-off application glitch. The component is being dropped when the file is
parsed. Component groups, events, behaviours and the other sensor are all
unaffected; the drop is **per-component**, not whole-file.

#### Mode two: a removed component kills the whole entity

Bumping this project from 1.20.80 to 1.26.40 broke **both** entities outright:

```
addontemplate:stalker | minecraft:entity |
  -> components -> minecraft:pushable: this component was found in the input,
     but is not present in the Schema
ERROR: Entity 'addontemplate:stalker' failed to load from JSON: parse errors
```

`minecraft:pushable` was **split** somewhere between 1.26.0 and 1.26.40.
Vanilla files at 1.26.0 still carry it; files at 1.26.40 use a presence-based
pair instead - empty objects, no fields:

| 1.20.80 → 1.26.0 | 1.26.40 |
| --- | --- |
| `"minecraft:pushable": {"is_pushable": true, "is_pushable_by_piston": true}` | `"minecraft:pushable_by_entity": {}` + `"minecraft:pushable_by_block": {}` |

(`pushable_by_block` is the piston case.)

This is why **bumping `format_version` is a migration, not a clerical edit.**
The upgrade does not just unlock new components - it can *remove* ones you
depend on, and the failure is total rather than partial. The only reliable way
to find out is the in-game Content Log; nothing in the build pipeline reports
it.

Practical consequences:

- A mob that is "mostly working but one thing does nothing" is a
  `format_version` suspect before it is a logic suspect.
- A mob that **does not appear at all** after a version bump is a removed
  component, not a broken identifier. Read the Content Log.
- The verify gate cannot catch either case. `mct validate` passed clean on a
  file with a dead component *and* on a file that failed to load - a concrete
  limit of the gate worth remembering.
- **After any `format_version` change, check the Content Log before believing
  the change worked.** A clean `verify.sh` proves nothing here.
- `minecraft:environment_sensor` specifically requires something newer than
  1.8.0. The upper bound is not established here - see Awaiting playtest.
- **Each content type has its own numbering line, and "latest" differs per
  line.** Established from `bedrock-samples` and the Creator docs on
  2026-08-30:

  | File | Newest observed | Source |
  | --- | --- | --- |
  | BP entity | **1.26.40** | vanilla entities |
  | BP item | **1.26.30** | vanilla items (`apple.json` et al.) |
  | BP block | **1.21.110** | Creator docs - vanilla ships no BP block JSON |
  | RP client entity | 1.10.0 still dominant (94 files) vs 1.26.0 (7) | vanilla |
  | Spawn rules | **1.8.0** | vanilla - this line has not moved |

  Bumping is therefore never a find-and-replace. The project's files were moved
  to these values on 2026-08-30; the block figure rests on documentation rather
  than a vanilla sample, so it is the least certain of the three.

### Three states, and what the third one proved

`stalker` now runs three states - `calm` ↔ `aggro` on proximity, either →
`fleeing` on damage, `fleeing` → `calm` on a timer - composed from three
modules (`wandering`, `proximity_aggro`, `flee_on_damage`). All confirmed in
game.

- **A second transition source works.** Every earlier transition came from
  `environment_sensor` proximity. `minecraft:damage_sensor` → event is a
  different mechanism and it fires.
- **`minecraft:timer` + `time_down_event` returns state unprompted** - a
  transition with no external trigger at all.
- **Degenerate transitions are safe.** `damage_sensor` lives in *base*
  components, so hitting an already-fleeing mob re-fires `flee`, which removes
  two groups that are absent and adds one already present. This is a **silent
  no-op**, not an error - so the modules need no guards against it. (Whether it
  *restarts* the timer was not measured.)
- **Base components vs groups.** Putting `damage_sensor` in base rather than
  per-state is what makes it fire from any state - and is also why flee
  survives even when the state machine is broken, which is what made the
  `format_version` probe ambiguous until wandering was checked separately.

**The module rule strained here.** `flee_on_damage` must remove `calm` and
`aggro` by name, so it hardcodes groups it does not own - breaking the clean
"a module owns a whole state machine" rule in `AGENTS.md` section 4. Three
states is where that rule stops being sufficient. It is not wrong, but it is
incomplete: a module owns a machine, *or* it declares a dependency on one.

### Spawn rules and loot tables

Both are separate files, not entity components - the entity only *points* at
the loot table.

- Spawn rules live at `packs/BP/spawn_rules/<name>.spawn_rules.json` and use
  `format_version` **1.8.0** - a *third* numbering line, distinct from the BP
  entity (1.20.80) and the RP client entity (1.10.0). Copy the value from a
  vanilla spawn rule, never from your entity.
- `minecraft:loot` takes `{"table": "<path>"}`, relative to the **BP root**,
  and the schema pins it to `^loot_tables/.*.json$` - the `loot_tables/`
  prefix is part of the string, not implied.

**Cooperative Add-On rules apply to `loot_tables/` too**, which is easy to miss
because it is usually described as a texture rule. Copying vanilla's own layout
(`loot_tables/entities/skeleton.json`) **fails the gate**:

```
[CADDONREQ102] Found an cooperative add-on common name folder 'entities' in a
               parent folder pack\loot_tables.
[CADDONREQ104] Found a loose file 'stalker.loot.json' in loot_tables\entities.
```

The working layout is the same shape as textures -
`loot_tables/<creatorshortname>/<mygamename>/<file>.json`, here
`loot_tables/addontemplate/template/stalker.loot.json`.

**That non-vanilla path resolves at runtime** - confirmed in game, a killed
stalker dropped from the table. Worth stating because moving off the layout
every vanilla example uses looks like it should break lookup, and does not.

`spawn_rules/` is **not** subject to this: a flat
`spawn_rules/stalker.spawn_rules.json` passes clean. So the rule is per-folder,
not global - do not assume, check.

**Natural spawning confirmed in game 2026-08-30.** The rule as written -
`population_control: "monster"`, surface + underground, brightness 0-7,
difficulty easy+, `has_biome_tag: monster` wrapped in `all_of`, herd 1-2 -
produces stalkers in a normal world once `domobspawning` is on. Weight was
raised to 100 during diagnosis and has been returned to **40**; spawning was
observed at 100, so 40 is inferred to work rather than measured.

#### Check the world before debugging the file

Natural spawning failed here for a long time, and **the spawn rule was never
the problem**: the test world had `domobspawning = 0`. Nothing in the pack, the
build, or `mct validate` can detect that - it is world state, not content.

`level.dat` is readable from disk and settles it in seconds without guessing.
Bedrock's `level.dat` is NBT with an 8-byte header; a byte-tag gamerule's value
is the byte immediately after its name, so a crude search is enough:

```python
b = open('<world>/level.dat','rb').read()
i = b.find(b'domobspawning'); print(b[i+len(b'domobspawning')])   # 0 = disabled
```

Worlds live under
`.../Minecraft Bedrock/Users/<id>/games/com.mojang/minecraftWorlds/<world>/`,
**not** under `Users/Shared/…` where the development packs go - that
`minecraftWorlds` is empty. `levelname.txt` in each folder gives the display
name. Note `level.dat` is written on save, so it can lag a gamerule changed
mid-session.

Before editing a spawn rule, rule out in this order: `domobspawning`,
difficulty above peaceful, light level ≤ the `brightness_filter` max, distance
**> 24 blocks** from the player, and the vanilla monster cap. Only then suspect
the file.

*Lesson recorded because it was learned the wrong way round:* three changes
were made to the spawn rule - `all_of` wrapping, weight 40 → 100, and adding
`minecraft:despawn` - while chasing what turned out to be a world setting. They
were not the cause, and making them first means it is no longer known whether
the original rule would have worked.

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

- `is_summonable` gates `/summon` and `is_spawnable` gates the spawn egg. Both
  are `true` on both entities here and were never toggled independently, so
  which flag gates what is documentation, not observation.
- Enabling `name_ninja`'s `entities` block but not `spawn_eggs` would leave
  the egg unnamed. Inferred from the per-type settings structure; all four
  blocks were enabled in a single commit, so a partial configuration never
  ran.

## Awaiting playtest

Tracked in `docs/test-backlog.md`, not here - manual tests are batched and run
together. Outstanding for entities: the drifter variant chain, a behaviour
re-check on the stalker after the format_version bump, whether the flee timer
restarts on a repeat hit, and the `environment_sensor` version cutoff.

Move results back into this file when they land.

## Open questions
- Component-group patterns worth templating beyond this one (tamed/wild,
  baby/adult).
