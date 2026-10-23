extends TestCase
## Locomotion: every core frame has a gait, stride scales with Size, feet plant on cells.


func test_every_frame_has_a_gait() -> void:
	var db := ContentDB.new()
	db.load_all()
	var known := ["biped", "digitigrade", "quadruped", "hexapod", "tracked", "hover", "winged"]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/locomotion.json"))
	for f: Dictionary in db.all("frames"):
		expect((data["frames"] as Dictionary).has(f["id"]), "%s listed in locomotion.json" % f["id"])
		expect(MechModel.gait_for(f["id"]) in known, "%s gait is known" % f["id"])


func test_steps_per_cell_scale_with_size() -> void:
	var m := MechModel.new()
	var expected := {0.5: 4, 1.0: 2, 2.0: 1, 3.0: 1}
	for s: float in expected:
		m.size = s
		expect_eq(m.steps_per_cell(), expected[s], "Size %s" % s)
	m.free()


func test_feet_planted_after_whole_cells() -> void:
	var db := ContentDB.new()
	db.load_all()
	var m := MechBuilder.build(db.frame("mf_standard_pattern_i_everest"), {}, db)
	m.walk_amount = 1.0
	m.walk_phase = m.steps_per_cell() * PI * 3.0  # three cells walked
	m._apply_walk()
	for leg: Dictionary in m.legs:
		var base: Vector3 = leg["base"]
		expect(absf((leg["hip"] as Node3D).rotation_degrees.x - base.x) < 0.01, "hip back at rest on a cell")
	m.free()


func test_free_walker_moves_smoothly_and_turns() -> void:
	var view := BattleView.new()
	view.set_map(BattleMap.flat(GridLayout.Shape.HEX, 12, 12), "grassy_hills")
	var mv := view.add_unit({"id": "e", "content_id": "mf_standard_pattern_i_everest", "side": "players", "size": 1, "cell": [2, 2], "level": 0})
	var w := FreeWalker.attach(mv)
	w._ready()
	var start := mv.position
	w.walk_to(start + Vector3(4, 0, 0))
	var phase0 := mv.model.walk_phase
	for i in range(60):
		w._physics_process(1.0 / 30.0)
	expect(mv.position.x > start.x + 2.0, "it walked toward the point")
	expect(mv.model.walk_phase > phase0, "the gait advanced with the distance")
	expect(absf(wrapf(mv.model.rotation.y - atan2(-1.0, 0.0), -PI, PI)) < 0.2, "it turned to face its way")
	for i in range(120):
		w._physics_process(1.0 / 30.0)
	expect(not w.is_moving(), "and stops at the point")
	view.free()


func test_kneel_for_mounting_and_stand_again() -> void:
	var db := ContentDB.new()
	db.load_all()
	for fid: String in ["mf_standard_pattern_i_everest", "mf_goblin", "mf_hydra"]:
		var m := MechBuilder.build(db.frame(fid), {}, db)
		var rest := m.pelvis.position.y
		var hips: Array = []
		for leg: Dictionary in m.legs:
			hips.append((leg["hip"] as Node3D).rotation_degrees.x)
		m.set_kneel(1.0)
		expect(m.pelvis.position.y < rest - 0.001, "%s lowers to kneel" % fid)
		if not m.legs.is_empty():
			expect(absf((m.legs[0]["hip"] as Node3D).rotation_degrees.x - float(hips[0])) > 20.0, "%s bends its legs" % fid)
		m.set_kneel(0.0)
		expect(absf(m.pelvis.position.y - rest) < 0.001, "%s stands back up" % fid)
		m.free()
