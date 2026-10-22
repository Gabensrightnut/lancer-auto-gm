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
  `tags` (`difficult`, `dangerous`, `impassable`, `destructible`).
- Units have `cell` (footprint anchor), `level` (base height) and `size`. Size 1/2 and 1 use
  one space; larger sizes use `GridLayout.footprint`.

## Event types (initial list; extend as needed, document here)

| type | fields |
|---|---|
| `turn_ended` | `unit` |
| `moved` | `unit`, `path` (array of `[x, y, level]`), `mode` (`walk`/`boost`/`fly`/`jump`/`involuntary`) |
| `attack_rolled` | `attacker`, `target`, `weapon`, `check` (Dice.check record), `result` (`hit`/`miss`/`crit`) |
| `damage_dealt` | `target`, `amount`, `damage_type`, `roll`, `armor_reduced`, `resisted` |
| `heat_changed` | `unit`, `amount`, `total` |
| `status_added` / `status_removed` | `unit`, `status`, `source` |
| `structure_check` / `stress_check` | `unit`, `roll`, `outcome` |
| `deployed` | `unit`, `object` (deployable, smoke, hard light wall...) |
| `tech_attack` | `attacker`, `target`, `check`, `result`, `effect` |

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
