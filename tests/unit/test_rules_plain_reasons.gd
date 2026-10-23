extends TestCase
## Refusals read as plain words for players; engine parameter hints go to RuleResult.hint.


func test_params_hints_are_kept_out_of_the_reason() -> void:
	var r := RuleResult.deny("Choose an allied character (params.target).", "systems: Metahook")
	expect_eq(r.reason, "Choose an allied character.")
	expect_eq(r.hint, "params.target")
	r = RuleResult.deny("Say where to move (params.to = [x, y]).", "Core p.62")
	expect_eq(r.reason, "Say where to move.")
	r = RuleResult.deny("Choose a space and a setting (params.setting: repulse or attract).", "systems: Perimeter Command Plate")
	expect_eq(r.reason, "Choose a space and a setting (repulse or attract).")
	r = RuleResult.deny("Say which drones go where (params.moves: [{drone, to}]).", "systems: Puppetmaster")
	expect_eq(r.reason, "Say which drones go where.")


func test_refusals_that_players_see_cite_a_rule() -> void:
	# Every refusal with a reason a player can meet in play names where the rule comes from.
	var s := preload("res://tests/unit/test_rules_fixtures.gd").state()
	var e := RulesEngine.new()
	var a := preload("res://tests/unit/test_rules_fixtures.gd").mech(s, "a", "players", Vector2i(0, 0))
	preload("res://tests/unit/test_rules_fixtures.gd").mech(s, "t", "enemies", Vector2i(9, 9))
	for type in ["move", "boost", "skirmish", "barrage", "ram", "grapple", "scan", "lock_on", "invade", "hide", "stabilize"]:
		var r := e.validate(s, {"type": type, "actor": "a", "params": {}})
		expect(r.ok or r.rule_ref != "", "%s: '%s' cites a rule" % [type, r.reason])
		expect(not r.reason.contains("params."), "%s: plain words" % type)
