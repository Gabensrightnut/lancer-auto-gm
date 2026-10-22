class_name AlienDressing
extends RefCounted
## Dresses an alien wilds board: a glowing toxic sea, bioluminescent plants, small crystal
## shards, rising spores, and a horizon of jagged spires, colossal ancient megastructures and
## a storm wall with lightning. Board decoration stays small and flat; cover comes only from
## raised columns (crystal and rock outcrops are real map data).

const TOXIC_SHADER := preload("res://src/render/shaders/toxic.gdshader")
const STORM_SHADER := preload("res://src/render/shaders/storm.gdshader")
const PLANT_SHADER := preload("res://src/render/shaders/glow_plant.gdshader")


static func build(t: TerrainRenderer, root: Node3D) -> void:
	HillsDressing.liquid(t, root, "toxic", TOXIC_SHADER, 0.25)
	_plants(t, root)
	var bounds := HillsDressing._bounds(t)
	HillsDressing._landscape(t, root, bounds, _land_height, 70.0)
	_megastructures(root, bounds)
	_storm(root, bounds)
	_spores(root, bounds)


## Outside the board: low ground, then terraced mesas and needle spires.
static func _land_height(x: float, z: float, bounds: Rect2) -> float:
	var dx := maxf(maxf(bounds.position.x - x, x - bounds.end.x), 0.0)
	var dz := maxf(maxf(bounds.position.y - z, z - bounds.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	var n := DemoMap.fbm(x * 0.05 + 30.0, z * 0.05)
	var mesa := floorf(n * 6.0) / 6.0 * 7.0
	var spire := pow(maxf(0.0, DemoMap.fbm(x * 0.25, z * 0.25) - 0.66), 1.5) * 45.0
	return -0.75 + smoothstep(2.0, 30.0, d) * mesa + spire * smoothstep(25.0, 45.0, d)


## A plant: a thin stem and a glowing cap (vertex alpha 0 = glows).
static func _plant_mesh(cap: Color, kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add := func(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k: int in arr[Mesh.ARRAY_INDEX]:
			st.set_color(col)
			st.set_normal((xf.basis * norms[k]).normalized())
			st.add_vertex(xf * verts[k])
	if kind == 0:
		# Glowcap mushroom.
		add.call(MeshKit.cylinder(0.08, 0.6, 5, 0.06), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.2, 0.15, 0.25, 1.0))
		add.call(SmoothKit.blob(Vector3(0.6, 0.3, 0.6), 0.7, 0.8, 0.0, 10), Transform3D(Basis(), Vector3(0, 0.55, 0)), Color(cap.r, cap.g, cap.b, 0.0))
	else:
		# Frond: three leaning glowing blades.
		for i in range(3):
			var b := Basis(Vector3.UP, TAU * i / 3.0) * Basis(Vector3.RIGHT, 0.5)
			add.call(SmoothKit.blob(Vector3(0.12, 0.9, 0.04), 0.8, 0.8, 1.0, 8), Transform3D(b, b * Vector3(0, 0.4, 0)), Color(cap.r, cap.g, cap.b, 0.3))
	return st.commit()


static func _plants(t: TerrainRenderer, root: Node3D) -> void:
	var colors := [Color(0.3, 0.95, 0.9), Color(0.85, 0.35, 0.95), Color(0.5, 0.75, 1.0)]
	var corners: PackedVector2Array = MeshKit.cell_shape(t.map.grid)["corners"]
	for kind in range(2):
		for ci in range(colors.size()):
			var xf: Array[Transform3D] = []
			for c in t.map.cells():
				var k := t.hills_kind(c)
				if k != TerrainRenderer.KIND_GRASS and k != TerrainRenderer.KIND_ROUGH:
					continue
				var key := "a%d%d%s" % [kind, ci, c]
				var count := 2 if k == TerrainRenderer.KIND_GRASS else 1
				for i in range(count):
					if MeshKit.hash01(key, i) > 0.45:
						continue
					var corner := corners[int(MeshKit.hash01(key, i + 9) * corners.size()) % corners.size()]
					var p := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c) + Vector3(corner.x, 0, corner.y) * 0.8 * sqrt(MeshKit.hash01(key, i + 20))
					var s := 0.06 + 0.06 * MeshKit.hash01(key, i + 30)
					xf.append(Transform3D(Basis(Vector3.UP, MeshKit.hash01(key, i + 40) * TAU).scaled(Vector3.ONE * s), p))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _plant_mesh(colors[ci], kind)
			mm.instance_count = xf.size()
			for i in range(xf.size()):
				mm.set_instance_transform(i, xf[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var mat := ShaderMaterial.new()
			mat.shader = PLANT_SHADER
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	# Small crystal shards on crystal tops (short, so they don't add to the column's height).
	var shard_mat := MeshKit.paint(Color(0.2, 0.4, 0.6), 0.4, 0.1, 0.0, Color(0.3, 0.7, 1.0))
	for c in t.map.cells():
		if not t.map.column(c).has_tag("crystal"):
			continue
		var key := "cr" + str(c)
		var base := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c)
		for i in range(4):
			var off := Vector3(MeshKit.hash01(key, i) - 0.5, 0, MeshKit.hash01(key, i + 5) - 0.5) * 0.6
			var h := 0.06 + 0.08 * MeshKit.hash01(key, i + 10)
			MeshKit.part(root, MeshKit.cylinder(0.03, h, 6, 0.0), shard_mat, base + off + Vector3.UP * h * 0.5,
				Vector3(MeshKit.hash01(key, i + 15) * 30.0 - 15.0, 0, MeshKit.hash01(key, i + 20) * 30.0 - 15.0))


## Colossal ancient structures on the horizon: an arch, a broken ring standing on edge and
## obelisks with faint glowing lines. Far enough out that fog turns them into silhouettes.
static func _megastructures(root: Node3D, bounds: Rect2) -> void:
	var stone := MeshKit.paint(Color(0.1, 0.09, 0.12), 0.5, 0.6, 0.0)
	var lines := MeshKit.paint(Color(0.05, 0.05, 0.05), 0.2, 0.3, 0.0, Color(0.35, 0.9, 1.0))
	var c := Vector3(bounds.get_center().x, -1.0, bounds.get_center().y)
	var arch := Node3D.new()
	arch.position = c + Vector3(-70, 0, -95)
	arch.rotation_degrees.y = 20
	root.add_child(arch)
	for s: float in [-1.0, 1.0]:
		MeshKit.part(arch, SmoothKit.loft([{"y": 0.0, "w": 9.0, "d": 7.0, "n": 4.0}, {"y": 40.0, "w": 6.0, "d": 5.0, "n": 4.0}, {"y": 55.0, "w": 7.5, "d": 5.5, "n": 4.0}]), stone, Vector3(s * 22.0, 0, 0))
		MeshKit.part(arch, MeshKit.chamfer_box(Vector3(0.4, 45.0, 0.4), 0.05), lines, Vector3(s * 22.0, 22.0, -3.2))
	MeshKit.part(arch, SmoothKit.rounded_box(Vector3(56.0, 7.0, 6.0), 1.5), stone, Vector3(0, 58.0, 0))
	MeshKit.part(arch, MeshKit.chamfer_box(Vector3(50.0, 0.4, 0.4), 0.05), lines, Vector3(0, 56.0, -3.1))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 30.0
	tm.outer_radius = 36.0
	tm.rings = 48
	tm.ring_segments = 10
	ring.mesh = tm
	ring.material_override = stone
	ring.position = c + Vector3(95, 18, -40)
	ring.rotation_degrees = Vector3(90, -60, 8)
	root.add_child(ring)
	for i in range(7):
		var a := deg_to_rad(-150.0 + i * 38.0 + MeshKit.hash01("ob", i) * 12.0)
		var r := 80.0 + 30.0 * MeshKit.hash01("obr", i)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r * 0.9)
		if p.z > bounds.end.y + 20.0:
			continue  # keep the camera side open
		var h := 25.0 + 40.0 * MeshKit.hash01("obh", i)
		var ob := MeshKit.part(root, SmoothKit.loft([{"y": 0.0, "w": 5.0, "d": 5.0, "n": 6.0}, {"y": h * 0.9, "w": 2.6, "d": 2.6, "n": 6.0}, {"y": h, "w": 0.3, "d": 0.3, "n": 6.0}]), stone, p)
		MeshKit.part(ob, MeshKit.chamfer_box(Vector3(0.25, h * 0.7, 0.25), 0.04), lines, Vector3(0, h * 0.4, -2.0))


## A curved cloud wall far out on the left horizon, flickering with lightning.
static func _storm(root: Node3D, bounds: Rect2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(bounds.get_center().x, -2.0, bounds.get_center().y)
	var r := 150.0
	var steps := 40
	for i in range(steps):
		var a0 := deg_to_rad(110.0 + 120.0 * float(i) / steps)
		var a1 := deg_to_rad(110.0 + 120.0 * float(i + 1) / steps)
		var p0 := c + Vector3(cos(a0), 0, -sin(a0)) * r
		var p1 := c + Vector3(cos(a1), 0, -sin(a1)) * r
		var u0 := float(i) / steps
		var u1 := float(i + 1) / steps
		for v: Array in [[p0, u0, 0.0], [p1, u1, 0.0], [p1, u1, 1.0], [p0, u0, 0.0], [p1, u1, 1.0], [p0, u0, 1.0]]:
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex((v[0] as Vector3) + Vector3.UP * 55.0 * float(v[2]))
	var mi := MeshInstance3D.new()
	mi.name = "Storm"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = STORM_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _spores(root: Node3D, bounds: Rect2) -> void:
	var p := CPUParticles3D.new()
	p.name = "Spores"
	p.amount = 160
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(bounds.size.x * 0.55, 1.0, bounds.size.y * 0.55)
	p.position = Vector3(bounds.get_center().x, 1.0, bounds.get_center().y)
	p.direction = Vector3(0.2, 1, 0.1)
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Fx.soft_texture()
	m.albedo_color = Color(0.4, 1.0, 0.85)
	m.vertex_color_use_as_albedo = true
	q.material = m
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.mesh = q
	root.add_child(p)
