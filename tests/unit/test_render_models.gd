extends TestCase
## Generated geometry: cell outlines on both grids, mech sizes and weapon models.


func test_cell_shape_hex_and_square() -> void:
	for shape: GridLayout.Shape in [GridLayout.Shape.HEX, GridLayout.Shape.SQUARE]:
		var grid := GridLayout.create(shape)
		var cs := MeshKit.cell_shape(grid)
		var corners: PackedVector2Array = cs["corners"]
		expect_eq(corners.size(), 6 if shape == GridLayout.Shape.HEX else 4, "corner count")
		# Each edge's neighbor really is a neighbor, and each edge-neighbor appears once.
		var edge_n: Array = cs["edge_neighbors"]
		var neighbors := grid.neighbors(Vector2i.ZERO)
		for n: Vector2i in edge_n:
			expect(n in neighbors, "edge neighbor %s is adjacent" % n)
		# Corners sit halfway-ish between neighbor centers: the cell tiles the plane.
		for p: Vector2 in corners:
			var w := grid.from_world(Vector3(p.x * 0.9, 0, p.y * 0.9))
			expect_eq(w, Vector2i.ZERO, "points inside the outline belong to the cell")


func test_every_frame_builds_at_its_size() -> void:
	var db := ContentDB.new()
	db.load_all()
	var frames: Array = db.all("frames")
	expect(frames.size() >= 29, "core frames present")
	for f: Dictionary in frames:
		var mech := MechBuilder.build(f, DemoLoadouts.for_frame(f, db), db)
		var size := float(f["stats"]["size"])
		expect(absf(mech.height - size * 0.95) < 0.001, "%s height matches Size" % f["id"])
		expect(not mech.meshes.is_empty(), "%s has geometry" % f["id"])
		expect(mech.eye != null, "%s has a cockpit eye" % f["id"])
		# Every weapon in the loadout got a model in some mount.
		var wanted := 0
		for m: Dictionary in DemoLoadouts.for_frame(f, db)["mounts"]:
			wanted += (m["weapons"] as Array).size()
		expect(mech.slot_weapon.size() == wanted, "%s mounts all %d weapons (got %d)" % [f["id"], wanted, mech.slot_weapon.size()])
		mech.free()


func test_every_weapon_builds_with_muzzle_and_style() -> void:
	var db := ContentDB.new()
	db.load_all()
	var styles := {}
	for w: Dictionary in db.all("weapons"):
		var model := WeaponBuilder.build(w)
		expect(model.get_node_or_null("Muzzle") != null, "%s has a muzzle" % w["id"])
		expect(model.get_child_count() > 2, "%s has parts" % w["id"])
		styles[model.get_meta("style")] = true
		model.free()
	for s: String in ["kinetic", "energy", "explosive", "missile", "melee", "flame", "swarm"]:
		expect(styles.has(s), "some weapon uses the %s animation" % s)


func test_weapon_models_differ() -> void:
	var db := ContentDB.new()
	db.load_all()
	var a := WeaponBuilder.build(db.weapon("mw_assault_rifle"))
	var b := WeaponBuilder.build(db.weapon("mw_vulture_dmr"))
	var sig := func(n: Node) -> String:
		var parts: Array = []
		for c in n.get_children():
			if c is MeshInstance3D:
				parts.append(str((c as MeshInstance3D).position.snappedf(0.001)))
		return ",".join(parts)
	expect(sig.call(a) != sig.call(b), "two rifles from different makers look different")
	a.free()
	b.free()


func test_roll_formula_text() -> void:
	var check := {"d20": 6, "bonus": 2, "bonuses": [{"label": "Grit", "value": 2}], "total": 12, "target": 8,
		"accuracy_roll": {"accuracy": 1, "difficulty": 0, "net": 1, "color": "blue", "dice": [4], "kept": 4, "value": 4}}
	var text := RollDisplay.formula_bbcode(check, "hit")
	expect(text.begins_with("6 "), text)
	expect("+4" in text and "+2 Grit" in text and "= 12 vs Evasion 8" in text and "HIT" in text, text)
	var src := RollDisplay.expand_sources({"sources": [{"label": "Lock On", "type": "accuracy"}, {"label": "Cover", "type": "difficulty", "value": 2}]})
	expect_eq(src["accuracy"].size(), 1)
	expect_eq(src["difficulty"].size(), 2)
