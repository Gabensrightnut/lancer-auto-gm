extends TestCase
## Map editor: saved maps (MapDoc), the GM's battlefield actions (GmMapActions) and the
## editor's tools (MapEditorModel), before a mission and live during one.

const DIR := "user://test_maps/"


func _doc() -> MapDoc:
	return MapDoc.generated(3, 24, 20, GridLayout.Shape.HEX, "sitrep_control", "grassy_hills", "")


func test_map_doc_saves_and_loads() -> void:
	var d := _doc()
	d.name = "Ridge Line 2"
	d.culture = "medieval"
	d.weather = "rain"
	expect_eq(d.save(DIR), OK)
	expect(MapDoc.list(DIR).has("ridge_line_2"), "listed by its file-safe name")
	var back := MapDoc.load_named("Ridge Line 2", DIR)
	expect(back != null, "loads")
	expect_eq(JSON.stringify(back.map.to_dict()), JSON.stringify(d.map.to_dict()), "same terrain")
	expect_eq(back.kit(), "grassy_hills/medieval+rain")
	expect_eq(back.zones.keys().size(), 4, "control zones kept")
	expect_eq(typeof(back.zones["zone_1"][0][0]), TYPE_INT, "cells come back as ints")
	DirAccess.remove_absolute(DIR.path_join("ridge_line_2.json"))


func test_a_mission_can_use_a_saved_map() -> void:
	var d := _doc()
	var g := MissionGenerator.generate(5, {"map_doc": d, "db": preload("res://tests/unit/test_gm_mission.gd").db()})
	var s: GameState = g["state"]
	var m: Mission = g["mission"]
	expect_eq(m.sitrep_id, "sitrep_control", "the map's sitrep by default")
	for c in d.map.cells():
		expect_eq(s.map.ground_height(c), d.map.ground_height(c))
	expect_eq(JSON.stringify(m.zones), JSON.stringify(d.zones), "the map's own zones")
	expect(str(m.flavor["kit"]).begins_with("grassy_hills"), "the map's look")
	expect(s.units_on_side("players").size() > 0 and s.units_on_side("enemies").size() > 0, "forces deployed")


func test_gm_terrain_edit_goes_through_the_rules() -> void:
	var engine := RulesEngine.new()
	GmActions.register(engine)
	var s := GameState.new(1, GridLayout.Shape.SQUARE)
	s.map = BattleMap.flat(GridLayout.Shape.SQUARE, 10, 10)
	var u := Unit.new()
	u.id = "u1"
	u.cell = Vector2i(4, 4)
	u.size = 1
	s.add_unit(u)
	var ok := engine.submit(s, {"type": "gm_edit_terrain", "params": {"cells": [{"cell": [2, 2], "ground": 2, "tags": ["rock"]}]}})
	expect((ok["result"] as RuleResult).ok, "a GM raises a rock")
	expect_eq(s.map.ground_height(Vector2i(2, 2)), 2)
	expect_eq(str(ok["events"][0]["type"]), "terrain_edited")
	var bury := engine.submit(s, {"type": "gm_edit_terrain", "params": {"cells": [{"cell": [4, 4], "ground": 1}]}})
	expect(not (bury["result"] as RuleResult).ok, "can't bury a unit")
	var strand := engine.submit(s, {"type": "gm_edit_terrain", "params": {"cells": [{"cell": [4, 4], "tags": ["impassable"]}]}})
	expect(not (strand["result"] as RuleResult).ok, "can't make a unit's space impassable")
	var bad := engine.submit(s, {"type": "gm_edit_terrain", "params": {"cells": [{"cell": [1, 1], "tags": ["lava_monsters"]}]}})
	expect(not (bad["result"] as RuleResult).ok, "unknown tags refused")
	var off := engine.submit(s, {"type": "gm_edit_terrain", "params": {"cells": [{"cell": [40, 40], "ground": 1}]}})
	expect(not (off["result"] as RuleResult).ok, "off the map refused")


func test_gm_objective_edit_keeps_secrets_filtered() -> void:
	var engine := RulesEngine.new()
	GmActions.register(engine)
	var s := GameState.new(1, GridLayout.Shape.HEX)
	s.map = BattleMap.flat(GridLayout.Shape.HEX, 10, 10)
	s.objectives = {"sitrep": "sitrep_recon", "true_zone": "zone_2", "zones": {}, "deployment": {}}
	s.seats["p1"] = {"name": "P1", "side": "players"}
	var zones := {"zone_1": [[1, 1]], "zone_2": [[5, 5]]}
	var r := engine.submit(s, {"type": "gm_edit_objectives", "params": {"zones": zones, "deployment": {"players": [[0, 9]]}}})
	expect((r["result"] as RuleResult).ok)
	expect_eq(str(r["events"][0]["type"]), "objectives_changed")
	expect_eq((s.objectives["zones"] as Dictionary).size(), 2)
	var seen := ViewFilter.new().view_for(s, "p1")
	expect(not (seen.get("objectives", {}) as Dictionary).has("true_zone"), "the True Control Zone stays secret")


func test_editor_tools_before_a_mission() -> void:
	var m := MapEditorModel.new()
	m.start_prep(MapDoc.blank(20, 17, GridLayout.Shape.SQUARE, "sitrep_control"))
	var c := Vector2i(5, 5)
	m.paint([c], "raise")
	m.paint([c], "raise")
	expect_eq(m.state.map.ground_height(c), 2, "raise twice")
	m.paint([c], "destructible")
	m.preset = "rock"
	m.paint([c], "preset")
	expect(m.state.map.column(c).has_tag("rock") and m.state.map.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE), "presets keep breakable")
	m.paint([c], "sturdy")
	expect(not m.state.map.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE), "sturdy removes it")
	m.level_to = 0
	m.paint([c], "level")
	expect_eq(m.state.map.ground_height(c), 0)
	# Mirrored brush: point symmetry through the center.
	m.symmetric = true
	var cells := m.brush(Vector2i(2, 3), 0)
	expect(cells.has(Vector2i(17, 13)), "mirror of (2,3) on 20x17 is (17,13): %s" % [cells])
	# Zones.
	m.zone = "zone_9"
	m.paint([Vector2i(3, 3)], "zone")
	expect(m.doc.zones.has("zone_9") and m.state.objectives["zones"].has("zone_9"), "zone painted into the doc and the state")
	m.paint([Vector2i(3, 3)], "unzone")
	expect((m.doc.zones["zone_9"] as Array).is_empty(), "unzone removes it")
	# The fairness checker speaks plainly and warns.
	var lines := m.fairness_lines()
	expect(lines.size() >= 4, "fairness lines")
	m.set_objectives(m.doc.zones, {"players": [], "enemies": []})
	expect(not m.fairness_ok(), "no deployment zones is a warning")


func test_editor_live_edits_reach_the_mission_state() -> void:
	var g := MissionGenerator.generate(8, {"size": 20, "sitrep": "sitrep_control", "db": preload("res://tests/unit/test_gm_mission.gd").db()})
	var s: GameState = g["state"]
	var engine := RulesEngine.new()
	var m := MapEditorModel.new()
	m.start_live(engine, s)
	expect(m.live)
	expect_eq(m.doc.sitrep, "sitrep_control", "the mission's sitrep")
	var free_cell := Vector2i.ZERO
	var taken := {}
	for u: Unit in s.units.values():
		for c in s.map.grid.footprint(u.cell, u.size):
			taken[c] = true
	for c in s.map.cells():
		if not taken.has(c):
			free_cell = c
			break
	var before := s.map.ground_height(free_cell)
	var events := m.paint([free_cell], "raise")
	expect(not events.is_empty(), "a live edit applies: %s" % m.last_error)
	expect_eq(s.map.ground_height(free_cell), before + 1, "the mission's own map changed")
	var unit_cell: Vector2i = (s.units.values()[0] as Unit).cell
	expect(m.paint([unit_cell], "raise").is_empty() and m.last_error != "", "refused under a unit")
