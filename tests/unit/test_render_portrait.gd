extends TestCase
## Pilot portraits: every part option and expression draws, the creator edits the v2 format,
## locks survive randomize, and the token builds.


func test_every_option_and_expression_draws() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var base := PortraitSpec.randomize(rng)
	var pa := PortraitArt.new()
	pa.size = Vector2(200, 240)
	for p: Dictionary in PortraitSpec.parts():
		for opt: String in p.get("options", []):
			var look := base.duplicate(true)
			(look["parts"] as Dictionary)[String(p["id"])]["option"] = opt
			pa.set_look(look)
	for e: String in PortraitSpec.expression_ids():
		pa.set_look(base, e)
		expect(PortraitArt.EXPRESSIONS.has(pa.expression), "%s is drawn as itself" % e)
	pa.set_look({"skin": "#a16a45", "hair_style": "bun"}, "angry")
	expect_eq(pa.expression, "angry", "older flat looks work too")
	pa.free()


func test_creator_edits_and_locks() -> void:
	var pc := PilotCreator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	pc.open(PortraitSpec.randomize(rng))
	pc.select_part("hair")
	pc.set_option("mohawk")
	expect_eq(pc.get_portrait()["parts"]["hair"]["option"], "mohawk")
	pc.set_color(Color("b23a2c"))
	expect_eq(pc.get_portrait()["parts"]["hair"]["primary"], "#b23a2c")
	pc.select_part("face")
	pc.set_color(Color("5a3420"))
	expect_eq(pc.get_portrait()["parts"]["body"]["primary"], "#5a3420", "face and body share the skin tone")
	pc.toggle_lock("hair")
	for i in range(5):
		pc.randomize_all()
		expect_eq(pc.get_portrait()["parts"]["hair"]["option"], "mohawk", "locked hair stays")
	var got: Array = []
	pc.confirmed.connect(func(p: Dictionary) -> void: got.append(p))
	pc.confirmed.emit(pc.get_portrait())
	expect_eq(int(got[0]["version"]), 2)
	pc.free()


func test_token_builds_for_any_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in range(6):
		var t := PilotToken.new().build(PortraitSpec.randomize(rng))
		expect(t.get_child_count() > 0, "token has a body")
		t.free()


func test_lookups_keep_the_full_portrait() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var v2 := PortraitSpec.randomize(rng)
	expect_eq(PortraitArt.look_for_pilot({"id": "p1", "portrait": v2}), v2, "a pilot's v2 portrait comes back whole")
	var a := PortraitArt.look_for_pilot({"id": "p2"})
	expect_eq(a, PortraitArt.look_for_pilot({"id": "p2"}), "no portrait: the same random one every time")
	expect_eq(int(PortraitArt.look_for_npc({"id": "n1", "look": {"skin": "#a16a45"}})["version"]), 2, "flat NPC looks become v2")


func test_barks_show_and_expire() -> void:
	var b := BattleBarks.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var done: Array = []
	b.finished.connect(func(x: Dictionary) -> void: done.append(x))
	for i in range(4):
		b.say({"name": "Hawk", "face": {"portrait": PortraitSpec.randomize(rng), "expression": "smiling"}, "text": "Line %d" % i, "duration": 1.0})
	expect_eq(b._live.size(), BattleBarks.MAX_ON_SCREEN, "at most three at once; the oldest makes room")
	expect_eq(done.size(), 1)
	b._process(2.0)
	expect_eq(b._live.size(), 0, "they fade out on their own")
	b.free()
