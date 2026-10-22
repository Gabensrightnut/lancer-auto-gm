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

## Action buttons (`ActionBar.set_actions(list)`, `ActionBar.resources = hud`)

```gdscript
{
  "id": "act_overcharge", "name": "Overcharge",
  "cost": "quick" | "full" | "free" | "reaction" | "protocol" | "move",
  "desc": "short text on the button", "text": "full rule text (hover)", "rule_ref": "Core rules: ...",
  "extras": [{"kind": "heat" | "charges" | "overcharge", "value": "1d3"}],   # badges with numbers
  "enabled": false, "reason": "Already used a Quick action this turn",      # greyed with reason
  "preview": {"heat": [1, 3], "quick": 1, "full": 1, "reaction": 1, "overcharge": 1,
              "core_power": 1, "repairs": 1, "hp": -2, "overshield": 3},    # shown on the HUD bars
}
```

Signals: `action_pressed(action)`, `action_hovered(action)`. Heat previews warn when they
would reach `danger_zone` or exceed the heat cap.

## Cameras

`BattleView.set_camera_mode("tactical")` or `set_camera_mode("cockpit", unit_id, target_id)`.
`CockpitHUD` reads `unit_id`, `target_id`, `weapon_name`, `weapon_range`; `hacked_by(name)`
glitches it (wire `EventPlayer.on_local_hacked`, and set `local_units` to the seat's units).
