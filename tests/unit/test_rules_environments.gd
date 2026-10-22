extends TestCase
## Rules environments (Core: Environments, lancer-data environments.json): state.environments.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(envs: Array, t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	s.environments = envs
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 30
	t.hp = 30
	F.begin(e, s, a)


func _end(u: Unit) -> Dictionary:
	return F.act(e, s, "end_turn", u.id)


func test_standing_effects() -> void:
	_setup(["env_extremecold", "env_thinatmosphere", "env_particulatestorms", "env_disruptivestorms"])
	expect(Effects.resists(a, "Heat", false, -1), "extreme cold: mechs resist heat")
	expect(Effects.resists(a, "Explosive", false, -1), "thin atmosphere")
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["cover"]["cover"], "soft", "particulate storm: mechs always have soft cover")
	var check := Combat.skill_check(s, a, "systems", "test", 10, 0, 0, [], true)
	expect_eq((check["sources"] as Array).filter(func(x: Dictionary) -> bool: return x["label"] == "Disruptive storm").size(), 1, "disruptive storm: +1 Difficulty on Systems saves")
	s.environments = []
	Environments.sync(s)
	expect(not Effects.resists(a, "Heat", false, -1), "gone with the environment")


func test_extreme_cold_freezes_still_mechs() -> void:
	_setup(["env_extremecold"])
	_end(a)
	expect(a.has_status("Immobilized"), "didn't move or Boost")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	F.load_dice(s, [5])
	expect(F.ok(F.act(e, s, "break_ice", "a")))
	expect(a.has_status("Immobilized"), "failed the Hull save")
	F.act(e, s, "move", "a", {"to": [0, 1]})
	expect_eq(a.cell, Vector2i(0, 0), "still frozen")
	_end(a)
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	F.load_dice(s, [15])
	expect(F.ok(F.act(e, s, "break_ice", "a")), "a quick action Hull save")
	expect(not a.has_status("Immobilized"))
	expect(not F.ok(F.act(e, s, "break_ice", "a")), "nothing to break")


func test_extreme_heat_and_corrosive() -> void:
	_setup(["env_extremeheat", "env_corrosiveatmosphere"])
	Combat.deal_damage(s, t, [{"type": "Heat", "amount": 2}], {"source": "a"})
	expect_eq(t.heat, 3, "+1 heat from a character's weapon or system")
	t.armor = 2
	F.load_dice(s, [15, 4])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "damage_dealt")[0]["amount"], 4, "all weapons gain AP: armor ignored")


func test_dangerous_storm_and_shelter() -> void:
	_setup(["env_dangeroustorms"])
	var out := _end(a)
	expect_eq(a.hp, 8, "2 energy (AP) out in the open")
	s.map.set_column(Vector2i(4, 1), 2, PackedStringArray())
	t.level = 0
	F.act(e, s, "start_turn", "t")
	out = _end(t)
	expect_eq(t.hp, 30, "next to terrain tall enough for hard cover")


func test_extreme_sun_shade_and_ruling() -> void:
	_setup(["env_extremesun"])
	F.load_dice(s, [4])
	_end(a)
	expect_eq(a.heat, 4, "1d6 heat in the sun at the end of its own turn")
	expect_eq(t.heat, 0, "the table's ruling: only the character whose turn ended")
	s.map.set_column(Vector2i(4, 0), 0, PackedStringArray(["shade"]))
	F.act(e, s, "start_turn", "t")
	_end(t)
	expect_eq(t.heat, 0, "in shade")


func test_electrical_storm_and_earthquake() -> void:
	_setup(["env_electricalstorms", "env_earthquakes"])
	_end(a)
	F.act(e, s, "start_turn", "t")
	# End of round: lightning picks unit 1 of [a, t] (a), Engineering save 3 + 0 - 1 Difficulty
	# fails; the earthquake die is 1, Hull saves: a 2 fails, t 18 passes.
	F.load_dice(s, [1, 3, 1, 1, 2, 18])
	var out := _end(t)
	expect(a.has_status("Stunned"), "struck by lightning")
	expect(a.has_status("Prone"), "knocked down by the quake")
	expect(not t.has_status("Prone"))
	expect_eq(F.events_of(out, "environment_roll").size(), 1)


func test_gravity() -> void:
	_setup(["env_highgravity"])
	expect(not F.ok(F.act(e, s, "boost", "a", {"to": [1, 0]})), "high gravity: no Boost")
	Combat.add_status(s, t, "Slowed", "test")
	expect(t.has_status("Immobilized") and not t.has_status("Slowed"), "Immobilized instead of Slowed")
	_setup(["env_lowgravity"])
	expect(Effects.has(a, "boost_flight"), "mechs fly when they Boost")
	a.level = 6
	a.counters["falling"] = true
	var hp := a.hp
	Combat.fall_unit(s, a)
	expect_eq(a.hp, hp, "no falling damage")


func test_ocean_world() -> void:
	_setup(["env_oceanworld"])
	var plan := Movement.plan(s, a, Vector2i(2, 0))
	expect_eq(plan["cost"], 4, "every space counts as difficult underwater")
	a.loadout["systems"] = [{"key": "s0", "id": "ms_eva_module", "name": "EVA Module"}]
	expect_eq(Movement.plan(s, a, Vector2i(2, 0))["cost"], 2, "an EVA Module moves normally")


func test_molten_world() -> void:
	_setup(["env_moltenworld"])
	s.map.set_column(Vector2i(1, 0), 0, PackedStringArray(["dangerous", "lava"]))
	s.map.set_column(Vector2i(2, 0), 0, PackedStringArray(["dangerous", "lava"]))
	F.load_dice(s, [20])  # the dangerous terrain check
	F.act(e, s, "move", "a", {"to": [1, 0]})
	expect_eq(a.hp, 5, "5 energy (AP)")
	expect_eq(a.heat, 3)
	F.act(e, s, "move", "a", {"to": [2, 0]})
	expect_eq(a.hp, 5, "only the first time on its turn")


func test_sinking_world() -> void:
	_setup(["env_sinkingworld"])
	_end(a)
	expect(a.has_status("Slowed"), "moved 1 space or less")
	F.act(e, s, "start_turn", "t")
	F.act(e, s, "move", "t", {"to": [5, 0]})
	F.act(e, s, "move", "t", {"to": [6, 0]})
	_end(t)
	expect(not t.has_status("Slowed"), "moved 2 spaces")
	F.act(e, s, "start_turn", "a")
	_end(a)
	expect(a.has_status("Immobilized") and Environments.sinking(a), "Slowed and still: sinking")
	var b := F.mech(s, "b", "players", Vector2i(1, 0))
	F.act(e, s, "start_turn", "t")
	_end(t)
	F.act(e, s, "start_turn", "b")
	F.load_dice(s, [15])
	var out := F.act(e, s, "dig_out", "b", {"target": "a"})
	expect(F.ok(out), F.reason(out))
	expect(not a.has_status("Immobilized") and not a.has_status("Slowed"), "an adjacent mech pulled it out")


func test_hostile_flora() -> void:
	_setup(["env_dangerousflorafauna"])
	var f := Environments.make_flora("flora1", Vector2i(3, 2))
	s.add_unit(f)
	expect(not TurnRules.takes_turns(f), "immobile, takes no turns")
	F.load_dice(s, [3])  # Hull save fails
	F.act(e, s, "move", "a", {"to": [2, 2]})
	expect_eq(a.hp, 7, "3 kinetic")
	expect(a.has_status("Immobilized"))
	Combat.deal_damage(s, f, [{"type": "Kinetic", "amount": 5}])
	Environments.release_flora(s)
	expect(not a.has_status("Immobilized"), "free once the flora is destroyed")


func test_pilots_in_particulate_storm() -> void:
	_setup(["env_particulatestorms"])
	var p := Unit.new()
	p.id = "p"
	p.kind = Unit.KIND_PILOT
	p.side = "players"
	p.cell = Vector2i(0, 3)
	p.max_hp = 6
	p.hp = 6
	s.add_unit(p)
	_end(a)
	s.turn_side = "players"
	F.act(e, s, "start_turn", "p")
	_end(p)
	expect_eq(p.hp, 5, "1 kinetic (AP) each turn outside a mech")


func test_generated_molten_map_has_lava_the_rules_read() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var map := TerrainGen.generate(rng, 30, 26, GridLayout.Shape.SQUARE, {}, "molten_world", "")
	var lava: Array[Vector2i] = []
	for c in map.cells():
		if map.column(c).has_tag("lava"):
			lava.append(c)
	expect(not lava.is_empty(), "the world generator tags lava")
	_setup(["env_moltenworld"])
	s.map = map
	a.cell = lava[0]
	a.level = map.ground_height(lava[0])
	expect(Environments.in_lava(s, a), "the molten-world rule reads the generator's lava tag")
	s.map.column(lava[0]).tags = PackedStringArray(["molten"])
	expect(Environments.in_lava(s, a), "a 'molten' tag counts too")
