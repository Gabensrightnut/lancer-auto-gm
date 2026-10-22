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

## Roll results (`RollPopups`): numbers, no dice

Rolls are instant; results pop up as numbers over the unit (DESIGN "Roll visuals"):
`show_check(world, check, result)` -> "20 HIT" tinted blue/red by leftover Accuracy/
Difficulty; `show_damage(world, amount, damage_type, breakdown)` -> "7 [icon]";
`show_text(...)` for structure/stress/heat. Hovering a pop-up shows the breakdown
(`RollDisplay.formula_bbcode(check, result)` / `RollDisplay.damage_bbcode(damage_event)`),
which also goes to the combat log. `check` is the `Dice.check` record plus optional
`sources` ([{label, kind/type, value}]), `bonus_sources`/`bonuses` ([{label, value}]),
`target_label`. Fx.speed only changes how long pop-ups linger.

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

## Skill checks and saves

`skill_check` events pop up over the roller like any other roll ("16 SUCCESS").

## Playing a turn (`PlayerTurn`, `DemoBattle`)

`PlayerTurn.begin(unit_id)`: camera to the mech, bar up; board hover -> `RulesQueries.preview_move`
drawn as a move plan; click -> Confirm prompt; actions -> target pick (hover shows
`RulesQueries.attack_preview` hit chance and `RulesQueries.cover` cells) -> Confirm; End Turn
button. Everything is submitted to `RulesEngine`; the events go to `EventPlayer`.

`EventPlayer` options: `camera` (follows each action), `pre_attack_pause` (0.7 s),
`skip_to_my_turn`, `on_banner`, `on_turn_started`, `popup`. Speeds: `EventPlayer.SPEEDS`
(cinematic 0.7, normal 1.0, fast 1.8; debug 4.0 and instant 0 for tests and demos).

## Floating labels (`BattleView.labels: LabelDeclutter`)

Nameplates (name, HP/heat/structure, status tags) are a fixed size on screen (1080p pixels,
scaled with the window). Each frame they are laid out in screen space:
- `labels.active_unit` (set on `turn_started` and by `PlayerTurn.begin`) and `labels.hover_unit`
  (the hovered target) are placed first; other units' plates keep off the active mech.
- A plate that overlaps another plate or a planning label steps up (at most 70 px, then it
  fades). Plates at the window edges slide back on screen.
- Plates under HUD panels vanish: any visible Control in group `LabelDeclutter.GROUP_KEEPOUT`
  (turn-order bar and banner, hint, action bar, hover card, prompts, combat log).
- Plates next to the cursor dim, except the hovered unit (your own unit's plate dims less).
- Overlay labels made with `screen_px` (move cost, terrain flags, cover, NO LOS) are also fixed
  size and in group `GROUP_PRIORITY`: plates make room for them, and they step past each other.

## Mech paint and the customizer preview (`MechPaint`, `MechPreview`)

Paint is cosmetic and stored with the mech, e.g. `mech["paint"]` (every key optional; missing
means the frame's factory look):

    {"primary": "#rrggbb", "secondary": "#rrggbb", "glow": "#rrggbb", "markings": "#rrggbb",
     "decals": {"chest": "chevron", "shoulder_l": "roundel", "shoulder_r": "number:07",
                "leg_l": "stripes", "leg_r": ""}}

Decal ids: chevron, stripes, roundel, star, hazard, bars, diamond, number:NN. Primary and
secondary are the model's two biggest painted color groups (imported frames name them); dark
trim and bare metal keep their color. `MechPaint.apply(model, paint)` repaints a built model
(inside the tree, for decals); `MechView` applies `unit["paint"]` when present.

Builder hookup (the builder's `preview_area`):

    var pv := MechPreview.new()          # turntable + paint controls; show_paint_controls = false for the turntable only
    preview_area.add_child(pv)
    pv.set_mech(model.db, m["frame"], m.get("loadout", {}), m.get("paint", {}))   # again on frame/loadout change
    pv.paint_changed.connect(func(p: Dictionary) -> void: m["paint"] = p)

Presets: `data/game/paint_presets.json` plus the player's saved ones in
`user://paint_presets.json`. Screenshot scene: `scenes/customizer.tscn` (tags paint_factory,
paint_preset, paint_random, paint_everest).

## Pilot looks (`PortraitArt`, `PilotCreator`, `PilotToken`)

All three read the story session's v2 portrait (`PortraitSpec`, `data/game/story/portraits.json`):
`{version: 2, parts: {part id: {option, primary, secondary}}}`, stored in `pilot["portrait"]`.

- `PortraitArt` (Control): the illustrated bust, drawn in code from the parts. It is a drop-in
  for the placeholder `Portrait`, with the same `set_look(look, expr)` and `lit`. It draws all
  10 expressions in portraits.json (neutral, smiling, angry, worried, shouting, sad,
  surprised, determined, smug, hurt) and also reads older flat looks. `card = false` skips
  the background.
- `PilotCreator` (PanelContainer, full screen): `open(portrait)`, then the
  `confirmed(portrait)` or `cancelled` signal. It has the parts list with lock pins, an
  option grid with live thumbnails, primary and secondary colors from the part's palette,
  saved color pairs, the expression strip, a Token tab, Randomize all (keeps locked parts),
  save and load looks, Reset, Cancel and Confirm. Saved files: `user://pilot_looks.json` and
  `user://portrait_colors.json`.
- `PilotToken` (Node3D): `PilotToken.new().build(portrait)` builds the on-foot figure, about
  1.8 m tall and facing -Z.

Screenshot scene: `scenes/customizer.tscn`, tags creator_portrait, creator_token,
creator_beard, portraits, expressions.

## Abilities, picks and zones

- **Catalog:** `ActionCatalog.for_unit` adds everything in `RulesQueries.available_actions`
  that it doesn't build itself: the remaining basic actions, system, talent and trait
  abilities, trait reactions and the core power.
  - Situational basics (Eject, Mount, Self-Destruct...) go on the **More** tab, which All
    leaves out.
  - Entries whose `automation` is manual or partial get `table` ("manual"/"partial") and
    `table_note`. The button shows a TABLE badge and the hover card shows the note.
- **Picks:** `ActionInputs.steps(state, engine, unit, action)` is the list of things to pick
  before submitting. Each step is `{param, pick: unit|cell, count, optional, label, area,
  weapon, who, pairs}`.
  - Weapons: aim, aims, targets, fold_to.
  - Abilities: to (deploy), target, toward, aim, spaces.
  - Core power: target, aim (mag field), sections (pairs), drones.
  - Anything else is probed with validate.
  - `PlayerTurn` runs the steps on the board (mode "pick"): hover previews the area, picked
    spaces are marked, the last pick is checked with validate (the reason shows in the hint),
    Space finishes "up to" or optional steps, and a confirm prompt follows.
  - TODO(rules): a `RulesQueries.action_inputs` query would replace the guessing.
- **Zones:** `BattleView.zones: ZoneLayer` draws `state.zones` (smoke, sealant, caltrops,
  bunker, javelin, cloak, mag_field, smoke_cloud, hologram, enclave and others), from
  `zone_created`/`zone_removed` events or `set_zones(list)`.
- **Table notes:** `manual_effect` events log their `guidance` and pop up a `TableNotice`
  ("For the table").

## Cameras

`BattleView.set_camera_mode("tactical")` or `set_camera_mode("cockpit", unit_id, target_id)`.
`CockpitHUD` reads `unit_id`, `target_id`, `weapon_name`, `weapon_range`; `hacked_by(name)`
glitches it (wire `EventPlayer.on_local_hacked`, and set `local_units` to the seat's units).
