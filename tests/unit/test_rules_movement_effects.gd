extends TestCase
## Movement granted or changed by traits, core systems, systems, talents and core bonuses.
## Only rule text grants movement; how a mech looks never does.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(effects: Array = [], t_cell := Vector2i(11, 11)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", t_cell)
	_give(a, effects)
	F.begin(e, s, a)


func _give(u: Unit, effects: Array) -> void:
	var list: Array = u.loadout.get("effects", [])
	for x: Dictionary in effects:
		var c := x.duplicate()
		c["label"] = c.get("label", "test effect")
		list.append(c)
	u.loadout["effects"] = list


func _next_turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_looks_never_grant_flight() -> void:
	_setup()
	var out := F.act(e, s, "move", "a", {"to": [1, 0], "level": 2, "fly": true})
	expect(not F.ok(out), "no rule grants this mech flight")


func test_teleport_moves_ignore_walls_engagement_and_overwatch() -> void:
	_setup([{"kind": "teleport_moves", "label": "EX Slipstream Module"}], Vector2i(1, 1))
	for y in range(12):
		s.map.set_column(Vector2i(2, y), 5)
	t.controller = "seat2"
	Combat.refresh_engagement(s)
	var out := F.act(e, s, "move", "a", {"to": [3, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.cell, Vector2i(3, 0), "straight through a 5-high wall (Core p.63)")
	expect_eq(F.events_of(out, "reaction_offered").size(), 0, "teleporting doesn't provoke")
	expect_eq(F.events_of(out, "moved")[0]["mode"], "teleport")
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [4, 0]})), "PROVISIONAL: the teleport used the standard move")


func test_teleport_fails_into_occupied_or_midair_or_while_immobilized() -> void:
	_setup([{"kind": "teleport_moves"}], Vector2i(3, 0))
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [3, 0]})), "occupied: the teleport fails")
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [2, 0], "level": 2})), "can't end mid-air without flight")
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [5, 0]})), "out of range (Speed 4)")
	a.statuses["Immobilized"] = {"source": "x"}
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [2, 0]})), "still movement: Immobilized stops it")


func test_ignore_difficult_terrain() -> void:
	_setup([{"kind": "ignore_difficult", "label": "Bulwark Mods"}])
	for y in range(12):
		s.map.set_column(Vector2i(1, y), 0, PackedStringArray([BattleMap.TAG_DIFFICULT]))
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(2, 0))["cost"], 2)


func test_climb_at_normal_speed() -> void:
	_setup([{"kind": "climb_normal", "label": "High-Stress Mag Clamps"}])
	s.map.set_column(Vector2i(1, 0), 2)
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(1, 0))["cost"], 3, "1 step + 1 per level instead of 2")


func test_kai_bioplating_jumps() -> void:
	_setup([{"kind": "jump_plus", "label": "Kai Bioplating"}])
	expect(F.ok(F.act(e, s, "jump", "a", {"to": [0, 4]})), "full Speed across")
	_setup([{"kind": "jump_plus", "label": "Kai Bioplating"}])
	s.map.set_column(Vector2i(1, 0), 2)
	var out := F.act(e, s, "jump", "a", {"to": [1, 0], "vertical": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.level, 2, "up to half Speed")


func test_optional_flight_costs_heat_only_on_turns_flown() -> void:
	_setup([{"kind": "optional_flight", "heat": "size+1", "label": "Type-I Flight System"}])
	expect(F.ok(F.act(e, s, "move", "a", {"to": [1, 0], "level": 2, "fly": true})))
	F.act(e, s, "end_turn", "a")
	expect_eq(a.heat, 2, "Size 1 + 1 heat")
	_setup([{"kind": "optional_flight", "heat": 1, "label": "All-Theater Movement Suite"}])
	F.act(e, s, "move", "a", {"to": [1, 0]})
	F.act(e, s, "end_turn", "a")
	expect_eq(a.heat, 0, "didn't fly this turn: no heat")


func test_jump_jets_fly_only_on_boost_and_must_land() -> void:
	_setup([{"kind": "boost_flight", "label": "Rapid Burst Jump Jet System"}])
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [1, 0], "level": 2, "fly": true})), "a standard move can't fly")
	var out := F.act(e, s, "boost", "a", {"to": [2, 0], "level": 3, "fly": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.level, 0, "ended mid-air: falls at once")
	expect_eq(a.hp, 7, "3 spaces: 3 AP kinetic")


func test_boost_bonus() -> void:
	_setup([{"kind": "boost_bonus", "value": 2, "label": "Integrated Nerveweave"}])
	F.act(e, s, "move", "a", {"to": [4, 0]})
	expect(F.ok(F.act(e, s, "boost", "a", {"to": [10, 0]})), "Speed 4 + 2")


func test_nelson_skirmisher_move_after_attacking() -> void:
	_setup([{"kind": "after_attack_move", "spaces": 1, "after": "attack", "label": "Skirmisher"}], Vector2i(1, 0))
	Combat.refresh_engagement(s)
	expect(not F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 1]})), "only right after an attack")
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var out := F.act(e, s, "bonus_move", "a", {"to": [0, 1]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "reaction_offered").size(), 0, "doesn't provoke")
	expect(not F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 2]})), "once")


func test_bonus_move_lost_after_another_action_and_blocked_by_slowed() -> void:
	_setup([{"kind": "after_attack_move", "spaces": 4, "after": "attack", "label": "Perpetual Momentum Drive"}], Vector2i(5, 0))
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(RulesQueries.preview_move(s, "a", Vector2i(0, 4), -1, "bonus")["ok"], "4 spaces with the core")
	F.act(e, s, "lock_on", "a", {"target": "t"})
	expect(not F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 1]})), "must be taken immediately")
	_next_turn(a)
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	a.statuses["Slowed"] = {"source": "x"}
	expect(not F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 1]})), "Slowed: no special moves")


func test_skirmisher_talent_only_after_skirmish() -> void:
	_setup([{"kind": "after_attack_move", "spaces": 2, "after": "skirmish", "label": "Skirmisher II"}], Vector2i(1, 0))
	F.load_dice(s, [2])
	F.act(e, s, "improvised_attack", "a", {"target": "t"})
	expect(not F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 1]})), "not after an Improvised Attack")
	_next_turn(a)
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.ok(F.act(e, s, "bonus_move", "a", {"to": [0, 2]})), "2 spaces after a Skirmish")


func test_swallowtail_cloak_when_still() -> void:
	_setup([{"kind": "status_if_still", "status": "Invisible", "label": "Integrated Cloak"}])
	F.act(e, s, "end_turn", "a")
	expect(a.has_status("Invisible"), "didn't move: Invisible")
	_next_turn(a)
	expect(not a.has_status("Invisible"), "until the start of its next turn")
	F.act(e, s, "move", "a", {"to": [1, 0]})
	F.act(e, s, "end_turn", "a")
	expect(not a.has_status("Invisible"), "moved: no cloak")


func test_flicker_field_afterimage() -> void:
	_setup([{"kind": "afterimage", "label": "Flicker Field Projector"}], Vector2i(5, 0))
	F.act(e, s, "move", "a", {"to": [1, 0]})
	_next_turn(t)
	F.load_dice(s, [1])
	var out := F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect(F.events_of(out, "attack_rolled")[0]["invisible_miss"], "counts as Invisible for one attack")
	expect(not a.counters.has("afterimage"), "used up")


func test_iskander_seeder_punishes_non_standard_moves() -> void:
	_setup([], Vector2i(9, 9))
	_give(t, [{"kind": "punish_movement", "damage": 3, "range": 50, "label": "Broad-Sweep Seeder"}])
	F.act(e, s, "move", "a", {"to": [1, 0]})
	expect_eq(a.hp, 10, "a standard move is fine")
	F.act(e, s, "boost", "a", {"to": [3, 0]})
	expect_eq(a.hp, 7, "Boost: 3 AP explosive")
	Attacks.knock_back(s, a, Vector2i(2, 0), 1)
	expect_eq(a.hp, 7, "1/round")


func test_ace_agility_while_flying() -> void:
	_setup([{"kind": "accuracy", "on": "save", "skill": "agility", "value": 1, "while_flying": true, "label": "Ace"}])
	var labels := func(c: Dictionary) -> Array: return (c["sources"] as Array).map(func(x: Dictionary) -> String: return x["label"])
	expect(not labels.call(Combat.skill_check(s, a, "agility", "x", 10, 0, 0, [], true)).has("Ace"))
	a.flying = true
	expect(labels.call(Combat.skill_check(s, a, "agility", "x", 10, 0, 0, [], true)).has("Ace"))


func test_factory_reads_systems_core_bonuses_and_talents() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": ["ms_bulwark_mods", "ms_type_i_flight_system"]}
	var u := UnitFactory.build_mech(db(), "u", "mf_standard_pattern_i_everest", loadout,
		{"ll": 6, "core_bonuses": ["cb_integrated_nerveweave", "cb_fomorian_frame"], "talents": {"t_skirmisher": 2}})
	expect(Effects.has(u, "ignore_difficult"), "Bulwark Mods")
	expect(Effects.has(u, "optional_flight"), "Type-I Flight System")
	expect_eq(Effects.value(u, "boost_bonus"), 2, "Integrated Nerveweave")
	expect_eq(u.size, 2.0, "Fomorian Frame: one Size larger")
	expect(Effects.has(u, "heavy_frame"))
	expect(Effects.has(u, "after_attack_move"), "Skirmisher rank II")
	var ev := UnitFactory.build_mech(db(), "v", "mf_standard_pattern_i_everest", {}, {"ll": 0})
	expect(not Effects.has(ev, "optional_flight"), "a plain Everest gets no movement extras")


func test_frame_cores_and_traits_from_data() -> void:
	var nelson := UnitFactory.build_mech(db(), "n", "mf_nelson", {})
	expect_eq(Effects.value(nelson, "after_attack_move", "spaces"), 1, "Skirmisher trait")
	var cores: Array = nelson.loadout["core"]["effects"]
	expect(cores.any(func(x: Dictionary) -> bool: return x["kind"] == "after_attack_move" and x["spaces"] == 4))
	var mc := UnitFactory.build_mech(db(), "m", "mf_mourning_cloak", {})
	expect(mc.loadout["core"]["effects"].any(func(x: Dictionary) -> bool: return x["kind"] == "teleport_moves"))
	var sw := UnitFactory.build_mech(db(), "s", "mf_swallowtail", {})
	expect(Effects.has(sw, "status_if_still"))
	var dw := UnitFactory.build_mech(db(), "d", "mf_dusk_wing", {})
	expect_eq(dw.flight, "hover", "Dusk Wing: 'can hover when it moves'")
	var bal := UnitFactory.build_mech(db(), "b", "mf_balor", {})
	expect_eq(bal.flight, "", "no frame flies just because of its look")


func test_mobility_hardsuit_pilot_must_land() -> void:
	var p := UnitFactory.build_pilot(db(), "pp", {"name": "Ace", "gear": ["pg_mobility_hardsuit"]})
	expect(Effects.has(p, "optional_flight"))
	s = F.state()
	e = RulesEngine.new()
	p.cell = Vector2i(0, 0)
	s.add_unit(p)
	F.mech(s, "t", "enemies", Vector2i(11, 11))
	F.begin(e, s, p)
	expect(F.ok(F.act(e, s, "move", "pp", {"to": [1, 0], "level": 3, "fly": true})))
	F.act(e, s, "end_turn", "pp")
	expect_eq(p.level, 0, "must end the turn on a surface, or fall")


func test_knockback_passes_smaller_characters_but_not_obstructions() -> void:
	_setup([], Vector2i(1, 0))
	var small := F.mech(s, "small", "players", Vector2i(2, 0), 0.5)
	Attacks.knock_back(s, t, Vector2i(0, 0), 2)
	expect_eq(t.cell, Vector2i(3, 0), "through the smaller character, ending past it (Core p.62)")
	small.size = 1.0
	small.cell = Vector2i(4, 0)
	Attacks.knock_back(s, t, Vector2i(0, 0), 3)
	expect_eq(t.cell, Vector2i(3, 0), "a same-Size character is an obstruction")


func test_minotaur_maze_blocks_even_bigger_hostiles() -> void:
	s = F.state(GridLayout.Shape.SQUARE, 8, 2)
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0), 2.0)
	t = F.mech(s, "t", "enemies", Vector2i(2, 0))
	a.speed = 6
	F.begin(e, s, a)
	expect(RulesQueries.preview_move(s, "a", Vector2i(3, 0))["ok"], "a Size 2 can pass a smaller hostile")
	_give(t, [{"kind": "maze", "label": "Localized Maze"}])
	expect(not RulesQueries.preview_move(s, "a", Vector2i(3, 0))["ok"], "but never through a Minotaur")
