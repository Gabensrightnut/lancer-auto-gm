extends TestCase
## House rules (HouseRuleSwitches): off by default (the Lancer Tactics picks on), switchable
## between actions, each doing what its card says.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(on: Array = [], t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 30
	t.hp = 30
	F.begin(e, s, a)
	for id: String in on:
		expect(F.ok(e.submit(s, {"type": "set_house_rule", "params": {"id": id, "on": true}})), id)


func test_catalog_and_defaults() -> void:
	var fresh := GameState.new(1)
	for r: Dictionary in HouseRuleSwitches.listing(fresh):
		expect(r.has("source") and r.has("text") and r.has("name"), String(r["id"]))
		var expected: bool = r["id"] in ["lt_split_barrage", "lt_brace_prompt"]
		expect_eq(bool(r["on"]), expected, String(r["id"]) + " default")
	expect(HouseRuleSwitches.listing(fresh).size() >= 10)


func test_switch_mid_game() -> void:
	_setup()
	var out := e.submit(s, {"type": "set_house_rule", "params": {"id": "hr_fall_stun", "on": true}})
	expect(F.ok(out))
	expect_eq(F.events_of(out, "house_rule_changed")[0]["name"], "Stunned by a hard fall")
	expect(HouseRuleSwitches.on(s, "hr_fall_stun"))
	expect(GameState.from_dict(s.to_dict()).house_rules.get("hr_fall_stun", false), "saved with the game")
	expect(not F.ok(e.submit(s, {"type": "set_house_rule", "params": {"id": "nope", "on": true}})))


func test_fall_stun_and_brace_for_the_fall() -> void:
	_setup(["hr_fall_stun", "hr_brace_fall"])
	t.level = 6
	t.counters["falling"] = true
	F.load_dice(s, [3])  # the Hull save fails
	Combat.fall_unit(s, t)
	expect_eq(t.hp, 27, "braced: half of 6")
	expect(t.has_status("Stunned"), "a hard fall stuns")


func test_collapse_roll() -> void:
	_setup(["hr_collapse_save"])
	s.map.set_column(Vector2i(3, 3), 1, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE]))
	F.load_dice(s, [2])
	var ev := TerrainDamage.damage_cell(s, Vector2i(3, 3), 6, "Kinetic", true, "test")
	expect_eq(s.map.ground_height(Vector2i(3, 3)), 0, "a 6-damage hit and a 2 on the collapse roll: it comes down")
	expect_eq(F.events_of({"events": ev}, "collapse_roll").size(), 1)


func test_direct_hit_without_stun() -> void:
	_setup(["hr_structure_no_stun"])
	a.structure = 4
	Combat._direct_hit(s, a)
	expect(not a.has_status("Stunned"))
	expect(not Reactions.can_react(a, "overwatch", s).ok, "no reactions instead")
	expect(a.counters.get("brace_next_turn", false), "one quick action next turn")


func test_hide_behind_hard_cover() -> void:
	_setup([], Vector2i(4, 0))
	s.map.set_column(Vector2i(1, 0), 1, PackedStringArray())  # waist-high wall: hard cover, still seen
	expect_eq(Sight.unit_cover(s, t, a)["cover"], "hard")
	expect(not Combat.can_hide(s, a).ok, "book: in line of sight")
	F.act(e, s, "end_turn", "a")
	e.submit(s, {"type": "set_house_rule", "params": {"id": "hr_hide_hard_cover", "on": true}})
	expect(Combat.can_hide(s, a).ok, "house rule: hard cover is enough")


func test_overheated() -> void:
	_setup(["hr_overheated"])
	a.heat = 6
	a.loadout["weapons"].append(F.weapon("1:0", "Burner", "Main", "CQB", "1d6", 5, [{"id": "tg_heat_self", "val": 2}]))
	a.statuses["Exposed"] = {"source": "test"}
	Combat.overheated_check(s, a)
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})), "Overheated: no Heat (Self) weapons")
	expect(F.ok(F.act(e, s, "stabilize", "a", {"main": "cool", "extra": "reload"})))
	expect(not a.counters.has("overheated"), "cooled down")


func test_npc_recharge_heat() -> void:
	_setup(["hr_npc_recharge_heat"])
	t.kind = Unit.KIND_NPC
	var ab := {"key": "f0/a0", "name": "Burner", "source_key": "f0", "kind": "action", "activation": "Quick", "ops": [], "automated": true,
		"tags": [{"id": "tg_recharge", "val": 6}]}
	t.loadout["abilities"] = [ab]
	Abilities.spend(s, t, ab)
	expect_eq(int(t.turn.get("recharge_heat", 0)), 2, "Recharge 6+: 2 heat")
