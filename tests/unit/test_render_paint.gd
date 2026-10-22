extends TestCase
## Mech paint: roles found on built models, repaint and factory restore, decal textures,
## random schemes, and the preview control.


func _model(frame_id: String) -> MechModel:
	var db := ContentDB.new()
	db.load_all()
	return MechBuilder.build(db.frame(frame_id), {"mounts": [{"weapons": ["mw_assault_rifle"]}]}, db)


func _colors(m: MechModel) -> Array:
	var out: Array = []
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = mi.material_override
		if mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
			mat = mi.get_surface_override_material(0)
			if mat == null:
				mat = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			out.append((mat as ShaderMaterial).get_shader_parameter("base_color"))
	return out


func test_repaint_changes_primary_and_reset_restores() -> void:
	for frame_id: String in ["mf_standard_pattern_i_everest", "mf_lancaster", "mf_raleigh"]:
		var m := _model(frame_id)
		var before := _colors(m)
		var refs := MechPaint.model_colors(m)
		expect(refs.has("primary"), "%s has a primary color group" % frame_id)
		MechPaint.apply(m, {"primary": "#e6b422"})
		expect(_colors(m) != before, "%s: new primary changes some parts" % frame_id)
		MechPaint.apply(m, {})
		expect_eq(_colors(m), before, "%s: empty paint restores the factory look" % frame_id)
		m.free()


func test_repaint_does_not_touch_other_models() -> void:
	var a := _model("mf_lancaster")
	var b := _model("mf_lancaster")
	var before := _colors(b)
	MechPaint.apply(a, {"primary": "#1f4466", "secondary": "#e6b422"})
	expect_eq(_colors(b), before, "materials are copied per model")
	a.free()
	b.free()


func test_decal_textures_and_random_paint() -> void:
	for id: String in MechPaint.DECALS:
		if id != "":
			expect(MechPaint.decal_texture(id if id != "number" else "number:42") != null, id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var p := MechPaint.random_paint(rng)
	for k: String in ["primary", "secondary", "glow", "markings", "decals"]:
		expect(p.has(k), "random paint has " + k)
	expect(p["primary"] != p["secondary"], "two different main colors")


func test_preview_control_builds_the_loadout() -> void:
	var db := ContentDB.new()
	db.load_all()
	var pv := MechPreview.new()
	pv.set_mech(db, "mf_lancaster", {"mounts": [{"weapons": ["mw_assault_rifle"]}]}, {"glow": "#ff3c4a"})
	expect(pv.model() != null, "a model is on the turntable")
	expect_eq(pv.get_paint().get("glow"), "#ff3c4a")
	var got: Array = []
	pv.paint_changed.connect(func(p: Dictionary) -> void: got.append(p))
	pv.reset_paint()
	expect_eq(got.size(), 1, "reset reports the change")
	expect(pv.get_paint().is_empty(), "reset clears to factory")
	expect(pv.presets().size() > 5, "factory plus data presets")
	pv.free()


func test_merged_parts_keep_their_paint() -> void:
	for frame_id: String in ["mf_lancaster", "mf_standard_pattern_i_everest"]:
		var m := _model(frame_id)
		var unpainted := 0
		for mi: MeshInstance3D in m.find_children("Merged", "MeshInstance3D", true, false):
			for s in range(mi.mesh.get_surface_count()):
				if mi.mesh.surface_get_material(s) == null and mi.get_surface_override_material(s) == null:
					unpainted += 1
		expect_eq(unpainted, 0, "%s: every merged surface keeps its material" % frame_id)
		m.free()
