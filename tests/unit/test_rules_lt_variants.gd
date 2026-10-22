extends TestCase
## Lancer Tactics variants (DESIGN.md "Rule differences"): the book by default, LT on request.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(lt: Array) -> void:
	s = F.state()
	for id: String in lt:
		s.house_rules[id] = true
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	a.loadout["weapons"].append(F.weapon("1:0", "Pistol", "Auxiliary", "CQB", "1d3", 5))
	t = F.mech(s, "t", "enemies", Vector2i(3, 0))
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func test_defaults_follow_the_users_picks() -> void:
	var fresh := GameState.new(1)
	expect(Rulings.lancer_tactics(fresh, "lt_split_barrage"), "split Barrage on for new campaigns")
	expect(Rulings.lancer_tactics(fresh, "lt_brace_prompt"), "LT Brace prompt on")
	expect(not Rulings.lancer_tactics(fresh, "lt_repeat_quick_tech"), "Quick Tech stays book")
	_setup([])
	F.load_dice(s, [15, 3, 15, 3])
	expect(F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})), "book: one Skirmish a turn")
	F.load_dice(s, [19, 1])
	F.act(e, s, "invade", "a", {"target": "t"})
	expect(not F.ok(F.act(e, s, "invade", "a", {"target": "t"})), "book: a different Quick Tech option")


func test_split_barrage() -> void:
	_setup(["lt_split_barrage"])
	F.load_dice(s, [15, 3])
	expect(F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})))
	expect(F.ok(F.act(e, s, "move", "a", {"to": [0, 1]})), "move between the shots")
	var again := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(not F.ok(again), "not the same mount twice")
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	expect(F.ok(out), F.reason(out))


func test_repeat_quick_tech() -> void:
	_setup(["lt_repeat_quick_tech"])
	F.load_dice(s, [19, 1])
	F.act(e, s, "invade", "a", {"target": "t"})
	F.load_dice(s, [19, 1])
	var out := F.act(e, s, "invade", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))


func test_brace_prompt() -> void:
	_setup(["lt_brace_prompt"])
	expect(not Attacks._brace_worthwhile(t, [{"type": "Kinetic", "amount": 5}], false), "a small hit: no prompt")
	expect(Attacks._brace_worthwhile(t, [{"type": "Kinetic", "amount": 21}], false), "more than half its HP")
	t.hp = 4
	expect(Attacks._brace_worthwhile(t, [{"type": "Kinetic", "amount": 4}], true), "would take it to 0 HP")
	t.heat = 5
	expect(Attacks._brace_worthwhile(t, [{"type": "Heat", "amount": 2}], false), "would overheat it")


func test_flight_fixed_and_aux_mount() -> void:
	_setup(["lt_flight_fixed", "lt_aux_mount"])
	a.flight = "flight"
	var out := F.act(e, s, "move", "a", {"to": [1, 2], "fly": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.level, 3, "flying: 3 spaces above the surface")
	var w := Weapons.find(a, "1:0")
	w["mount"] = 0
	expect(AttackActions.lt_aux_only(s, a, w), "an Aux on a mount with a Main: no bonus damage")
