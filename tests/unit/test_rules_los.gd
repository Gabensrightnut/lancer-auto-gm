extends TestCase
## Line of sight for attacks (Core p.64-66): seeing a target doesn't let a shot through a wall.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func test_a_wall_blocks_direct_fire_but_not_arcing() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 3)
	for y in range(3):
		s.map.set_column(Vector2i(5, y), 4, PackedStringArray(["wall"]))  # a wall across the map
	var a := F.mech(s, "a", "players", Vector2i(2, 1))
	a.loadout["weapons"] = [F.weapon("0:0", "Rifle"), F.weapon("1:0", "Mortar", "Main", "Cannon", "1d6", 10, [{"id": "tg_arcing"}])]
	F.mech(s, "t", "enemies", Vector2i(8, 1))
	s.intel["players"] = {"t": {"stats": true}}  # known and revealed: it still can't be shot through the wall
	var direct := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect(not direct["ok"] and String(direct["reason"]).contains("line of sight"), "direct fire refused: %s" % direct.get("reason", ""))
	expect(RulesQueries.attack_preview(s, "a", "1:0", "t")["ok"], "Arcing fires over it")
	var d := RulesQueries.los_detail(s, "a", "t")
	expect(not d["visible"] and d["blocked_at"] == [5, 1] and d["blocker"]["kind"] == "wall", "the line shows the wall: %s" % d)
