extends TestCase
## Attacking and destroying terrain (Core p.68 Objects and Damage): TerrainDamage.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var a: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(unit: Unit = null) -> void:
	s = F.state()
	e = RulesEngine.new()
	if unit == null:
		a = F.mech(s, "a", "players", Vector2i(0, 0))
	else:
		a = unit
		a.side = "players"
		s.add_unit(a)
	F.mech(s, "foe", "enemies", Vector2i(11, 11))
	s.map.set_column(Vector2i(3, 0), 1, PackedStringArray(["wall", BattleMap.TAG_DESTRUCTIBLE]))
	F.begin(e, s, a)


func _next_turn() -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = a.side
	F.act(e, s, "start_turn", a.id)


func test_shoot_a_wall_down() -> void:
	_setup()
	var info := RulesQueries.terrain_info(s, Vector2i(3, 0))
	expect_eq([info["hp"], info["evasion"], info["armor"], info["target"]], [10, 5, 0, "terrain:3,0"], "10 HP, Evasion 5 per Size 1 section")
	var pv := RulesQueries.attack_preview(s, "a", "0:0", "terrain:3,0")
	expect(pv["ok"], str(pv.get("reason", "")))
	expect_eq(pv["target_number"], 5)
	F.load_dice(s, [6, 6])  # 6 hits Evasion 5
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:3,0"})
	expect(F.ok(out), F.reason(out))
	expect_eq(TerrainDamage.hp_left(s, Vector2i(3, 0)), 4)
	expect(not s.units.has("terrain:3,0"), "the stand-in object is gone after the action")
	expect(GameState.from_dict(s.to_dict()).terrain_damage.has("3,0"), "damage is saved")
	_next_turn()
	F.load_dice(s, [10, 5])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:3,0"})
	var gone := F.events_of(out, "terrain_destroyed")
	expect_eq(gone.size(), 1)
	expect_eq(gone[0]["cells"], [[3, 0, 0]], "cells with their new heights")
	var col := s.map.column(Vector2i(3, 0))
	expect_eq(col.ground, 0)
	expect(not col.has_tag(BattleMap.TAG_DESTRUCTIBLE) and not col.has_tag(BattleMap.TAG_DIFFICULT), "no rubble rule in the book")
	# The map state remembers what's gone (for drawing the rubble), and clients get it.
	expect(int(s.terrain_lost.get("3,0", 0)) >= 1 and int(gone[0].get("lost", 0)) >= 1, "sections lost are recorded")
	expect_eq(int(GameState.from_dict(s.to_dict()).terrain_lost.get("3,0", 0)), int(s.terrain_lost["3,0"]), "and saved")
	expect_eq(TerrainDamage.damage_state(s, Vector2i(3, 0))["sections_lost"], int(s.terrain_lost["3,0"]), "damage_state reads it")
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:3,0"})), "nothing left to hit")


func test_armor_and_waived_terrain() -> void:
	_setup()
	s.map.set_column(Vector2i(3, 0), 2, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE, "armor_2"]))
	F.load_dice(s, [10, 5])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:3,0"})
	expect_eq(TerrainDamage.hp_left(s, Vector2i(3, 0)), 7, "Armor 2 (solid rock)")
	s.map.set_column(Vector2i(2, 2), 2, PackedStringArray(["rock"]))
	expect(TerrainDamage.info(s, Vector2i(2, 2)).is_empty(), "not destructible: the GM waived the rule")
	_next_turn()
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:2,2"})))


func test_sections_and_falling() -> void:
	_setup()
	s.map.set_column(Vector2i(3, 0), 3, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE, "floor_1"]))
	var b := F.mech(s, "b", "players", Vector2i(3, 0))
	expect_eq(b.level, 3)
	var ev := TerrainDamage.damage_cell(s, Vector2i(3, 0), 12, "Kinetic", false, "test")
	expect_eq(s.map.ground_height(Vector2i(3, 0)), 2, "one Size 1 section at a time; no carry-over")
	expect(F.events_of({"events": ev}, "falling").size() == 1, "the mech on top falls")
	TerrainDamage.damage_area(s, [[3, 0]], 10, "Energy", true, "test")
	expect_eq(s.map.ground_height(Vector2i(3, 0)), 1, "down to its floor, no lower")
	expect(TerrainDamage.info(s, Vector2i(3, 0)).is_empty())


func test_siege_ram_and_breach_grenade() -> void:
	_setup(UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": ["ms_siege_ram", "ms_bb_breach_blast_charges"]}, {"ll": 6}))
	a.cell = Vector2i(2, 0)
	F.load_dice(s, [15])
	var out := F.act(e, s, "ram", "a", {"target": "terrain:3,0"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "terrain_destroyed").size(), 1, "Siege Ram: 10 AP to objects and terrain")
	_next_turn()
	s.map.set_column(Vector2i(6, 1), 2, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE]))
	var key := ""
	for x: Dictionary in Abilities.all(a):
		if x["name"] == "Thermal Grenade":
			key = x["key"]
	out = F.act(e, s, "activate", "a", {"ability": key, "aim": [6, 1]})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.map.ground_height(Vector2i(6, 1)), 0, "objects in the blast are hit automatically: 10 AP to each section")


func test_jackhammer() -> void:
	_setup(UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_mortar"]}], "systems": []}, {"ll": 6, "talents": {"t_siege_specialist": 1}}))
	var near := F.mech(s, "near", "enemies", Vector2i(4, 0))
	var key := ""
	for x: Dictionary in Abilities.all(a):
		if x["name"] == "Jackhammer Round":
			key = x["key"]
	expect(key != "", "the talent's action")
	var out := F.act(e, s, "activate", "a", {"ability": key, "target": "terrain:3,0"})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.map.ground_height(Vector2i(3, 0)), 0, "10 AP kinetic, automatically")
	expect_eq(near.hp, 8, "2 kinetic to characters next to it")
	expect_eq(near.cell, Vector2i(6, 0), "knocked back 2 spaces from it")


func test_rammed_into_a_wall() -> void:
	_setup(UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []}, {"ll": 6, "talents": {"t_juggernaut": 2}}))
	a.cell = Vector2i(1, 0)
	var t := F.mech(s, "t", "enemies", Vector2i(2, 0))
	t.max_hp = 20
	t.hp = 20
	F.load_dice(s, [15, 4])
	var out := F.act(e, s, "ram", "a", {"target": "t", "knockback": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(2, 0), "the wall stops the knockback")
	expect_eq(t.hp, 16, "Kinetic Mass Transfer: 1d6 kinetic")


func test_apocalypse_rail_hits_objects() -> void:
	_setup()
	s.map.set_column(Vector2i(5, 5), 3, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE]))
	var w := {"id": FrameSystems.RAIL, "profile": 2}
	var ev := TerrainDamage.after_area(s, a, w, [[5, 5]])
	expect_eq(s.map.ground_height(Vector2i(5, 5)), 0, "Charge Rail 2: 40 AP to objects and terrain in the area")
	expect_eq(F.events_of({"events": ev}, "terrain_destroyed")[0]["cells"], [[5, 5, 0]])


func test_materials_and_hp_tags() -> void:
	_setup()
	s.map.set_column(Vector2i(3, 0), 1, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE, "material:fortified"]))
	expect_eq(TerrainDamage.info(s, Vector2i(3, 0))["armor"], 4, "fortified: Armor 4")
	F.load_dice(s, [10, 4])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "terrain:3,0"})
	expect_eq(TerrainDamage.hp_left(s, Vector2i(3, 0)), 10, "a 4-damage shot bounces off")
	TerrainDamage.damage_cell(s, Vector2i(3, 0), 4, "Kinetic", true, "test")
	expect_eq(TerrainDamage.hp_left(s, Vector2i(3, 0)), 6, "AP gets through")
	s.map.set_column(Vector2i(5, 5), 1, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE, "material:wood", "hp_20", "armor_1"]))
	var info := TerrainDamage.info(s, Vector2i(5, 5))
	expect_eq([info["armor"], info["max_hp"]], [1, 20], "explicit armor_N wins over the material; hp_N sets the section HP")


func test_portable_bunker_has_40_hp() -> void:
	_setup()
	var ev := Zones.add(s, {"kind": "bunker", "owner": "foe", "label": "Portable Bunker", "center": [6, 6], "cells": [[6, 6]], "phase": "up"})
	var zid := String(Zones.of_kind(s, "bunker")[0]["id"])
	F.load_dice(s, [10, 6])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "zone:" + zid})
	expect(F.ok(out), F.reason(out))
	expect_eq(int(Zones.of_kind(s, "bunker")[0]["hp"]), 34, "40 HP, Evasion 5")
	Zones.of_kind(s, "bunker")[0]["hp"] = 3
	_next_turn()
	F.load_dice(s, [10, 6])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "zone:" + zid})
	expect(Zones.of_kind(s, "bunker").is_empty(), "destroyed")
