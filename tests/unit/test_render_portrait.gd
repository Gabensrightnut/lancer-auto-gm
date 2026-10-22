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
