# Renderer data formats

What the 3D view, overlays, roll display and event player expect. All plain Dictionaries
(network-safe). Cells are `[x, y]` or `[x, y, level]`; level is the height of the unit's base.

## Units (`BattleView.add_unit`, `load_view`)

A `Unit.to_dict()` or a `ViewFilter.view_for()` unit entry. Used fields: `id`, `name`, `side`
(`players` = blue, `enemies` = red), `content_id` (frame id), `size`, `cell`, `level`,
`statuses`, `loadout` (`{"mounts": [{"mount", "weapons": [ids], "mod"}], "systems": [...]}`).
Optional (shown as `??` when missing): `hp`, `max_hp`, `overshield`, `heat`, `heat_cap`,
`structure`, `max_structure`. Units with `hidden: true` are skipped.

## Turn overlays (`BattleView.overlays.show_plan(plan)`, `clear()`)

Every key is optional. The renderer draws exactly these values; the rules engine computes them.

```gdscript
{
  "path": [[x, y, level], ...],          # start first, as in a `moved` event
  "path_info": [{}, {"cost": 1, "flags": ["climb"]}, ...],  # parallel to path; index 0 unused
      # flags: provoke, boost, difficult, dangerous, climb, fall  (colors + labels)
  "speed": 4, "boost": 4,                # steps past speed draw yellow (boost), past both grey
  "size": 1,                             # mover's Size, for footprint centering
  "footprint": {"cell": [x, y], "level": l, "size": 2, "ok": true, "reason": "TOO NARROW"},
  "blocked": [[x, y], ...],              # spaces this mech can't stand on (greyed)
  "cover": [{"cell": [x, y], "level": l, "kind": "hard" | "soft"}],  # terrain giving cover
  "cover_from": [{"unit": "id", "kind": "hard" | "soft" | "none"}],  # at the destination
  "sky_layer": {"level": 3, "cells": [[x, y], ...]},                # flying: pick a space in the air
  "los": {"dim_cells": [[x, y], ...], "no_los_units": ["id"]},      # dims cells, darkens units
}
```

## Roll display (`RollDisplay.play_check(check, result, title)`)

`check` is the `Dice.check()` record plus three optional display fields:

```gdscript
{
  "d20": 13, "bonus": 2, "total": 19, "target": 8,
  "accuracy_roll": {"accuracy": 2, "difficulty": 1, "net": 1, "color": "blue",
                    "dice": [4], "kept": 4, "value": 4},
  "sources": [{"label": "Lock On", "type": "accuracy"},            # one entry per point,
              {"label": "Soft cover", "type": "difficulty", "value": 1}],  # or "value": n
  "bonuses": [{"label": "Grit", "value": 2}],   # breakdown of `bonus`; else shown as "Bonus"
  "target_label": "Evasion",                    # "E-Defense", "Save Target"...
}
```

`result`: `hit`, `miss`, `crit` (or `success` / `fail`). Missing source labels fall back to
"Accuracy"/"Difficulty". `play_damage(damage_dealt_event)` shows a damage roll;
`show_card(title, lines, color)` shows structure/stress outcomes. Speed: `Fx.speed`
(1 full, 2.5 quick, 0 instant).

## Events (`EventPlayer.play(events)`)

The ARCHITECTURE.md event types, plus the fields the animations use:

| type | fields used |
|---|---|
| `moved` | `unit`, `path` `[[x, y, level]...]`, `mode` (`walk`, `boost`, `fly`, `jump`, `involuntary`) |
| `attack_rolled` | `attacker`, `target`, `weapon` (id: picks the animation), `check`, `result` |
| `damage_dealt` | `target`, `amount`, `damage_type`, optional `roll` (Dice.roll), `armor_reduced`, `resisted`, **`hp` (HP after, recommended)** |
| `heat_changed` | `unit`, `amount` (negative = vent: steam), `total` |
| `status_added` / `status_removed` | `unit`, `status`, `source` (Lock On gets a reticle) |
| `structure_check` / `stress_check` | `unit`, `roll` (int or Dice.roll), `outcome` (text) |
| `deployed` | `unit`, `object`: `{"kind": "smoke" \| "hard_light_wall" \| other, "id", "name", "cells": [[x, y, l]...], "height"}` |
| `tech_attack` | `attacker`, `target`, `check`, `result`, `effect` (text) |
| **`structure_changed`** (new) | `unit`, `amount`, `total` |
| **`destroyed`** (new) | `unit` (explosion, then a wreck that stays) |
| `turn_ended` | `unit` |
| rules engine events | also handled: `turn_started`, `round_started`, `damage_rolled`, `hp_changed`, `structure_lost`, `stress_lost`, `unit_destroyed`, `skill_check`, `burn_marked`, logs for the rest. Weapons are named by loadout key; the player maps keys to ids from the unit's `loadout.weapons`. |

Weapon animation comes from the weapon's data (`WeaponBuilder.attack_style`): Melee → lunge and
swing, Nexus → drone swarm, Burn + Cone → flamethrower, Launcher → arcing missiles, Explosive →
shell (arcing with a warning ring if it has Blast), Energy → charge + beam, else kinetic tracers.

## Resource HUD (`ResourceHUD.set_data(d)`)

```gdscript
{
  "name": "Everest", "frame": "GMS Everest",
  "hp": [8, 10], "overshield": 0, "heat": [2, 6], "danger_zone": 3,   # [current, total]
  "structure": [4, 4], "stress": [4, 4], "repairs": [3, 5], "burn": 0,
  "core_power": "available" | "used",
  "economy": {"quick": [1, 2], "full": [0, 1], "move": [4, 4], "reaction": [1, 1],
              "overcharge_next": "1d3"},
}
```

Any missing pool shows "??" (enemies the seat hasn't scanned). Hovering an action calls
`set_preview(action.preview)`.

## Action bar (`ActionBar.set_actions(list, pilot_id)`), BG3-style

One bar at the bottom center (height 9% of the screen x `bar_scale`, a settings slider; it
shrinks to fit the width), with tabs by `group`, number-key shortcuts (1-0 in the shown
order), drag-to-swap buttons (order saved per pilot in `user://action_layouts/`), a compact
`ResourceCluster` on its left and an End Turn button on its right. `ActionCatalog.for_unit()`
builds this list from a real Unit with the rules engine (host side).

```gdscript
{
  "id": "w:0:0", "name": "Assault Rifle", "short": "Assault",            # short = button label
  "group": "weapons" | "quick" | "full" | "tech" | "systems" | "reactions" | "core",
  "cost": "quick" | "full" | "free" | "reaction" | "protocol",
  "icon": "kinetic",                       # official icon name (assets/icons/lancer/)
  "stats": "Range 10 {icon:range}   1d6 {icon:kinetic}",   # numbers + icons for the card
  "text": "full rule text", "rule_ref": "Core rules, actions: Skirmish",
  "extras": [{"icon": "heat", "value": "+2"}, {"icon": "generic_item", "value": "1/2"}],
  "enabled": false, "reason": "Loading: reload it before firing again.",
  "lockout": {"kind": "turns", "left": 1, "total": 2}     # clock-hand sweep shrinks per turn
           | {"kind": "recharge", "target": 5, "ready": false}   # d6 "5+", glows when ready
           | {"kind": "loading"}                          # "Reload"
           | {"kind": "uses", "left": 0, "total": 2}      # "Used" / "1/2"
           | {"kind": "status", "status": "Jammed", "turns": 1},
  "warnings": [{"text": "This will overheat you (8/8 {icon:heat} → 10): ...", "level": "danger"}],
  "outcome": {"target": "Goblin", "hit_chance": 0.55, "cover": "soft", "damage": "1–6",
              "damage_type": "Kinetic", "armor": 1},        # shown while a target is hovered
  "preview": {"heat": [1, 3], "quick": 1, ...},            # previewed on the resource bars
}
```

Text fields may contain `{icon:name}` or `{icon:name:RRGGBB}`; `Icons.write()` draws the
official icon inline. `update_actions(list)` updates in place so lockout sweeps animate.
Signals: `action_pressed`, `action_hovered`, `end_turn_pressed`.

## Turn order bar (`TurnOrderBar.set_data(d)`)

```gdscript
{"round": 1, "picking_side": "players", "local_side": "players", "active_name": "Everest",
 "units": [{"id", "name", "side", "acted": bool, "active": bool, "hp": [cur, max] (optional)}]}
```

Portraits: `TurnOrderBar.render_portrait(host, model, height)` renders a MechModel once.
Signal `i_will_go(unit_id)` when a player picks who acts next.

## Skill check popup (`SkillCheckPopup.play(check, hold)`)

The `skill_check` event's `check`: Dice.check plus `label`/`skill`, `bonus_sources`
(`[{label, value}]`), `sources` (`[{label, kind: "accuracy"/"difficulty"}]`).

## Playing a turn (`PlayerTurn`, `DemoBattle`)

`PlayerTurn.begin(unit_id)`: camera to the mech, bar up; board hover -> `RulesQueries.preview_move`
drawn as a move plan; click -> Confirm prompt; actions -> target pick (hover shows
`RulesQueries.attack_preview` hit chance and `RulesQueries.cover` cells) -> Confirm; End Turn
button. Everything is submitted to `RulesEngine`; the events go to `EventPlayer`.

`EventPlayer` options: `camera` (follows each action), `pre_attack_pause` (0.7 s),
`skip_to_my_turn`, `on_banner`, `on_turn_started`, `popup`. Speeds: `EventPlayer.SPEEDS`
(cinematic 0.7, normal 1.0, fast 1.8; debug 4.0 and instant 0 for tests and demos).

## Cameras

`BattleView.set_camera_mode("tactical")` or `set_camera_mode("cockpit", unit_id, target_id)`.
`CockpitHUD` reads `unit_id`, `target_id`, `weapon_name`, `weapon_range`; `hacked_by(name)`
glitches it (wire `EventPlayer.on_local_hacked`, and set `local_units` to the seat's units).
