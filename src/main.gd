extends Node3D
## Demo. By default a playable battle on the real rules engine (DemoBattle): pick who goes
## with "I'll go", plan and confirm your actions, End Turn, watch the enemy turn.
## N starts a new battle. Space plays the scripted effects showcase (hand-written events in
## the rules engine's format). G hex/square, B biome, C camera, V speed, K skip to my turn,
## F1-F3 overlay examples.

var content: ContentDB
var view: BattleView
var player: EventPlayer
var rolls: RollPopups
var combat_log: CombatLog
var hud: CockpitHUD
var resources: ResourceCluster
var action_bar: ActionBar
var battle: DemoBattle
var shape := GridLayout.Shape.HEX
## "urban_ruins" or "grassy_hills" (B switches).
var biome := "urban_ruins"
var _ui: CanvasLayer
var _help: Label
var _speed_i := 1
const SPEED_NAMES := ["cinematic", "normal", "fast", "debug"]
var _running := false

## Demo roster: id -> [frame id, side, world x, world z, level offset, name, loadout].
const ROSTER := {
	"everest": ["mf_standard_pattern_i_everest", "players", 6.0, 9.2, 0, "Everest", [["Main", ["mw_assault_rifle"]], ["Flex", ["mw_tactical_knife"]], ["Heavy", ["mw_howitzer"]]]],
	"blackbeard": ["mf_blackbeard", "players", 9.5, 7.0, 0, "Blackbeard", [["Flex", ["mw_chain_axe"]], ["Main", ["mw_hand_cannon"]], ["Heavy", []]]],
	"minotaur": ["mf_minotaur", "players", 3.3, 10.6, 0, "Minotaur", [["Main/Aux", ["mw_nexus_hunter_killer", "mw_pistol"]]]],
	"swallowtail": ["mf_swallowtail", "players", 11.6, 11.2, 3, "Swallowtail", [["Flex", ["mw_vulture_dmr"]], ["Aux/Aux", ["mw_fold_knife"]]]],
	"drake": ["mf_drake", "players", 1.2, 7.4, 0, "Drake", [["Main", ["mw_assault_cannon"]], ["Main", []], ["Heavy", ["mw_daisy_cutter"]]]],
	"goblin": ["mf_goblin", "enemies", 8.0, 4.8, 0, "Goblin", [["Flex", ["mw_autopod"]]]],
	"sherman": ["mf_sherman", "enemies", 12.6, 3.4, 0, "Sherman", [["Flex", ["mw_stub_cannon"]], ["Main", ["mw_sol_pattern_laser_rifle"]], ["Heavy", ["mw_andromeda_pattern_heavy_laser_rifle"]]]],
	"tokugawa": ["mf_tokugawa", "enemies", 11.2, 4.4, 0, "Tokugawa", [["Flex", ["mw_torch"]], ["Main", ["mw_annihilator"]]]],
	"barbarossa": ["mf_barbarossa", "enemies", 2.6, 4.6, 0, "Barbarossa", [["Main", ["mw_shatterhead_colony_missiles"]], ["Heavy", ["mw_siege_cannon"]]]],
}


func _ready() -> void:
	content = ContentDB.new()
	content.load_all()
	view = BattleView.new()
	view.content = content
	add_child(view)
	_build_ui()
	player = EventPlayer.new(view, rolls, combat_log)
	player.local_units = ["everest"]
	player.on_local_hacked = hud.hacked_by
	add_child(player)
	_build_board()
	if OS.get_cmdline_user_args().is_empty():
		start_battle.call_deferred()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	hud = CockpitHUD.new()
	hud.visible = false
	_ui.add_child(hud)
	rolls = RollPopups.new()
	_ui.add_child(rolls)
	combat_log = CombatLog.new()
	combat_log.position = Vector2(1600 - 496, 70)
	_ui.add_child(combat_log)
	action_bar = ActionBar.new()
	_ui.add_child(action_bar)
	resources = action_bar.resources
	_help = Label.new()
	_help.position = Vector2(12, 8)
	_help.add_theme_font_size_override("font_size", 13)
	_help.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.85))
	_help.add_theme_constant_override("outline_size", 4)
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ui.add_child(_help)
	_update_help()


var _help_open := false


func _update_help() -> void:
	if not _help_open:
		_help.text = "H: controls"
		return
	var lines: Array = []
	for kv: Array in BattleKeys.listing():
		lines.append("%s: %s" % [kv[1], kv[0]])
	_help.text = "Mouse: click/drag to move, right click for options, middle-drag orbit (Shift: pan), wheel zoom, screen edges pan.  1-0: action bar\n" + \
		"   ".join(lines) + "\nDemo: N new battle   F5 effects showcase   F6 speed: %s   F7 biome: %s   F8 grid: %s   F9 grid lines   K skip to my turn" % [
		String(SPEED_NAMES[_speed_i]).to_upper(), biome.replace("_", " ").to_upper(), "HEX" if shape == GridLayout.Shape.HEX else "SQUARE"]
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size.x = 1100


## Battle loadouts that differ from the showcase. Avoids weapons whose lancer-data damage is
## a number (rules engine bug, reported: Attacks._hit does String(val)).
const BATTLE_LOADOUTS := {
	"goblin": [["Flex", ["mw_nexus_light"]]],
	"sherman": [["Flex", ["mw_pistol"]], ["Main", ["mw_thermal_rifle"]], ["Heavy", ["mw_heavy_machine_gun"]]],
	"tokugawa": [["Flex", ["mw_charged_blade"]], ["Main", ["mw_annihilator"]], ["Main", []]],
	"barbarossa": [["Main", ["mw_shatterhead_colony_missiles"]], ["Main", ["mw_assault_rifle"]], ["Heavy", ["mw_howitzer"]]],
}


## Where the demo roster stands on each biome's board (added to ROSTER positions).
const BIOME_OFFSET := {"urban_ruins": Vector2.ZERO, "grassy_hills": Vector2(6.0, 6.5), "alien_wilds": Vector2(4.0, 7.0)}
const BIOMES := ["urban_ruins", "grassy_hills", "alien_wilds"]
## Screenshot-only: battle board from the world styles (see start_battle).
var world_spec := ""
## Screenshot-only: systems for roster units ({id: [system ids]}).
var battle_systems: Dictionary = {}
## Screenshot-only: the generated mission of a world=gen... board (objectives on the board).
var world_mission: Mission
var battle_offset := Vector2.ZERO


## [BattleMap, kit] for a world_preview-style spec.
func _world_map(spec_text: String) -> Array:
	var spec := spec_text.replace("=", ":").split(":")
	var name := spec[0]
	var map: BattleMap
	var kit := "urban_ruins"
	if name.begins_with("gen"):
		var parts := name.trim_prefix("gen").split("+")
		var opts := {"db": content, "shape": "hex"}
		if parts.size() > 1:
			opts["landscape"] = parts[1]
		if parts.size() > 2:
			opts["culture"] = parts[2]
		var g := MissionGenerator.generate(int(parts[0]), opts)
		map = (g["state"] as GameState).map
		kit = (g["mission"] as Mission).flavor.get("kit", "grassy_hills")
		world_mission = g["mission"]
	else:
		match name:
			"hills":
				map = DemoMap.build_hills(shape)
				kit = "grassy_hills"
			"alien":
				map = DemoMap.build_alien(shape)
				kit = "alien_wilds"
			_:
				map = DemoMap.build(shape)
	if spec.size() > 1:
		kit = spec[1].replace("-", "/")
	return [map, kit]


func _build_board() -> void:
	var map: BattleMap
	match biome:
		"grassy_hills":
			map = DemoMap.build_hills(shape)
		"alien_wilds":
			map = DemoMap.build_alien(shape)
		_:
			map = DemoMap.build(shape)
	view.set_map(map, biome)
	var off: Vector2 = BIOME_OFFSET[biome]
	view.clear_units()
	for id: String in ROSTER:
		var r: Array = ROSTER[id]
		var frame := content.frame(r[0])
		var cell := DemoMap.cell_at(map, r[2] + off.x, r[3] + off.y)
		var mounts: Array = []
		for m: Array in r[6]:
			mounts.append({"mount": m[0], "weapons": m[1], "mod": ""})
		var stats: Dictionary = frame.get("stats", {})
		var u := {
			"id": id, "name": r[5], "side": r[1], "content_id": r[0], "size": float(stats.get("size", 1)),
			"cell": [cell.x, cell.y], "level": map.ground_height(cell) + int(r[4]), "flying": int(r[4]) > 0,
			"loadout": {"mounts": mounts, "systems": []}, "statuses": {},
		}
		if r[1] == "players" or id == "goblin":
			u.merge({"hp": int(stats.get("hp", 10)), "max_hp": int(stats.get("hp", 10)), "heat": 0,
				"heat_cap": int(stats.get("heatcap", 6)), "structure": 4, "max_structure": 4})
		view.add_unit(u)
	# Face everyone toward the other side.
	for mv: MechView in view.units.values():
		mv.face(Vector3(8 + off.x, 0, 6 + off.y) if mv.unit["side"] == "players" else Vector3(8 + off.x, 0, 11 + off.y))
	view.tactical.look_at_point(Vector3(7.5 + off.x, 0.8, 7.0 + off.y), 15.0)
	view.tactical.snap()
	_update_help()
	resources.set_data(sample_resources())
	action_bar.set_actions(sample_actions(), "demo_everest")
	action_bar.visible = false
	hud.battle = view
	hud.unit_id = "everest"
	hud.target_id = "goblin"
	hud.weapon_name = "Assault Rifle"
	hud.weapon_range = "RANGE 10   ·   1d6 KINETIC"


func _unhandled_input(event: InputEvent) -> void:
	# Demo-only keys live on F5-F9 so the battle controls (BattleKeys) keep the main keys.
	var fk := (event as InputEventKey).keycode if event is InputEventKey and event.pressed and not event.echo else KEY_NONE
	if fk == KEY_F5 and not _running:
		_stop_battle()
		_build_board()
		combat_log.clear_log()
		_run_demo()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_N and not _running:
		start_battle()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_H:
		_help_open = not _help_open
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_K:
		player.skip_to_my_turn = true
	elif fk == KEY_F8 and not _running:
		shape = GridLayout.Shape.SQUARE if shape == GridLayout.Shape.HEX else GridLayout.Shape.HEX
		_build_board()
	elif fk == KEY_F7 and not _running:
		biome = BIOMES[(BIOMES.find(biome) + 1) % BIOMES.size()]
		_build_board()
	elif fk == KEY_F9:
		view.terrain.set_grid_visible(not view.terrain.grid_lines.visible)
	elif event.is_action_pressed("first_person") and (battle == null or not battle.turn.active):
		_toggle_camera()
	elif fk == KEY_F6:
		_speed_i = (_speed_i + 1) % SPEED_NAMES.size()
		Fx.speed = EventPlayer.SPEEDS[SPEED_NAMES[_speed_i]]
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F1:
				view.overlays.show_plan(move_plan())
			KEY_F2:
				view.overlays.show_plan(sky_plan(3))
			KEY_F3:
				view.overlays.show_plan(los_plan())
			KEY_F4:
				view.overlays.clear()
	_update_help()


func _toggle_camera() -> void:
	var cockpit := view.camera_mode == "tactical"
	if cockpit:
		view.set_camera_mode("cockpit", "everest", "goblin")
	else:
		view.set_camera_mode("tactical")
	hud.visible = cockpit


# --- playable battle ----------------------------------------------------------------------

func _stop_battle() -> void:
	if battle:
		battle.queue_free()
		battle = null
	player.cancel()


## Starts a playable battle on the grassy hills board (hex), or on a world-style board
## when `world_spec` is set (screenshots: "gen<seed>[+landscape[+culture]]" or
## "urban|hills|alien[=landscape-culture]", as in world_preview).
func start_battle() -> void:
	_stop_battle()
	combat_log.clear_log()
	view.overlays.clear()
	biome = "grassy_hills"
	shape = GridLayout.Shape.HEX
	var map := DemoMap.build_hills(shape)
	var kit := biome
	var off: Vector2 = BIOME_OFFSET[biome]
	if world_spec != "":
		var w := _world_map(world_spec)
		map = w[0]
		kit = w[1]
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for c in map.cells():
			var p := map.grid.to_world(c)
			lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
		off = Vector2((lo.x + hi.x) * 0.5 - 7.5, (lo.z + hi.z) * 0.5 - 8.5)
	battle_offset = off
	view.set_map(map, kit)
	if world_mission and world_spec.begins_with("gen"):
		# What the players' seat may know of the sitrep: zones and deployment areas.
		view.show_mission({"zones": world_mission.zones, "deployment": world_mission.deployment}, GameState.PHASE_COMBAT)
	battle = DemoBattle.new()
	add_child(battle)
	battle.setup(content, view, player, _ui)
	var roster := ROSTER.duplicate(true)
	for id: String in BATTLE_LOADOUTS:
		(roster[id] as Array)[6] = BATTLE_LOADOUTS[id]
	for id: String in battle_systems:
		(roster[id] as Array).append(battle_systems[id])
	battle.load_battle(map, roster, off)
	view.tactical.look_at_point(Vector3(7.5 + off.x, 0.8, 7.0 + off.y), 15.0)
	view.tactical.snap()
	_update_help()
	await battle.start()


# --- sample data -------------------------------------------------------------------------

func _cell(id: String) -> Vector2i:
	return (view.units[id] as MechView).cell


## A ground path along the grid line between two cells, as [x, y, level] steps.
func _path(from: Vector2i, to: Vector2i) -> Array:
	var out: Array = []
	for c in view.map.grid.line(from, to):
		out.append([c.x, c.y, view.map.ground_height(c)])
	return out


## Sample move plan in the TurnOverlays format (values a rules engine would supply).
func move_plan() -> Dictionary:
	var start := _cell("everest")
	var dest := DemoMap.cell_at(view.map, 4.8, 6.9)
	var path := _path(start, dest)
	var info: Array = [{}]
	for i in range(1, path.size()):
		var flags: Array = []
		if int(path[i][2]) > int(path[i - 1][2]):
			flags.append("climb")
		if view.map.column(Vector2i(path[i][0], path[i][1])).has_tag("difficult"):
			flags.append("difficult")
		info.append({"cost": 2 if "difficult" in flags else 1, "flags": flags})
	var cover: Array = []
	for c in view.map.cells():
		var col := view.map.column(c)
		if col.ground == 1:
			cover.append({"cell": [c.x, c.y], "level": 1, "kind": "hard"})
	return {
		"path": path, "path_info": info, "speed": 4, "boost": 4, "size": 1,
		"footprint": {"cell": [dest.x, dest.y], "level": view.map.ground_height(dest), "size": 1, "ok": true},
		"cover": cover,
		"cover_from": [{"unit": "goblin", "kind": "hard"}, {"unit": "sherman", "kind": "none"}],
	}


func sky_plan(level: int) -> Dictionary:
	var center := _cell("swallowtail")
	var cells: Array = []
	for c in view.map.grid.cells_within(center, 4):
		if view.map.has_cell(c) and view.map.ground_height(c) < level:
			cells.append([c.x, c.y])
	var dest := DemoMap.cell_at(view.map, 11.0, 8.0)
	var path: Array = []
	for c in view.map.grid.line(center, dest):
		path.append([c.x, c.y, level])
	return {"sky_layer": {"level": level, "cells": cells}, "path": path, "speed": 5, "boost": 5,
		"footprint": {"cell": [dest.x, dest.y], "level": level, "size": 1, "ok": true}}


func los_plan() -> Dictionary:
	# Sample: spaces behind the tall buildings are out of sight of the Everest.
	var dim: Array = []
	for c in view.map.cells():
		var w := view.map.grid.to_world(c)
		if (w.x < 4.0 and w.z < 4.5) or (w.x > 14.0 and w.z < 4.0) or (w.x > 13.0 and w.z > 8.5 and w.z < 12):
			dim.append([c.x, c.y])
	return {"los": {"dim_cells": dim, "no_los_units": ["barbarossa"]},
		"cover": [{"cell": [DemoMap.cell_at(view.map, 11.9, 5.5).x, DemoMap.cell_at(view.map, 11.9, 5.5).y], "level": 1, "kind": "hard"}]}


## Sample resource HUD data for the Everest (ResourceHUD format; the rules engine supplies it).
func sample_resources() -> Dictionary:
	return {
		"name": "Everest", "frame": "GMS Everest", "hp": [8, 10], "overshield": 0, "heat": [2, 6],
		"danger_zone": 3, "structure": [4, 4], "stress": [4, 4], "repairs": [3, 5], "burn": 0,
		"core_power": "available",
		"economy": {"quick": [1, 2], "full": [0, 1], "move": [4, 4], "reaction": [1, 1], "overcharge_next": "1d3"},
	}


## Sample action buttons (ActionBar format). Names and text come from lancer-data; the
## availability and reasons here are made-up samples until the rules engine provides them.
func sample_actions() -> Array:
	var act := func(id: String, extra: Dictionary) -> Dictionary:
		var e := content.get_entry("actions", id)
		var a := {"id": id, "name": e.get("name", id), "cost": String(e.get("activation", "Quick")).to_lower().replace("quick tech", "quick"),
			"desc": _plain(e.get("terse", "")), "text": _plain(e.get("detail", "")), "rule_ref": "Core rules: %s (lancer-data %s)" % [e.get("name", id), id]}
		a.merge(extra, true)
		return a
	var core: Dictionary = content.frame("mf_standard_pattern_i_everest").get("core_system", {})
	return [
		{"id": "w_assault_rifle", "name": "Assault Rifle", "cost": "quick", "desc": "Skirmish: Range 10, 1d6 kinetic.",
			"text": "Attack with the Assault Rifle as a Skirmish.", "rule_ref": "Core rules: Skirmish", "preview": {"quick": 1}},
		{"id": "w_howitzer", "name": "Howitzer", "cost": "quick", "desc": "Range 20, Blast 1, 2d6 explosive.",
			"extras": [{"kind": "charges", "value": "0/1"}], "enabled": false, "reason": "Loading: not reloaded yet",
			"text": "Loading weapon: after firing it must be reloaded before it can fire again.", "rule_ref": "Tag: Loading"},
		act.call("act_barrage", {"enabled": false, "reason": "Already used a Quick action this turn"}),
		act.call("act_boost", {"preview": {"quick": 1}}),
		act.call("act_lockon", {"enabled": false, "reason": "No enemy within Sensors range"}),
		act.call("act_hide", {"preview": {"quick": 1}}),
		act.call("act_overcharge", {"extras": [{"kind": "overcharge", "value": "1d3"}], "preview": {"heat": [1, 3], "overcharge": 1}}),
		act.call("act_stabilize", {"enabled": false, "reason": "Needs a Full action; one Quick action is spent"}),
		act.call("act_brace", {"preview": {"reaction": 1}}),
		act.call("act_overwatch", {"preview": {"reaction": 1}}),
		{"id": "core", "name": String(core.get("active_name", "Core Power")), "cost": String(core.get("activation", "Protocol")).to_lower(),
			"desc": _plain(core.get("active_effect", "")), "text": _plain(core.get("active_effect", "")),
			"extras": [{"kind": "charges", "value": "1/1"}], "rule_ref": "Everest core system: %s" % core.get("name", ""), "preview": {"core_power": 1}},
	]


static func _plain(html: String) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(html.replace("<br>", "
"), "", true).strip_edges()


func _check(d20: int, acc: Array, diff: Array, dice: Array, bonuses: Array, target: int, target_label: String = "Evasion") -> Dictionary:
	var sources: Array = []
	for a: String in acc:
		sources.append({"label": a, "type": "accuracy"})
	for d: String in diff:
		sources.append({"label": d, "type": "difficulty"})
	var net := acc.size() - diff.size()
	var kept := 0
	for v: int in dice:
		kept = maxi(kept, v)
	var bonus := 0
	for b: Dictionary in bonuses:
		bonus += int(b["value"])
	var value := kept * signi(net)
	var total := d20 + bonus + value
	return {
		"d20": d20, "bonus": bonus, "bonuses": bonuses, "total": total, "target": target,
		"target_label": target_label, "success": total >= target, "crit": total >= 20, "sources": sources,
		"accuracy_roll": {"accuracy": acc.size(), "difficulty": diff.size(), "net": net,
			"color": "blue" if net > 0 else ("red" if net < 0 else ""), "dice": dice, "kept": kept, "value": value},
	}


## A ground-level cell next to `target`, on the side facing `from` (for melee demos).
func _beside(target: String, from: String) -> Vector2i:
	var t := _cell(target)
	var f := _cell(from)
	var best := t
	var best_d := 1 << 30
	for n in view.map.grid.neighbors(t):
		if not view.map.has_cell(n) or view.map.ground_height(n) != view.map.ground_height(t):
			continue
		var d := view.map.grid.distance(n, f)
		if d < best_d:
			best_d = d
			best = n
	return best


func demo_events() -> Dictionary:
	var ev := {}
	var dest := DemoMap.cell_at(view.map, 4.8, 6.9)
	ev["move"] = [{"type": "moved", "unit": "everest", "path": _path(_cell("everest"), dest), "mode": "walk"}]
	ev["kinetic"] = [
		{"type": "attack_rolled", "attacker": "everest", "target": "goblin", "weapon": "mw_assault_rifle", "result": "hit",
			"check": _check(13, ["Lock On", "Accurate"], ["Soft cover"], [4], [{"label": "Grit", "value": 2}], 8)},
		{"type": "damage_dealt", "target": "goblin", "amount": 4, "damage_type": "Kinetic", "armor_reduced": 0, "resisted": false,
			"roll": {"expr": "1d6", "rolls": [{"sides": 6, "value": 4}], "bonus": 0, "total": 4}},
		{"type": "heat_changed", "unit": "everest", "amount": 2, "total": 2},
	]
	ev["beam"] = [
		{"type": "attack_rolled", "attacker": "sherman", "target": "everest", "weapon": "mw_andromeda_pattern_heavy_laser_rifle", "result": "miss",
			"check": _check(7, [], ["Hard cover", "Impaired"], [5, 2], [{"label": "Attack bonus", "value": 1}], 8)},
		{"type": "attack_rolled", "attacker": "sherman", "target": "blackbeard", "weapon": "mw_sol_pattern_laser_rifle", "result": "hit",
			"check": _check(15, [], [], [], [{"label": "Attack bonus", "value": 1}], 8)},
		{"type": "damage_dealt", "target": "blackbeard", "amount": 3, "damage_type": "Energy"},
	]
	ev["missile"] = [
		{"type": "attack_rolled", "attacker": "everest", "target": "barbarossa", "weapon": "mw_howitzer", "result": "hit",
			"check": _check(11, ["Lock On"], [], [6], [{"label": "Grit", "value": 2}], 6)},
		{"type": "damage_dealt", "target": "barbarossa", "amount": 8, "damage_type": "Explosive"},
		{"type": "attack_rolled", "attacker": "barbarossa", "target": "drake", "weapon": "mw_shatterhead_colony_missiles", "result": "hit",
			"check": _check(12, [], [], [], [{"label": "Attack bonus", "value": 2}], 6)},
		{"type": "damage_dealt", "target": "drake", "amount": 5, "damage_type": "Energy"},
	]
	ev["melee"] = [
		{"type": "moved", "unit": "blackbeard", "path": _path(_cell("blackbeard"), _beside("tokugawa", "blackbeard")), "mode": "boost"},
		{"type": "attack_rolled", "attacker": "blackbeard", "target": "tokugawa", "weapon": "mw_chain_axe", "result": "crit",
			"check": _check(18, [], [], [], [{"label": "Grit", "value": 2}], 8)},
		{"type": "damage_dealt", "target": "tokugawa", "amount": 9, "damage_type": "Kinetic"},
		{"type": "attack_rolled", "attacker": "tokugawa", "target": "blackbeard", "weapon": "mw_torch", "result": "miss",
			"check": _check(6, [], ["Shredded?"], [3], [], 8)},
	]
	ev["tech"] = [
		{"type": "tech_attack", "attacker": "goblin", "target": "everest", "result": "hit", "effect": "Jam",
			"check": _check(14, [], [], [], [{"label": "Tech Attack", "value": 2}], 8, "E-Defense")},
		{"type": "status_added", "unit": "everest", "status": "Jammed", "source": "goblin"},
		{"type": "tech_attack", "attacker": "minotaur", "target": "goblin", "result": "hit", "effect": "Lock On",
			"check": _check(9, ["Lock On"], [], [5], [{"label": "Tech Attack", "value": 1}], 6, "E-Defense")},
		{"type": "status_added", "unit": "goblin", "status": "Lock On", "source": "minotaur"},
	]
	var smoke_cells: Array = []
	for c in view.map.grid.cells_within(DemoMap.cell_at(view.map, 7.6, 7.6), 1):
		smoke_cells.append([c.x, c.y, view.map.ground_height(c)])
	var wall_cells: Array = []
	for x: float in [10.9, 11.9, 12.9]:
		var c := DemoMap.cell_at(view.map, x, 9.6)
		wall_cells.append([c.x, c.y, view.map.ground_height(c)])
	ev["deploy"] = [
		{"type": "deployed", "unit": "minotaur", "object": {"kind": "smoke", "id": "smoke1", "name": "Smoke Grenade", "cells": smoke_cells}},
		{"type": "deployed", "unit": "swallowtail", "object": {"kind": "hard_light_wall", "id": "wall1", "name": "Hard Light Wall", "cells": wall_cells, "height": 1.0}},
	]
	ev["heat"] = [
		{"type": "heat_changed", "unit": "everest", "amount": 4, "total": 6},
		{"type": "stress_check", "unit": "everest", "roll": 6, "outcome": "Emergency Shunt: no further effect"},
		{"type": "heat_changed", "unit": "everest", "amount": -6, "total": 0},
	]
	ev["structure"] = [
		{"type": "damage_dealt", "target": "goblin", "amount": 6, "damage_type": "Kinetic", "hp": 0},
		{"type": "structure_check", "unit": "goblin", "roll": 6, "outcome": "Glancing Blow"},
		{"type": "structure_changed", "unit": "goblin", "amount": -1, "total": 3},
	]
	ev["destroy"] = [
		{"type": "destroyed", "unit": "goblin"},
		{"type": "turn_ended", "unit": "everest"},
	]
	return ev


func _run_demo() -> void:
	_running = true
	var ev := demo_events()
	view.overlays.show_plan(move_plan())
	await Fx.wait(self, 2.0)
	view.overlays.clear()
	for key: String in ["move", "kinetic", "beam", "missile", "melee", "tech", "deploy", "heat", "structure", "destroy"]:
		_focus_for(key)
		await player.play(ev[key])
	_running = false


func _focus_for(key: String) -> void:
	var pairs := {
		"move": ["everest", "goblin"], "kinetic": ["everest", "goblin"], "beam": ["sherman", "blackbeard"],
		"missile": ["everest", "barbarossa"], "melee": ["blackbeard", "tokugawa"], "tech": ["goblin", "everest"],
		"deploy": ["minotaur", "swallowtail"], "heat": ["everest", "everest"],
		"structure": ["goblin", "goblin"], "destroy": ["goblin", "goblin"],
	}
	var p: Array = pairs.get(key, ["everest", "goblin"])
	var a: MechView = view.units[p[0]]
	var b: MechView = view.units[p[1]]
	view.tactical.frame_pair(a.global_position, b.global_position, 5.5)


# --- screenshots -----------------------------------------------------------------------

func _battle_stage(tag: String) -> void:
	rolls.hold = false
	Fx.speed = 4.0
	await start_battle()
	if tag == "turn_order":
		Fx.speed = 1.0
		var off := battle_offset
		view.tactical.look_at_point(Vector3(7.5 + off.x, 0.8, 7.5 + off.y), 15.0)
		view.tactical.pitch = -50.0
		view.tactical.snap()
		return
	if tag == "skill":
		Fx.speed = 1.0
		rolls.hold = true
		player.play_event({"type": "skill_check", "unit": "everest", "check": {"label": "Engineering check", "skill": "Engineering", "d20": 14, "total": 16, "target": 10,
			"success": true, "bonus_sources": [{"label": "Engineering", "value": 2}], "sources": [{"label": "Trained (trigger)", "kind": "accuracy"}],
			"accuracy_roll": {"accuracy": 1, "difficulty": 0, "net": 1, "color": "blue", "dice": [3], "kept": 3, "value": 3}}})
		view.tactical.look_at_point(view.units["everest"].global_position + Vector3.UP * 0.6, 6.0)
		view.tactical.snap()
		await get_tree().create_timer(3.0).timeout
		return
	battle._on_i_will_go("everest")
	while not battle.turn.active:
		await get_tree().process_frame
	Fx.speed = 1.0
	await get_tree().create_timer(0.8).timeout
	var t := battle.turn
	var me: Unit = battle.state.unit("everest")
	match tag:
		"my_turn", "bar_small", "bar_large":
			if tag == "bar_small":
				battle.bar.bar_scale = 0.75
			elif tag == "bar_large":
				battle.bar.bar_scale = 1.4
			# Plan a move three spaces toward the enemy and show the confirm prompt.
			var goal := battle.state.unit("goblin").cell
			var line := view.map.grid.line(me.cell, goal)
			var best: Vector2i = line[1]
			for i in range(1, line.size()):
				if RulesQueries.preview_move(battle.state, "everest", line[i]).get("ok", false):
					best = line[i]
			t.plan_move(best)
		"target":
			for a: Dictionary in battle.bar.actions:
				if a.get("kind") == "attack":
					t._on_action(a)
					break
			t.hover_target("goblin")
			view.tactical.frame_pair(view.units["everest"].global_position, view.units["goblin"].global_position, 7.0)
			view.tactical.snap()
		"fly_up", "fly_across", "fly_fall":
			var line := view.map.grid.line(me.cell, battle.state.unit("goblin").cell)
			var cam := view.get_viewport().get_camera_3d()
			var ground := view.map.ground_height(me.cell)
			view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 1.0, -1.0), 10.0)
			view.tactical.pitch = -32.0
			view.tactical.yaw = 35.0
			view.tactical.snap()
			await get_tree().process_frame
			if tag == "fly_up":
				t.toggle_fly()
				t.change_sky(1)
				var c: Vector2i = line[mini(2, line.size() - 1)]
				t.plan_move(c)
			elif tag == "fly_across":
				var c1: Vector2i = line[1]
				await battle.submit({"type": "move", "actor": "everest", "params": {"to": [c1.x, c1.y], "fly": true, "level": view.map.ground_height(c1) + 2}})
				t.fly = true
				t.sky_level = battle.state.unit("everest").level
				t.refresh()
				var c2: Vector2i = line[mini(3, line.size() - 1)]
				view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 0.0, -1.0), 10.0)
				view.tactical.snap()
				await get_tree().process_frame
				t.plan_move(c2)
			else:
				# Jump jets: a Boost that ends in the air falls at once (Core p.63).
				var c3: Vector2i = line[2]
				var seen := [false]
				player.event_started.connect(func(ev: Dictionary) -> void:
					if ev.get("type") == "moved" and ev.get("mode") == "fall":
						seen[0] = true)
				battle.submit({"type": "boost", "actor": "everest", "params": {"to": [c3.x, c3.y], "fly": true, "level": view.map.ground_height(c3) + 3}})
				var guard := 0
				while not seen[0] and guard < 600:
					guard += 1
					await get_tree().process_frame
				await get_tree().create_timer(0.18).timeout
				return
			await get_tree().create_timer(0.4).timeout
		"eject", "dismount", "on_foot":
			# Pilots on foot through the rules engine: Eject (launched out), Dismount (climbs down).
			var spot: Variant = Pilots.free_adjacent(battle.state, me, null)
			var to: Vector2i = spot[0] if spot != null else me.cell
			view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 0.3, 0), 6.5 if tag == "dismount" else 11.0)
			view.tactical.pitch = -30.0 if tag == "dismount" else -42.0
			view.tactical.snap()
			var seen := [false]
			player.event_started.connect(func(ev: Dictionary) -> void:
				if ev.get("type") == "pilot_left_mech":
					seen[0] = true)
			var act := {"type": "dismount" if tag == "dismount" else "eject", "actor": "everest", "params": {"to": [to.x, to.y]}}
			if tag != "dismount":
				# Eject's distance is a table ruling (grey area): use the suggested reading here,
				# then the farthest landing space the engine accepts.
				Rulings.apply_suggested(battle.state)
				var best := -1
				for c: Vector2i in view.map.grid.cells_within(me.cell, 6):
					var p := {"type": "eject", "actor": "everest", "params": {"to": [c.x, c.y]}}
					var d := view.map.grid.distance(me.cell, c)
					if d > best and battle.engine.validate(battle.state, p).ok:
						best = d
						act = p
			var r: RuleResult = battle.engine.validate(battle.state, act)
			if not r.ok:
				push_warning("%s refused: %s" % [act["type"], r.reason])
			if tag == "on_foot":
				await battle.submit(act)
				var pv: MechView = view.units.get(battle.state.unit("everest").counters.get("pilot", ""))
				if pv:
					view.tactical.look_at_point(pv.global_position + Vector3(0, 0.2, 0), 4.0)
					view.tactical.snap()
				await get_tree().create_timer(0.5).timeout
				return
			battle.submit(act)
			var guard := 0
			while not seen[0] and guard < 600:
				guard += 1
				await get_tree().process_frame
			await get_tree().create_timer(0.45 if tag == "eject" else 0.4).timeout
		"barriers":
			# Vision and barrier zones, a Blinded mech and a cascading NHP (look check).
			var mc := me.cell
			view.zones.set_zones([
				{"id": "b1", "kind": "hardlight", "owner": "everest", "cells": _ring_cells(mc, 2)},
				{"id": "b2", "kind": "blink", "owner": "goblin", "cells": _ring_cells(battle.state.unit("goblin").cell, 1)},
				{"id": "b3", "kind": "flash", "owner": "everest", "cells": _ring_cells(mc + Vector2i(-4, 2), 1)},
				{"id": "b4", "kind": "oasis", "owner": "everest", "cells": [[mc.x + 3, mc.y + 1], [mc.x + 3, mc.y + 2], [mc.x + 4, mc.y + 2], [mc.x + 4, mc.y + 3]]},
			])
			(view.units["minotaur"] as MechView).set_stat("statuses", {"Blinded": {}})
			(view.units["blackbeard"] as MechView).set_stat("statuses", {"Cascading": {}})
			view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 0.5, 0), 15.0)
			view.tactical.pitch = -48.0
			view.tactical.snap()
			await get_tree().create_timer(0.8).timeout
		"tactical_view":
			t.set_tactical_view(true)
			view.tactical.distance = 18.0
			await get_tree().create_timer(0.8).timeout
		"barks":
			var rng := RandomNumberGenerator.new()
			rng.seed = 8
			battle.barks.say({"unit": "everest", "name": "Hawk", "face": {"portrait": PortraitSpec.randomize(rng), "expression": "determined"},
				"text": "Moving up. Cover me, Blackbeard.", "duration": 30.0})
			battle.barks.say({"unit": "blackbeard", "name": "Rook", "face": {"portrait": PortraitSpec.randomize(rng), "expression": "smiling"},
				"text": "Always do.", "duration": 30.0})
			battle.barks.say({"name": "Harrow Actual", "side": "enemies", "face": {"portrait": PortraitSpec.randomize(rng), "expression": "angry"},
				"text": "All units, hold the ridge. Nobody gets past the river.", "duration": 30.0})
			await get_tree().create_timer(0.6).timeout
		"gear", "gear_aim", "gear_table":
			# Zones on the board (real ones from the engine plus one of each other kind),
			# then the step-by-step picker aiming a smoke grenade.
			var me_cell := me.cell
			var zl := [
				{"id": "z1", "kind": "caltrops", "owner": "everest", "label": "Caltrops", "cells": _ring_cells(me_cell + Vector2i(-3, 1), 1)},
				{"id": "z2", "kind": "sealant", "owner": "everest", "label": "Sealant", "cells": _ring_cells(me_cell + Vector2i(2, 3), 1)},
				{"id": "z3", "kind": "javelin", "owner": "everest", "label": "Javelin", "cells": [[me_cell.x + 4, me_cell.y - 2]]},
				{"id": "z4", "kind": "smoke", "owner": "everest", "label": "Smoke", "cells": _ring_cells(me_cell + Vector2i(1, -4), 1)},
				{"id": "z5", "kind": "bunker", "owner": "everest", "label": "Bunker", "cells": [[me_cell.x - 1, me_cell.y - 2]]},
				{"id": "z6", "kind": "cloak", "owner": "swallowtail", "label": "Cloaking Field", "cells": [], "radius": 2, "center": [0, 0]},
			]
			view.zones.set_zones(zl)
			if tag == "gear_aim":
				for a: Dictionary in battle.bar.actions:
					if String(a.get("name", "")).contains("Smoke Grenade"):
						t._on_action(a)
				var target_cell := me_cell + Vector2i(2, -3)
				var cam := view.get_viewport().get_camera_3d()
				t.hover_screen(cam.unproject_position(view.cell_pos(target_cell, view.map.ground_height(target_cell))))
			elif tag == "gear_table":
				player.play_event({"type": "manual_effect", "unit": "everest", "source": "COMP/CON Class Assistant Unit",
					"text": "Your mech gains the AI tag... (rule text shown here)", "guidance": "Not automated yet: read the system's text and apply it at the table."})
				battle.bar.set_tab("systems")
				await get_tree().process_frame
				for a: Dictionary in battle.bar.actions:
					if a.has("table"):
						battle.bar.hover(String(a["id"]))
						break
			else:
				battle.bar.set_tab("all")
			view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 0.5, -1.5), 13.0)
			view.tactical.pitch = -55.0
			view.tactical.snap()
			await get_tree().create_timer(1.0).timeout
		"cooldowns":
			t.cancel()
			battle.bar.set_actions(lockout_samples(), "demo_cooldowns")
			battle.bar.resources.set_data(sample_resources())
			await get_tree().process_frame
			battle.bar.hover("act_overcharge")
		"enemy_turn", "reaction":
			battle.auto_react = tag == "enemy_turn"
			t.end_turn()
			# Wait for an enemy attack roll to be on screen.
			var seen := [false]
			var want := ["reaction_offered"] if tag == "reaction" else ["attack_rolled", "tech_attack"]
			player.event_started.connect(func(e: Dictionary) -> void:
				if e.get("type") in want:
					seen[0] = true)
			var waited := 0.0
			while not seen[0] and waited < 40.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
			await get_tree().create_timer(2.2).timeout

## tools/screenshot.gd hook. Pass "all" (or tag names) after the frame count; out path
## must contain %s. Tags: board square move sky los roll kinetic beam missile melee tech
## deploy heat vent destroy cockpit.
func screenshot_setup(args: PackedStringArray) -> Array:
	view.labels.cursor = Vector2(-10000, -10000)  # no mouse in screenshots
	var tags: Array = Array(args)
	if tags.is_empty() or tags[0] == "all":
		tags = ["board", "square", "move", "sky", "los", "roll", "kinetic", "beam", "missile", "melee", "tech", "deploy", "heat", "vent", "destroy", "cockpit", "hud", "hills", "hills_close", "hills_nogrid", "hills_square", "alien", "alien_close", "alien_vista",
			"turn_order", "my_turn", "target", "cooldowns", "enemy_turn", "skill", "walk", "reaction", "wreck"]
	return tags


func player_turn_cancel() -> void:
	if battle and battle.turn:
		battle.turn.cancel()


func _ring_cells(c: Vector2i, r: int) -> Array:
	var out: Array = []
	for x in view.map.grid.cells_within(c, r):
		if view.map.has_cell(x):
			out.append([x.x, x.y])
	return out


## Sample actions with one of each lockout kind, for the cooldown screenshot.
func lockout_samples() -> Array:
	var list := sample_actions()
	list.append({"id": "lk_turns", "group": "systems", "cost": "quick", "icon": "system", "name": "Pattern-A Jericho", "short": "Jericho",
		"enabled": false, "reason": "Deployed: back in 1 round.", "lockout": {"kind": "turns", "left": 1, "total": 3},
		"text": "Sample: a timed wait shrinks like a clock hand as rounds pass."})
	list.append({"id": "lk_recharge", "group": "systems", "cost": "quick", "icon": "npc_feature", "name": "Seismic Ripper (Recharge 5+)", "short": "Ripper",
		"enabled": false, "reason": "Recharge 5+: roll a 5 or 6 at the start of the turn.", "lockout": {"kind": "recharge", "target": 5},
		"text": "Sample NPC ability with Recharge 5+."})
	list.append({"id": "lk_ready", "group": "systems", "cost": "quick", "icon": "npc_feature", "name": "Shock Wave (Recharge 4+)", "short": "Shock",
		"enabled": true, "lockout": {"kind": "recharge", "target": 4, "ready": true}, "text": "Recharge roll succeeded: ready again."})
	list.append({"id": "lk_uses", "group": "systems", "cost": "quick", "icon": "grenade", "name": "Smoke Charges (Limited 2)", "short": "Smoke",
		"enabled": false, "reason": "Limited 2: used this mission.", "lockout": {"kind": "uses", "left": 0, "total": 2}, "text": "Sample Limited system."})
	list.append({"id": "lk_status", "group": "tech", "cost": "quick", "icon": "tech_quick", "name": "Invade", "short": "Invade",
		"enabled": false, "reason": "Jammed: can't take tech actions until the end of your next turn.", "lockout": {"kind": "status", "status": "Jammed", "turns": 1},
		"text": "Status lockout sample."})
	var groups := {"w_assault_rifle": "weapons", "w_howitzer": "weapons", "act_barrage": "full", "act_stabilize": "full",
		"act_lockon": "tech", "act_brace": "reactions", "act_overwatch": "reactions", "core": "core"}
	var icons := {"w_assault_rifle": "kinetic", "w_howitzer": "explosive", "act_lockon": "condition_lockon", "act_hide": "status_hidden",
		"act_barrage": "barrage", "act_stabilize": "repair", "act_overwatch": "threat", "core": "corebonus", "act_overcharge": "overcharge"}
	for a: Dictionary in list:
		a["group"] = groups.get(a.get("id"), a.get("group", "quick"))
		if icons.has(a.get("id")):
			a["icon"] = icons[a["id"]]
		if a.get("id") == "w_howitzer":
			a["lockout"] = {"kind": "loading"}
			a["reason"] = "Loading: reload it (Stabilize) before firing again."
		if a.get("id") == "act_overcharge":
			a["text"] = "Take any quick action as a free action, even one you've already taken this turn. Costs heat: 1, then 1d3, 1d6, then 1d6+4."
			a["extras"] = [{"icon": "heat", "value": "+1d3"}]
			a["warnings"] = [{"text": "This can put you in the Danger Zone {icon:status_dangerzone} (2/6 {icon:heat} → up to 5)."}]
	return list


func screenshot_stage(tag: String) -> void:
	world_spec = ""
	world_mission = null
	battle_systems = {}
	if tag in ["barks", "eject", "dismount", "on_foot", "barriers", "tactical_view"]:
		await _battle_stage(tag)
		return
	if tag.begins_with("fly"):
		# Flying with the rules engine's real movement: a flight system, or jump jets for the fall.
		battle_systems = {"everest": ["ms_rapid_burst_jump_jet_system"] if tag == "fly_fall" else ["ms_type_i_flight_system"]}
		await _battle_stage(tag)
		return
	if tag.begins_with("gear"):
		battle_systems = {"everest": ["ms_pattern_a_smoke_charges", "ms_javelin_rockets", "ms_caltrop_launcher", "ms_lb_oc_cloaking_field", "ms_comp_con_class_assistant_unit"]}
		await _battle_stage(tag)
		return
	if tag.begins_with("world="):
		# The player's turn HUD on one of the world session's boards.
		world_spec = tag.trim_prefix("world=")
		await _battle_stage("my_turn")
		if world_mission and not world_mission.zones.is_empty():
			# Pull back to show the sitrep's objectives across the board.
			player_turn_cancel()
			view.tactical.look_at_point(view.units["everest"].global_position + Vector3(0, 0, -6.0), 26.0)
			view.tactical.pitch = -58.0
			view.tactical.snap()
			await get_tree().create_timer(0.6).timeout
		return
	if tag in ["turn_order", "my_turn", "target", "cooldowns", "enemy_turn", "skill", "bar_small", "bar_large", "reaction"]:
		await _battle_stage(tag)
		return
	_stop_battle()
	view.overlays.clear()
	player.cancel()
	rolls.clear_all()
	rolls.hold = false
	if view.camera_mode != "tactical":
		_toggle_camera()
	for c in view.fx_root.get_children():
		c.queue_free()
	player.lasting.clear()
	shape = GridLayout.Shape.SQUARE if tag in ["square", "hills_square"] else GridLayout.Shape.HEX
	biome = "grassy_hills" if tag.begins_with("hills") else ("alien_wilds" if tag.begins_with("alien") else "urban_ruins")
	_build_board()
	resources.visible = tag == "hud"
	action_bar.visible = tag == "hud"
	var ev := demo_events()
	match tag:
		"board":
			view.tactical.look_at_point(Vector3(7.5, 0.8, 6.8), 14.5)
			view.tactical.snap()
		"square":
			view.tactical.look_at_point(Vector3(7.5, 0.8, 6.8), 14.5)
			view.tactical.snap()
		"move":
			view.overlays.show_plan(move_plan())
			view.tactical.look_at_point(Vector3(5.5, 0.8, 8.0), 8.5)
			view.tactical.snap()
		"sky":
			view.overlays.show_plan(sky_plan(3))
			view.tactical.look_at_point(Vector3(11.5, 2.5, 9.0), 9.0)
			view.tactical.snap()
		"los":
			view.overlays.show_plan(los_plan())
			view.tactical.look_at_point(Vector3(7.5, 0.8, 6.8), 14.5)
			view.tactical.snap()
		"roll":
			rolls.hold = true
			Fx.speed = 4.0
			_focus_for("kinetic")
			view.tactical.snap()
			await player.play([ev["kinetic"][0], ev["kinetic"][1]])
			Fx.speed = 1.0
		"kinetic", "beam", "missile", "melee", "tech":
			_focus_for(tag)
			view.tactical.snap()
			player.camera = view.tactical
			# Time from the start of the shot/swing to the most telling moment.
			var delays := {"kinetic": 0.06, "beam": 0.42, "missile": 0.62, "melee": 0.32, "tech": 0.55}
			var list: Array = ev[tag]
			if tag == "beam":
				list = [ev["beam"][1]]
			elif tag == "melee":
				await player.play([ev["melee"][0]])
				list = [ev["melee"][1]]
			elif tag == "missile":
				list = [ev["missile"][0]]
			player.play(list)
			await player.firing
			view.tactical.snap()
			await Fx.wait(self, delays[tag])
		"deploy":
			_focus_for("deploy")
			view.tactical.snap()
			await player.play(ev["deploy"])
			await Fx.wait(self, 0.6)
		"heat", "vent":
			await player.play(ev["move"])
			_focus_for("heat")
			view.tactical.distance = 4.5
			view.tactical.snap()
			await player.play([ev["heat"][0]])
			if tag == "vent":
				player.play([ev["heat"][2]])
				await Fx.wait(self, 0.7)
		"destroy", "wreck":
			_focus_for("destroy")
			view.tactical.distance = 4.5
			view.tactical.snap()
			await player.play(ev["structure"])
			player.play(ev["destroy"])
			# The fireball at its peak, or the burning wreck once it settles.
			await Fx.wait(self, 0.35 if tag == "destroy" else 2.6)
		"firetest":
			var at: Vector3 = view.units["goblin"].global_position + Vector3(1.5, 0, 0)
			view.units["goblin"].visible = false
			Fx.fire(view.fx_root, at + Vector3.UP * 0.1, 0.8)
			view.tactical.look_at_point(at + Vector3.UP * 0.4, 3.0)
			view.tactical.pitch = -12
			view.tactical.snap()
			await Fx.wait(self, 1.5)
		"walk":
			_focus_for("move")
			view.tactical.distance = 4.0
			view.tactical.pitch = -20
			view.tactical.snap()
			player.play(demo_events()["move"])
			await get_tree().create_timer(0.9).timeout
		"hills", "hills_square":
			view.tactical.look_at_point(Vector3(15.0, 1.0, 13.5), 30.0)
			view.tactical.pitch = -46
			view.tactical.snap()
		"alien":
			view.tactical.look_at_point(Vector3(15.0, 1.0, 12.0), 30.0)
			view.tactical.pitch = -30
			view.tactical.yaw = 0
			view.tactical.snap()
		"alien_close":
			view.tactical.look_at_point(Vector3(11.0, 1.5, 14.0), 12.0)
			view.tactical.pitch = -22
			view.tactical.yaw = 25
			view.tactical.snap()
		"alien_vista":
			view.terrain.set_grid_visible(false)
			view.tactical.look_at_point(Vector3(13.0, 4.0, 12.0), 16.0)
			view.tactical.pitch = -4
			view.tactical.yaw = 37
			view.tactical.snap()
		"hills_close":
			view.tactical.look_at_point(Vector3(13.0, 1.2, 14.0), 11.0)
			view.tactical.pitch = -32
			view.tactical.yaw = -20
			view.tactical.snap()
		"hills_nogrid":
			view.terrain.set_grid_visible(false)
			view.tactical.look_at_point(Vector3(13.0, 1.2, 14.0), 11.0)
			view.tactical.pitch = -32
			view.tactical.yaw = -20
			view.tactical.snap()
		"hud":
			view.overlays.show_plan(move_plan())
			view.tactical.look_at_point(Vector3(5.5, 0.8, 8.0), 9.5)
			view.tactical.snap()
			await get_tree().process_frame
			action_bar.hover("act_overcharge")
		"cockpit":
			player.play([ev["tech"][0]])
			await Fx.wait(self, 0.2)
			_toggle_camera()
			await Fx.wait(self, 1.2)
