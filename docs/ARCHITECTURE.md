# Architecture

Godot 4.7, typed GDScript. The full feature design is in [DESIGN.md](../DESIGN.md); this file
says how the code is split and the contracts between the parts.

## Layout

```
data/lancer-data/   Official Massif data (GPL-3.0). Never edited.
data/game/          Our own data: GM tables, behaviors, presets, map kits.
src/core/           Pure game logic. No rendering, no networking, no Node classes.
  grid/             GridLayout (HexGrid, SquareGrid), BattleMap (stacked terrain).
  rules/            RulesEngine, ActionHandler subclasses, RuleResult.
  dice.gd           Seeded Dice. Every roll in a game goes through state.dice.
  unit.gd           Unit: plain data for a mech / pilot / NPC / deployable.
  game_state.gd     GameState: the authoritative battle state (host only).
  view_filter.gd    ViewFilter: what one seat may know.
src/content/        ContentDB: read-only access to lancer-data.
src/render/         3D scene, models, animations, overlays, cameras. Reads views + events.
src/net/            Peer-to-peer sessions, sending views and actions.
src/gm/             Procedural GM: mission/encounter generation, enemy tactics, events.
src/ui/             HUD, menus, roll display, tutorials.
launcher/           Separate Godot project for the auto-updating launcher.
tests/              Headless tests. tests/unit/*.gd, every test_* method runs.
tools/              Dev tools (screenshot capture).
```

## The one rule: everything goes through the rules engine

```
player input / GM AI / network client
        │  action  {"type": "move", "actor": "unit_id", "params": {...}}
        ▼
RulesEngine.submit(state, action)  ──►  RuleResult (ok / reason + rule_ref / grey area)
        │  events  [{"type": "moved", ...}, {"type": "attack_rolled", ...}]
        ▼
ViewFilter.view_for(state, seat) + per-seat event filtering  (host)
        │
        ▼
renderer + UI on each client (animate events, show the view)
```

- **Actions** are plain Dictionaries so they can travel over the network. `type` names an
  `ActionHandler`; `actor` is a unit id; `params` is action-specific.
- **Handlers** (`src/core/rules/`) implement `validate()` (no side effects) and `resolve()`
  (changes state, returns events). Each rule check cites its source in `rule_ref`.
- **Events** are plain Dictionaries with a `type`. They are the only thing the renderer
  animates. Rolls in events carry the full `Dice.check()` / `Dice.accuracy_roll()` record so
  the UI can show base roll, blue Accuracy / red Difficulty dice, and bonuses.
- **Grey areas:** `RuleResult.ruling_needed(id, ...)` stops the action until the table picks
  an option and it's stored in `state.rulings[id]`; later the same ruling applies automatically.
- **Randomness:** only `state.dice`, only on the host. The seed + action log replays a game.
- **Views:** the host never sends `GameState` itself. Each seat gets `ViewFilter.view_for()`.
  Secrets (Hidden positions, unscanned stats, GM-only map features, dice state) never leave
  the host.

## Grid contract

- Ground-plane cells are `Vector2i`. Height is an int `level`; 1 level = 1 space.
- Only `src/core/grid/` knows hex vs square. Everything else uses `GridLayout`:
  `neighbors`, `distance`, `line`, `cells_within`, `footprint`, `footprint_distance`,
  `to_world`, `from_world`.
- `BattleMap` columns: `ground` (solid levels), optional `gap` (overhang/bridge space),
  `tags` (`difficult`, `dangerous`, `impassable`, `destructible`, `soft_cover`). Look-only
  tags (`rock`, `woods`, `building`, `wall`, `water`, `ice`, `lava`, `toxic`, `crystal`,
  `rubble`, `chasm`) pick how a column is drawn and never change rules; see
  `src/render/world/README.md`.
- Units have `cell` (footprint anchor), `level` (base height) and `size`. Size 1/2 and 1 use
  one space; larger sizes use `GridLayout.footprint`.

## Event types

Emitted by the rules engine (`src/core/rules/`), in the order things happen. Every event that
applies a rule carries `rule_ref`. Rolls carry the full `Dice.check()` record plus
`bonus_sources` ([{label, value}], also as `bonuses`) and `target_label` ("Evasion",
"E-Defense", "Save Target", "Check (10+)"); each Accuracy/Difficulty source in
`check.sources` is `{label, kind (also as type): "accuracy"/"difficulty", value, rule_ref}`.
Clients get events through `ViewFilter.events_for(state, seat, events)`.
Read-only previews for overlays are in `RulesQueries` (movement arrow, reachable spaces,
cover, line of sight, attack/area/tech previews with hit chance).

| type | fields |
|---|---|
| `combat_started` | `first_side` |
| `round_started` | `round`, `side` (side that picks first) |
| `next_side` | `side` (side that picks the next unit to act) |
| `turn_started` / `turn_ended` | `unit` (+ `round` on start) |
| `moved` | `unit`, `path` (array of `[x, y, level]`), `mode` (`walk`/`boost`/`fly`/`fall`/`involuntary`/`jump`/`dragged`), `cost`, `stopped_by` |
| `movement_stopped` | `unit`, `by` (hostile that Engaged it), `reason` |
| `disengaged` | `unit` |
| `attack_rolled` | `attacker`, `target`, `weapon` (loadout key), `weapon_name`, `kind` (`melee`/`ranged`), `check`, `result` (`hit`/`miss`/`crit`), `cover` (`none`/`soft`/`hard`), `cover_cells`, `invisible_miss`, `lock_on_consumed` |
| `attack_skipped` | `attacker`, `weapon`, `target`, `reason` (an earlier attack in the same action made it impossible) |
| `invisible_roll` | `attacker`, `target`, `roll` (d2), `missed` |
| `damage_rolled` | `attacker`, `target`, `damage_type`, `crit`, `roll` (`expr`, `dice`, `kept`, `bonus`, `total`, `overkill_heat`) |
| `reliable_damage` | `attacker`, `target`, `amount` |
| `damage_dealt` | `target`, `source`, `amount` (taken), `damage_type`, `roll` (before reductions), `exposed`, `armor_reduced`, `resisted`, `hp` and `overshield` (after), `immune` |
| `hp_changed` | `unit`, `hp`, `overshield`, `source` |
| `burn_marked` / `burn_cleared` | `unit`, `amount`, `total` |
| `heat_changed` | `unit`, `amount`, `total`, `source` |
| `structure_lost` / `stress_lost` | `unit`, `structure` / `stress` (left) |
| `structure_check` / `stress_check` | `unit`, `roll` (`dice`, `lowest`, `ones`), `outcome` (table result title) |
| `system_trauma` | `unit`, `roll`, `destroys` (`mount`/`system`/``) |
| `equipment_destroyed` | `unit`, `weapon` or `system`, `name` |
| `skill_check` | `unit`, `check` (Dice.check + `skill`, `label`, `auto_fail`) |
| `meltdown_started` / `reactor_meltdown` | `unit`, `turns` |
| `unit_destroyed` | `unit`, `reason` |
| `falling` | `unit`, `reason` (falls at the end of the turn, then a `moved` with mode `fall`) |
| `status_added` / `status_removed` | `unit`, `status`, `source` |
| `knockback_blocked` | `unit` |
| `reaction` | `unit`, `reaction` (`brace`), `trigger` (attacker) |
| `reaction_policy` | `unit`, `reaction`, `policy` |
| `overcharged` | `unit`, `roll`, `count` |
| `stabilized` / `reloaded` | `unit`, `choices` |
| `searched` | `unit`, `target`, `found`, `check`, `contest` |
| `scanned` | `unit`, `target`, `side` |
| `tech_attack` | `attacker`, `target`, `check`, `result` (`hit`/`miss`), `effect`, `invisible_miss`, `lock_on_consumed` |
| `tech_action` | `unit`, `target`, `action` (`lock_on`, `invade` on an ally) |
| `reaction_offered` | `id`, `unit` (who decides), `reaction` (`brace`/`overwatch`/`prepared`), `context`, `trigger_action`. The engine is paused: answer with `{"type": "react", "actor": unit, "params": {"take": bool, ...}}` (Overwatch: `weapon`) |
| `movement_cancelled` | `unit`, `reason` (a reaction made the move impossible) |
| `area_attack` | `attacker`, `weapon`, `weapon_name`, `pattern`, `size`, `cells` [[x, y]], `origin` [x, y, level], `targets` |
| `ram` / `grapple` results | `attack_rolled` + `status_added` (Prone/Immobilized); `grappled` {`unit`, `target`}; `grapple_ended` {`unit`, `other`, `reason`}; `contested_check` {`unit`, `against`, `check`, `contest`, `success`} |
| `prepared` / `prepared_triggered` / `prepared_lost` | `unit`, `action`, `trigger`, `text` / `ok`, `reason` |
| `ejected` | `unit` (mech), `pilot` |
| `pilot_left_mech` / `pilot_mounted` | `unit` (pilot), `mech`, `cell` |
| `self_destruct_started` | `unit`, `turns` |
| `reactor_explosion` | `unit`, `reason`, `roll`, `targets` |
| `core_power` | `unit`, `core`, `power`, `text`, `automated` |
| `effect_triggered` | `unit`, `effect` (trait name), `target` |
| `status_blocked` / `no_effect` / `knockback_blocked` | `unit`/`target`, `reason` (immunity, Heavy Frame, Archaic...) |
| `tech_action` / `action_skipped` | `unit`, `target`, `action` (`lock_on`, `bolster`, `invade` on an ally) / `reason` |
| `deployed` | `unit` (owner), `object` {`id`, `kind` (drone/deployable/mine...), `name`, `cells` [[x, y, level]], `height`, `hp`} |
| `recalled` | `unit` (owner), `object` (id) |
| `mine_triggered` | `mine`, `unit` (who set it off), `text` |
| `activated` | `unit`, `ability`, `name`, `source`, `activation`, `automated`, `detail` |
| `manual_effect` | `unit`, `source`, `text`: not automated, the table applies it |
| `recharge_roll` | `unit`, `roll`, `ready` (sources ready again) |
| `effect_ended` | `unit`, `effect` (a timed effect ran out) |
| `revived` | `unit`, `by` |
| `ruling_needed` | `id`, `question`, `options` {id: text}, `rule_ref`, `trigger_action`: the engine is paused; the host answers `{"type": "set_ruling", "params": {"id", "choice"}}` |
| `ruling_made` | `id`, `choice`, `text` |

## Commands

```bash
# Import (first run, or after adding classes)
godot --headless --path . --import
# Tests
godot --headless --path . -s res://tests/run_tests.gd
# Screenshot of a scene
godot --path . -s res://tools/screenshot.gd -- res://scenes/main.tscn out.png
```

## Rules not yet confirmed

See [RULES_TODO.md](RULES_TODO.md). Code that depends on an unconfirmed rule is marked
`PROVISIONAL` with a pointer there.
