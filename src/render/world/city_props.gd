class_name CityProps
extends RefCounted
## Small things that make buildings read as real architecture: rooftop machinery, tanks,
## antennas and dishes, exposed rebar on ruins, shop signs, awnings, neon blade signs and
## holographic ads. All of it is either thin (antennas, rebar), flat against a wall (signs)
## or below WorldDressing.FLAT, so a roof never looks like it has cover it doesn't have.

const HOLO_SHADER := preload("res://src/render/shaders/holo.gdshader")


static func build(cb: CityBuilder, root: Node3D, faces: Array) -> void:
	var t := cb.t
	var arch := cb.arch
	var roof_style := str(arch.get("roof_props", "modern"))
	var ruin := float(arch.get("ruined", 0.0))
	var metal := MeshKit.mech_material(WorldStyle.color(arch.get("prop_metal", "#7a7c80")), 0.6, 0.5, Color.BLACK, false)
	var dark := MeshKit.mech_material(Color(0.18, 0.18, 0.19), 0.3, 0.7, Color.BLACK, false)
	var rust := MeshKit.mech_material(Color(0.36, 0.2, 0.12), 0.5, 0.7, Color.BLACK, false)
	var boxes: Array = []
	var tanks: Array = []
	var rods: Array = []
	var dishes: Array = []
	var rebar: Array = []
	var chimneys: Array = []
	for c: Vector2i in t.structure_cells:
		var key := "rp" + str(c)
		var top := t.top_y(c)
		var r := WorldRand.f(key, 0)
		var p := t.random_point(c, key, 1, 0.5) + Vector3.UP * (top - t.floor_y(c))
		p.y = top
		var rot := Basis(Vector3.UP, WorldRand.f(key, 2) * TAU)
		match roof_style:
			"medieval", "western":
				if r < 0.3:
					chimneys.append(Transform3D((rot * Basis.from_scale(Vector3(0.1, 0.14, 0.1))), p + Vector3.UP * 0.07))
			"none":
				pass
			_:
				if r < 0.16:
					boxes.append(Transform3D((rot * Basis.from_scale(Vector3(0.22, 0.1, 0.15))), p + Vector3.UP * 0.05))
				elif r < 0.24:
					tanks.append(Transform3D((rot * Basis.from_scale(Vector3(0.09, 0.13, 0.09))), p + Vector3.UP * 0.065))
				elif r < 0.3:
					dishes.append(Transform3D(rot * Basis(Vector3.RIGHT, -0.6), p + Vector3.UP * 0.05))
				if WorldRand.f(key, 3) < 0.12:
					var len := 0.35 + 0.5 * WorldRand.f(key, 4)
					rods.append(Transform3D(Basis().scaled(Vector3(1, len, 1)), t.random_point(c, key, 5, 0.6) + Vector3.UP * (top - t.floor_y(c) + len * 0.5)))
		if ruin > 0.0 and WorldRand.f(key, 6) < ruin * 0.5:
			for k in range(3):
				var q := t.random_point(c, key, 10 + k, 0.9)
				q.y = top
				var len := 0.12 + 0.18 * WorldRand.f(key, 20 + k)
				var tilt := Basis(Vector3.UP, WorldRand.f(key, 30 + k) * TAU) * Basis(Vector3.RIGHT, (WorldRand.f(key, 40 + k) - 0.5) * 0.7)
				rebar.append(Transform3D((tilt * Basis.from_scale(Vector3(1, len, 1))), q + tilt.y * len * 0.5))
	WorldDressing.multi(root, "RoofBoxes", MeshKit.chamfer_box(Vector3.ONE, 0.08), boxes, metal, true)
	WorldDressing.multi(root, "RoofTanks", MeshKit.cylinder(1.0, 1.0, 10), tanks, rust, true)
	WorldDressing.multi(root, "Antennas", MeshKit.cylinder(0.008, 1.0, 4), rods, dark, false)
	WorldDressing.multi(root, "Dishes", MeshKit.cylinder(0.07, 0.015, 10, 0.05), dishes, metal, false)
	WorldDressing.multi(root, "RoofRebar", MeshKit.cylinder(0.01, 1.0, 4), rebar, rust, false)
	WorldDressing.multi(root, "Chimneys", MeshKit.chamfer_box(Vector3.ONE, 0.05), chimneys,
		MeshKit.mech_material(WorldStyle.color(arch.get("trim", "#5a5048")), 0.0, 0.9, Color.BLACK, false), true)
	_street_faces(cb, root, faces)
	_street_props(cb, root)


## Shop signs and awnings over street-level facades, neon blade signs and holo ads higher up.
static func _street_faces(cb: CityBuilder, root: Node3D, faces: Array) -> void:
	var arch := cb.arch
	var signs := float(arch.get("signs", 0.0))
	var awnings := float(arch.get("awnings", 0.0))
	var neon := float(arch.get("neon", 0.0))
	var holo := float(arch.get("holo", 0.0))
	var floors := float(arch.get("floors", 3.0))
	var sign_cols: Array = arch.get("sign_colors", ["#d8c8a0"])
	var neon_cols: Array = arch.get("neon_colors", ["#ff33aa", "#22e0ff", "#ffd030"])
	var awn_cols: Array = arch.get("awning_colors", ["#7a2a22", "#2a4a6a", "#3a5a2a"])
	var sign_groups := {}
	for f: Array in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var out: Vector3 = f[2]
		var top: float = f[4]
		var key := "sf%s" % str(a)
		var w := a.distance_to(b)
		var mid := (a + b) * 0.5
		var along := (b - a).normalized()
		var basis := Basis(along, Vector3.UP, out)
		var ground_top := 1.0 / floors
		if WorldRand.f(key, 0) < signs and top >= ground_top + 0.1:
			# Shop sign band just above the storefront, flat on the wall.
			var col := WorldStyle.color(sign_cols[int(WorldRand.f(key, 1) * sign_cols.size()) % sign_cols.size()])
			var lit := neon > 0.0
			_add_group(sign_groups, col, lit, Transform3D((basis * Basis.from_scale(Vector3(w * 0.7, 0.07, 0.015))), mid + out * 0.01 + Vector3.UP * (ground_top * 0.82)))
		if WorldRand.f(key, 2) < awnings and top >= ground_top + 0.1:
			var col := WorldStyle.color(awn_cols[int(WorldRand.f(key, 3) * awn_cols.size()) % awn_cols.size()])
			var tilt := basis * Basis(Vector3.RIGHT, 0.45)
			_add_group(sign_groups, col, false, Transform3D((tilt * Basis.from_scale(Vector3(w * 0.8, 0.012, 0.13))), mid + out * 0.06 + Vector3.UP * (ground_top * 0.72)))
		if neon > 0.0 and WorldRand.f(key, 4) < neon * 0.6 and top > 1.2:
			# Vertical blade sign sticking out from the corner, up the upper floors.
			var col := WorldStyle.color(neon_cols[int(WorldRand.f(key, 5) * neon_cols.size()) % neon_cols.size()])
			var h := minf(0.35 + 0.5 * WorldRand.f(key, 6), top - 0.5)
			var y := 0.45 + (top - 0.5 - h) * WorldRand.f(key, 7) + h * 0.5
			_add_group(sign_groups, col, true, Transform3D((basis * Basis.from_scale(Vector3(0.02, h, 0.11))), a.lerp(b, 0.15) + out * 0.06 + Vector3.UP * y))
		if holo > 0.0 and WorldRand.f(key, 8) < holo and top > 1.8:
			_holo(root, key, mid + out * 0.012, basis, w, top)
	for k: String in sign_groups:
		var e: Array = sign_groups[k]
		var col: Color = e[0]
		var mat := MeshKit.mech_material(col, 0.1, 0.6, col * 1.6 if e[1] else Color.BLACK, false)
		WorldDressing.multi(root, "Signs", MeshKit.chamfer_box(Vector3.ONE, 0.002), e[2], mat, false)


static func _add_group(groups: Dictionary, col: Color, lit: bool, xf: Transform3D) -> void:
	var k := "%s|%s" % [col.to_html(), lit]
	if not groups.has(k):
		groups[k] = [col, lit, []]
	(groups[k][2] as Array).append(xf)


## A holographic advert: a flickering, scrolling panel flat on a tall facade.
static func _holo(root: Node3D, key: String, at: Vector3, basis: Basis, w: float, top: float) -> void:
	var h := minf(0.8 + WorldRand.f(key, 9) * 1.2, top - 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(w * 0.85, h)
	var mi := MeshInstance3D.new()
	mi.name = "Holo"
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = HOLO_SHADER
	var hues := [Color(1.0, 0.25, 0.7), Color(0.2, 0.9, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 1.0, 0.4)]
	m.set_shader_parameter("tint", hues[int(WorldRand.f(key, 10) * hues.size()) % hues.size()])
	m.set_shader_parameter("seed", WorldRand.f(key, 11) * 10.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(basis, at + Vector3.UP * (top - h * 0.5 - 0.25))
	root.add_child(mi, true)


## Street furniture on open ground next to buildings: lamps (thin poles with a glowing head,
## at the cell's edge), barrels and crates (below flat-decoration height).
## architecture.street: {"lamps": 0..1, "lamp_color", "lamp_style": "post"/"lantern"/"torch",
## "barrels": 0..1, "crates": 0..1}
static func _street_props(cb: CityBuilder, root: Node3D) -> void:
	var t := cb.t
	var street: Dictionary = cb.arch.get("street", {})
	if street.is_empty():
		return
	var lamp_col := WorldStyle.color(street.get("lamp_color", "#ffd8a0"))
	var style := str(street.get("lamp_style", "post"))
	var poles: Array = []
	var heads: Array = []
	var barrels: Array = []
	var crates: Array = []
	var lights := 0
	var corners: PackedVector2Array = MeshKit.cell_shape(t.map.grid)["corners"]
	for c in t.map.cells():
		if t.structure_cells.has(c) or t.surface(c) != TerrainRenderer.KIND_GROUND or t.map.column(c).has_tag(Sight.TAG_SOFT_COVER):
			continue
		var next_to := false
		for n in t.map.grid.neighbors(c):
			if t.structure_cells.has(n):
				next_to = true
				break
		if not next_to:
			continue
		var key := "st" + str(c)
		var base := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c)
		if WorldRand.f(key, 0) < float(street.get("lamps", 0.0)):
			var k := int(WorldRand.f(key, 1) * corners.size())
			var p := base + Vector3(corners[k].x, 0, corners[k].y) * 0.9
			var h := 0.75 if style == "post" else 0.45
			poles.append(Transform3D(Basis.from_scale(Vector3(1, h, 1)), p + Vector3.UP * h * 0.5))
			heads.append(Transform3D(Basis(), p + Vector3.UP * (h + 0.03)))
			if lights < WorldQuality.lights(14) and WorldRand.f(key, 2) < 0.5:
				lights += 1
				var l: OmniLight3D
				if style == "torch":
					var fl := FlickerLight.new()
					fl.base_energy = 1.2
					l = fl
				else:
					l = OmniLight3D.new()
				l.light_color = lamp_col
				l.light_energy = 1.2
				l.omni_range = 2.5
				l.position = p + Vector3.UP * (h - 0.05)
				root.add_child(l)
		if WorldRand.f(key, 3) < float(street.get("barrels", 0.0)):
			for i in range(1 + int(WorldRand.f(key, 4) * 3.0)):
				barrels.append(Transform3D(Basis.from_scale(Vector3(0.06, 0.14, 0.06)), t.random_point(c, key, 10 + i, 0.6) + Vector3.UP * 0.07))
		if WorldRand.f(key, 5) < float(street.get("crates", 0.0)):
			for i in range(1 + int(WorldRand.f(key, 6) * 3.0)):
				var s := 0.1 + 0.06 * WorldRand.f(key, 20 + i)
				crates.append(Transform3D(Basis(Vector3.UP, WorldRand.f(key, 30 + i) * TAU) * Basis.from_scale(Vector3.ONE * s), t.random_point(c, key, 40 + i, 0.6) + Vector3.UP * s * 0.5))
	var dark := MeshKit.mech_material(Color(0.12, 0.12, 0.13), 0.6, 0.5, Color.BLACK, false)
	WorldDressing.multi(root, "LampPoles", MeshKit.cylinder(0.012, 1.0, 5), poles, dark, false)
	WorldDressing.multi(root, "LampHeads", MeshKit.sphere(0.03, 6), heads, MeshKit.mech_material(lamp_col, 0.0, 0.5, lamp_col * 3.0, false), false)
	WorldDressing.multi(root, "Barrels", MeshKit.cylinder(1.0, 1.0, 10), barrels, MeshKit.mech_material(WorldStyle.color(street.get("barrel_color", "#5a4030")), 0.3, 0.7, Color.BLACK, false), true)
	WorldDressing.multi(root, "Crates", MeshKit.chamfer_box(Vector3.ONE, 0.06), crates, MeshKit.mech_material(WorldStyle.color(street.get("crate_color", "#7a6040")), 0.0, 0.9, Color.BLACK, false), true)
