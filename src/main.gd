extends Node3D
## Visual demo: an urban ruins board with mechs, turn overlays and a scripted event sequence.
## Space replays the sequence, G switches hex/square, C switches camera (tactical/cockpit),
## V cycles playback speed (full / quick / instant), 1-3 show overlay examples.
## The events here are hand-written samples in the rules engine's event format; in the game
## they come from RulesEngine.

var content: ContentDB
var view: BattleView
var player: EventPlayer
var rolls: RollDisplay
var combat_log: CombatLog
var hud: CockpitHUD
var resources: ResourceHUD
var action_bar: ActionBar
var shape := GridLayout.Shape.HEX
var _ui: CanvasLayer
var _help: Label
var _speed_i := 0
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
	"tokugawa": ["mf_tokugawa", "enemies", 10.3, 5.6, 0, "Tokugawa", [["Flex", ["mw_torch"]], ["Main", ["mw_annihilator"]]]],
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
		_run_demo.call_deferred()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	hud = CockpitHUD.new()
	hud.visible = false
	_ui.add_child(hud)
	rolls = RollDisplay.new()
	_ui.add_child(rolls)
	combat_log = CombatLog.new()
	combat_log.position = Vector2(1600 - 496, 70)
	_ui.add_child(combat_log)
	resources = ResourceHUD.new()
	_ui.add_child(resources)
	action_bar = ActionBar.new()
	action_bar.resources = resources
	action_bar.position = Vector2(412, 900 - 2 * 84 - 10)
	action_bar.size = Vector2(1600 - 412 - 16, 2 * 84)
	_ui.add_child(action_bar)
	_help = Label.new()
	_help.position = Vector2(16, 12)
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.85))
	_help.add_theme_constant_override("outline_size", 4)
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ui.add_child(_help)
	_update_help()


func _update_help() -> void:
	_help.text = "SPACE replay demo   G grid: %s   C camera: %s   V speed: %s   1 move plan  2 sky layer  3 line of sight\nRight-drag / Q E rotate   wheel zoom   WASD pan" % [
		"HEX" if shape == GridLayout.Shape.HEX else "SQUARE", view.camera_mode.to_upper(), ["FULL", "QUICK", "INSTANT"][_speed_i]]


func _build_board() -> void:
	var map := DemoMap.build(shape)
	view.set_map(map)
	view.clear_units()
	for id: String in ROSTER:
		var r: Array = ROSTER[id]
		var frame := content.frame(r[0])
		var cell := DemoMap.cell_at(map, r[2], r[3])
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
		mv.face(Vector3(8, 0, 6) if mv.unit["side"] == "players" else Vector3(8, 0, 11))
	view.tactical.look_at_point(Vector3(7.5, 0.8, 7.0), 15.0)
	view.tactical.snap()
	_update_help()
	resources.set_data(sample_resources())
	resources.position = Vector2(16, 900 - 314)
	action_bar.set_actions(sample_actions())
	hud.battle = view
	hud.unit_id = "everest"
	hud.target_id = "goblin"
	hud.weapon_name = "Assault Rifle"
	hud.weapon_range = "RANGE 10   ·   1d6 KINETIC"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("demo_replay") and not _running:
		_build_board()
		combat_log.clear_log()
		_run_demo()
	elif event.is_action_pressed("toggle_grid_shape") and not _running:
		shape = GridLayout.Shape.SQUARE if shape == GridLayout.Shape.HEX else GridLayout.Shape.HEX
		_build_board()
	elif event.is_action_pressed("cam_toggle"):
		_toggle_camera()
	elif event.is_action_pressed("roll_speed"):
		_speed_i = (_speed_i + 1) % 3
		Fx.speed = [EventPlayer.SPEED_FULL, EventPlayer.SPEED_QUICK, EventPlayer.SPEED_INSTANT][_speed_i]
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				view.overlays.show_plan(move_plan())
			KEY_2:
				view.overlays.show_plan(sky_plan(3))
			KEY_3:
				view.overlays.show_plan(los_plan())
			KEY_0:
				view.overlays.clear()
	_update_help()


func _toggle_camera() -> void:
	var cockpit := view.camera_mode == "tactical"
	if cockpit:
		view.set_camera_mode("cockpit", "everest", "goblin")
	else:
		view.set_camera_mode("tactical")
	hud.visible = cockpit
	resources.visible = not cockpit


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
		{"type": "moved", "unit": "blackbeard", "path": _path(_cell("blackbeard"), DemoMap.cell_at(view.map, 10.0, 6.4)), "mode": "boost"},
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

## tools/screenshot.gd hook. Pass "all" (or tag names) after the frame count; out path
## must contain %s. Tags: board square move sky los roll kinetic beam missile melee tech
## deploy heat vent destroy cockpit.
func screenshot_setup(args: PackedStringArray) -> Array:
	var tags: Array = Array(args)
	if tags.is_empty() or tags[0] == "all":
		tags = ["board", "square", "move", "sky", "los", "roll", "kinetic", "beam", "missile", "melee", "tech", "deploy", "heat", "vent", "destroy", "cockpit", "hud"]
	return tags


func screenshot_stage(tag: String) -> void:
	view.overlays.clear()
	player.cancel()
	rolls.clear_now()
	rolls.hold_result = false
	player.rolls = null
	if view.camera_mode != "tactical":
		_toggle_camera()
	for c in view.fx_root.get_children():
		c.queue_free()
	player.lasting.clear()
	shape = GridLayout.Shape.SQUARE if tag == "square" else GridLayout.Shape.HEX
	_build_board()
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
			rolls.hold_result = true
			player.rolls = rolls
			Fx.speed = 4.0
			_focus_for("kinetic")
			view.tactical.snap()
			await player.play([ev["kinetic"][0]])
			Fx.speed = 1.0
		"kinetic", "beam", "missile", "melee", "tech":
			_focus_for(tag)
			view.tactical.snap()
			var delays := {"kinetic": 0.42, "beam": 0.9, "missile": 1.12, "melee": 0.52, "tech": 0.95}
			var list: Array = ev[tag]
			if tag == "beam":
				list = [ev["beam"][1]]
			elif tag == "melee":
				await player.play([ev["melee"][0]])
				list = [ev["melee"][1]]
			elif tag == "missile":
				list = [ev["missile"][0]]
			player.play(list)
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
		"destroy":
			_focus_for("destroy")
			view.tactical.snap()
			player.play(ev["structure"] + ev["destroy"])
			await Fx.wait(self, 3.4)
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
