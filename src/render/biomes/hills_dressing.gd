class_name HillsDressing
extends RefCounted
## Dresses a grassy hills board: rippling water on river cells, swaying grass tufts and
## flowers, flat stones on rough ground, rolling landscape and tree lines beyond the board,
## and drifting pollen. Everything on the board stays small and flat: cover and obstacles
## come only from the map's raised columns.

const HILLS_SHADER := preload("res://src/render/shaders/terrain_hills.gdshader")
const WATER_SHADER := preload("res://src/render/shaders/water.gdshader")
const FOLIAGE_SHADER := preload("res://src/render/shaders/foliage.gdshader")
const WATER_DEPTH := 0.3


static func build(t: TerrainRenderer, root: Node3D) -> void:
	_water(t, root)
	_grass(t, root)
	_stones(t, root)
	var bounds := _bounds(t)
	_landscape(t, root, bounds)
	_trees(t, root, bounds)
	_pollen(root, bounds)


static func _bounds(t: TerrainRenderer) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in t.map.cells():
		var p := t.map.grid.to_world(c)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return Rect2(lo, hi - lo).grow(0.6)


static func _water(t: TerrainRenderer, root: Node3D) -> void:
	liquid(t, root, "water", WATER_SHADER, WATER_DEPTH)


## Liquid surface over every cell with `tag`, `depth` above the cell floor.
static func liquid(t: TerrainRenderer, root: Node3D, tag: String, shader: Shader, depth: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in t.map.cells():
		if not t.map.column(c).has_tag(tag):
			continue
		any = true
		var pts := t.cell_corners(c, t.top_y(c) + depth, -0.02)
		var center := t.map.grid.to_world(c) + Vector3.UP * (t.top_y(c) + depth)
		for i in range(pts.size()):
			MeshKit.add_tri(st, center, pts[i], pts[(i + 1) % pts.size()], Vector3.UP)
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Liquid_" + tag
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = shader
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## A tuft: a fan of thin blades, about 1 unit tall before scaling.
static func _tuft_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(7):
		var a := TAU * i / 7.0 + 0.4 * sin(i * 3.1)
		var lean := Vector3(cos(a), 0, sin(a)) * (0.25 + 0.15 * sin(i * 1.7))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.06
		var base := Vector3(cos(a), 0, sin(a)) * 0.05
		var h := 0.75 + 0.25 * sin(i * 2.3)
		var shade := color.darkened(0.3 + 0.1 * sin(i * 1.3))
		st.set_color(shade)
		st.set_normal(Vector3.UP)
		st.add_vertex(base - side)
		st.set_color(color.lightened(0.1))
		st.add_vertex(base + lean + Vector3.UP * h)
		st.set_color(shade)
		st.add_vertex(base + side)
	return st.commit()


static func _foliage_material(sway: float, sway_height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_height", sway_height)
	return m


static func _grass(t: TerrainRenderer, root: Node3D) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var greens := [Color(0.3, 0.5, 0.15), Color(0.4, 0.58, 0.2), Color(0.5, 0.55, 0.25), Color(0.25, 0.42, 0.14)]
	var flowers := [Color(0.95, 0.85, 0.3), Color(0.92, 0.92, 0.95), Color(0.7, 0.45, 0.85)]
	var corners: PackedVector2Array = MeshKit.cell_shape(t.map.grid)["corners"]
	for c in t.map.cells():
		var kind := t.hills_kind(c)
		if kind != TerrainRenderer.KIND_GRASS and kind != TerrainRenderer.KIND_ROUGH:
			continue
		var key := "g" + str(c)
		var center := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c)
		var n := 9 if kind == TerrainRenderer.KIND_GRASS else 4
		for i in range(n):
			# A random point inside the cell: blend toward a random corner.
			var k := MeshKit.hash01(key, i) * corners.size()
			var corner := corners[int(k) % corners.size()]
			var p := center + Vector3(corner.x, 0, corner.y) * 0.85 * sqrt(MeshKit.hash01(key, i + 50))
			var s := 0.045 + 0.05 * MeshKit.hash01(key, i + 100)
			var basis := Basis(Vector3.UP, MeshKit.hash01(key, i + 150) * TAU).scaled(Vector3(s * 1.4, s, s * 1.4))
			xforms.append(Transform3D(basis, p))
			var flower := MeshKit.hash01(key, i + 200) < 0.06
			colors.append(flowers[i % flowers.size()] if flower else greens[int(MeshKit.hash01(key, i + 250) * greens.size()) % greens.size()])
	# One multimesh per color: colors are baked into each tuft mesh.
	var groups := {}
	for k in range(xforms.size()):
		var key := colors[k].to_html()
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(xforms[k])
	for key: String in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tuft_mesh(Color.html(key))
		mm.instance_count = list.size()
		for k in range(list.size()):
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass"
		mmi.multimesh = mm
		mmi.material_override = _foliage_material(0.25, 1.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


static func _stones(t: TerrainRenderer, root: Node3D) -> void:
	var mat := MeshKit.mech_material(Color(0.42, 0.4, 0.37), 0.0, 0.9, Color.BLACK, false)
	for c in t.map.cells():
		if t.hills_kind(c) != TerrainRenderer.KIND_ROUGH:
			continue
		var key := "s" + str(c)
		var center := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c)
		for i in range(6):
			var off := Vector3(MeshKit.hash01(key, i) - 0.5, 0, MeshKit.hash01(key, i + 10) - 0.5) * 0.75
			var s := 0.06 + 0.08 * MeshKit.hash01(key, i + 20)
			# Flat stones: never tall enough to read as cover.
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(s * 1.3, s * 0.35, s), 0.012), mat, center + off + Vector3.UP * s * 0.12,
				Vector3(0, MeshKit.hash01(key, i + 30) * 180.0, MeshKit.hash01(key, i + 40) * 10.0))


## Height of the land outside the board: low next to it, rolling hills further out.
static func _land_height(x: float, z: float, bounds: Rect2) -> float:
	var dx := maxf(maxf(bounds.position.x - x, x - bounds.end.x), 0.0)
	var dz := maxf(maxf(bounds.position.y - z, z - bounds.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	var n := DemoMap.fbm(x * 0.06, z * 0.06)
	return -0.75 + smoothstep(0.5, 18.0, d) * (2.0 + 9.0 * n) + 0.3 * DemoMap.fbm(x * 0.4, z * 0.4)


static func _landscape(t: TerrainRenderer, root: Node3D, bounds: Rect2, height_fn: Callable = Callable(), ext: float = 45.0) -> void:
	if not height_fn.is_valid():
		height_fn = _land_height
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1.5
	var x0 := bounds.position.x - ext
	var z0 := bounds.position.y - ext
	var nx := int((bounds.size.x + 2.0 * ext) / step)
	var nz := int((bounds.size.y + 2.0 * ext) / step)
	var hgt := func(i: int, j: int) -> Vector3:
		var x := x0 + i * step
		var z := z0 + j * step
		return Vector3(x, height_fn.call(x, z, bounds), z)
	for j in range(nz):
		for i in range(nx):
			var a: Vector3 = hgt.call(i, j)
			var b: Vector3 = hgt.call(i + 1, j)
			var c: Vector3 = hgt.call(i + 1, j + 1)
			var d: Vector3 = hgt.call(i, j + 1)
			# Skip quads hidden under the board.
			if bounds.grow(-0.8).has_point(Vector2((a.x + c.x) * 0.5, (a.z + c.z) * 0.5)):
				continue
			var far := clampf((maxf(absf(a.x - bounds.get_center().x) - bounds.size.x * 0.5, absf(a.z - bounds.get_center().y) - bounds.size.y * 0.5)) / 30.0, 0.0, 1.0)
			st.set_color(Color(0.0, MeshKit.hash01("l", i * 1000 + j), 0.15 + 0.25 * far, 1.0))
			st.set_uv2(Vector2(0, a.y))
			var n1 := (b - a).cross(d - a).normalized()
			if n1.y < 0:
				n1 = -n1
			MeshKit.add_quad(st, a, b, c, d, n1)
	var mi := MeshInstance3D.new()
	mi.name = "Landscape"
	mi.mesh = st.commit()
	mi.material_override = t.material
	root.add_child(mi)


## A low-poly tree (trunk + three foliage clumps) as one mesh with vertex colors.
static func _tree_mesh() -> ArrayMesh:
	var parts := [
		[MeshKit.cylinder(0.05, 0.6, 6, 0.035), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.32, 0.22, 0.14)],
		[MeshKit.sphere(0.38, 7), Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), Vector3(0, 0.75, 0)), Color(0.13, 0.25, 0.08)],
		[MeshKit.sphere(0.3, 7), Transform3D(Basis().scaled(Vector3(1, 0.9, 1)), Vector3(0.18, 1.0, 0.08)), Color(0.17, 0.3, 0.1)],
		[MeshKit.sphere(0.26, 7), Transform3D(Basis().scaled(Vector3(1, 0.9, 1)), Vector3(-0.15, 1.12, -0.1)), Color(0.2, 0.33, 0.11)],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		var arrays := (p[0] as Mesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[1]
		for k in idx:
			st.set_color(p[2])
			st.set_normal((xf.basis * norms[k]).normalized())
			st.add_vertex(xf * verts[k])
	return st.commit()


static func _trees(t: TerrainRenderer, root: Node3D, bounds: Rect2) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var n := 0
	for ring in range(3):
		var margin := 1.8 + ring * 2.6
		var r := bounds.grow(margin)
		var per := int((r.size.x + r.size.y) * 2.0 / (1.3 + ring * 0.4))
		for i in range(per):
			n += 1
			var u := float(i) / per * 4.0
			var p: Vector2
			if u < 1.0:
				p = Vector2(lerpf(r.position.x, r.end.x, u), r.position.y)
			elif u < 2.0:
				p = Vector2(r.end.x, lerpf(r.position.y, r.end.y, u - 1.0))
			elif u < 3.0:
				p = Vector2(lerpf(r.end.x, r.position.x, u - 2.0), r.end.y)
			else:
				p = Vector2(r.position.x, lerpf(r.end.y, r.position.y, u - 3.0))
			p += Vector2(MeshKit.hash01("tx", n) - 0.5, MeshKit.hash01("tz", n) - 0.5) * 2.6
			# Leave gaps so the woods don't look like a wall, and keep the camera side open.
			if DemoMap.fbm(p.x * 0.15, p.y * 0.15) < 0.42 or p.y > bounds.end.y + 0.5:
				continue
			var s := 1.0 + 0.8 * MeshKit.hash01("ts", n) + ring * 0.25
			var y := _land_height(p.x, p.y, bounds)
			var basis := Basis(Vector3.UP, MeshKit.hash01("tr", n) * TAU).scaled(Vector3.ONE * s)
			xforms.append(Transform3D(basis, Vector3(p.x, y - 0.05, p.y)))
			var g := MeshKit.hash01("tc", n)
			colors.append(Color(0.12 + 0.1 * g, 0.24 + 0.1 * g, 0.08 + 0.04 * g))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_mesh()
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	mmi.material_override = _foliage_material(0.035, 1.3)
	root.add_child(mmi)


static func _pollen(root: Node3D, bounds: Rect2) -> void:
	var p := CPUParticles3D.new()
	p.name = "Pollen"
	p.amount = 120
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(bounds.size.x * 0.5, 1.5, bounds.size.y * 0.5)
	p.position = Vector3(bounds.get_center().x, 2.0, bounds.get_center().y)
	p.direction = Vector3(1, 0.1, 0.3)
	p.spread = 30.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Fx.soft_texture()
	m.albedo_color = Color(1.0, 0.97, 0.8, 0.6)
	q.material = m
	p.mesh = q
	root.add_child(p)
