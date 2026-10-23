extends TestCase
## Deploying before the fight (Deployment): the sitreps' deployment order and zones.

const F = preload("res://tests/unit/test_rules_fixtures.gd")
const SoldierTest = preload("res://tests/unit/test_rules_soldiers.gd")


static func rows(y0: int, y1: int) -> Array:
	var out: Array = []
	for y in range(y0, y1 + 1):
		for x in range(12):
			out.append([x, y])
	return out


static func setup(sitrep: String) -> GameState:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 12)
	s.objectives = {"sitrep": sitrep, "deployment": {"players": rows(8, 11), "enemies": rows(0, 2)}, "zones": {"zone": [[6, 5], [6, 6]]}}
	F.mech(s, "m", "players", Vector2i(0, 10))
	F.mech(s, "e", "enemies", Vector2i(0, 0))
	return s


func test_gauntlet_gm_deploys_first_inside_the_zones() -> void:
	var s := setup("sitrep_gauntlet")
	var e := RulesEngine.new()
	var out := F.act(e, s, "deploy", "m", {"to": [5, 10]})
	expect(not F.ok(out) and F.reason(out).contains("GM"), "Gauntlet: the GM deploys first: " + F.reason(out))
	expect(F.ok(F.act(e, s, "deploy", "e", {"to": [3, 1]})))
	expect_eq(s.unit("e").cell, Vector2i(3, 1))
	expect(F.ok(F.act(e, s, "deploy", "e", {"to": [4, 1]})), "re-deploying is the same action")
	expect(F.ok(e.submit(s, {"type": "deployment_done", "params": {"side": "enemies"}})))
	out = F.act(e, s, "deploy", "m", {"to": [5, 5]})
	expect(not F.ok(out) and F.reason(out).contains("zone"), "outside the zone: " + F.reason(out))
	expect(F.ok(F.act(e, s, "deploy", "m", {"to": [5, 10]})))
	# A Size 4 squad needs its whole footprint in the zone.
	var sq := Soldiers.build(SoldierTest.db(), "sq", "rifle_squad", "players", 1, s)
	sq.cell = Vector2i(0, 4)
	s.add_unit(sq)
	expect(not F.ok(F.act(e, s, "deploy", "sq", {"to": [0, 9]})), "part of it would be outside")
	expect(F.ok(F.act(e, s, "deploy", "sq", {"to": [6, 8]})), "all 16 spaces inside")
	e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	expect(not F.ok(F.act(e, s, "deploy", "m", {"to": [6, 10]})), "no deploying once the fight starts")


func test_holdout_and_control_orders() -> void:
	var s := setup("sitrep_holdout")
	var e := RulesEngine.new()
	expect(not F.ok(F.act(e, s, "deploy", "e", {"to": [3, 1]})), "Holdout: the PCs deploy first")
	expect(F.ok(F.act(e, s, "deploy", "m", {"to": [6, 5]})), "Holdout: the PCs may deploy in the Control Zone")
	var c := setup("sitrep_control")
	F.load_dice(c, [2, 5])  # the GM rolls 2, the player 5: the GM deploys first
	expect(not F.ok(F.act(e, c, "deploy", "m", {"to": [5, 10]})), "Control: the lower roll deploys first")
	expect_eq(c.objectives["deploying"], "enemies")
