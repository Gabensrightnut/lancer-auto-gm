extends TestCase
## Infantry: a squad shows ten men in its space, men fall as it loses HP (ceil(hp / max_hp * 10)),
## factions and crew paint set the colors, and a soldier is one man.


func test_men_left_follows_hp() -> void:
	var sq := {"kind": "squad", "hp": 4, "max_hp": 10}
	expect_eq(SquadModel.men_left(sq), 4, "4 of 10 HP: four standing")
	expect_eq(SquadModel.men_left({"kind": "squad", "hp": 1, "max_hp": 10}), 1, "one HP: one man left")
	expect_eq(SquadModel.men_left({"kind": "squad", "hp": 0, "max_hp": 10}), 0)
	expect_eq(SquadModel.men_left({"kind": "squad", "hp": 7.0, "max_hp": 20.0}), 4, "rounds up (network floats)")
	expect_eq(SquadModel.men_left({"kind": "squad", "men_left": 3.0, "hp": 9, "max_hp": 10}), 3, "the view's number wins")
	expect_eq(SquadModel.men_left({"kind": "soldier", "hp": 3, "max_hp": 5}), 1, "a single soldier")


func test_squad_formation_and_falling_men() -> void:
	var m := SquadModel.build({"id": "s1", "kind": "squad", "side": "enemies", "hp": 10, "max_hp": 10, "size": 1})
	expect_eq(m.figures.size(), 10, "ten men")
	for f in m.figures:
		expect(Vector2(f.position.x, f.position.z).length() < 0.5, "inside the space")
	m.set_men(4)
	expect_eq(m.standing().size(), 4, "six fell")
	m.set_men(6)
	expect_eq(m.standing().size(), 4, "the fallen stay down")
	m.free()
	var one := SquadModel.build({"id": "p", "kind": "soldier", "side": "players"})
	expect_eq(one.figures.size(), 1)
	one.free()


func test_faction_colors_and_crew_paint() -> void:
	expect_eq(SoldierFigure.faction_of({"faction": "pirate"}), "pirate")
	expect_eq(SoldierFigure.faction_of({"side": "players"}), "union", "by side when the unit doesn't say")
	var c := SoldierFigure.colors_for("union", {"primary": "#112233", "glow": "#00ff00"})
	expect_eq(String(c["uniform"]), "#112233", "the crew's paint colors the uniform")
	expect_eq(String(c["visor"]), "#00ff00")
	expect(c.has("armor") and c.has("trim"), "the rest from the faction")
	for f: String in SoldierFigure.data()["factions"]:
		var spec: Dictionary = SoldierFigure.data()["factions"][f]
		expect(String(spec["helmet"]).begins_with("Helmet_") and String(spec["armor"]).begins_with("Armor_"), "%s names its gear" % f)


func test_garrisoned_squad_shows_men_at_the_windows() -> void:
	var m := SquadModel.build({"id": "g", "kind": "squad", "side": "enemies", "hp": 10, "max_hp": 10})
	m.set_garrison("bldg_3")
	expect_eq(m.standing().size(), SquadModel.WINDOW_MEN, "a few men at the windows, the rest inside")
	m.set_garrison(null)
	expect_eq(m.standing().size(), 10, "out again: all in formation")
	m.free()
