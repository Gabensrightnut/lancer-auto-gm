class_name WorldDressing
extends RefCounted
## Dresses a board in its world style. What it adds follows the rules tags exactly:
## - woods only on soft_cover cells (tall, see-through foliage = soft cover);
## - rough clutter (stones, rubble, scree, ice) only on difficult cells, kept low;
## - flames/glow only on dangerous cells; liquids only on liquid look tags;
## - boulders only around rock columns (which are solid hard cover anyway);
## - everywhere else only small flat things: grass, flowers, pebbles.

const FOLIAGE_SHADER := preload("res://src/render/shaders/foliage.gdshader")
const WATER_SHADER := preload("res://src/render/shaders/water.gdshader")
const TOXIC_SHADER := preload("res://src/render/shaders/toxic.gdshader")
## Tallest a decoration on open ground may be (a size-1 mech is about 1 unit tall).
const FLAT := 0.18
## Rough-ground clutter per ground style.
const ROUGH := {"grass": "stones", "sand": "scree", "snow": "ice", "moss": "stones", "paving": "rubble", "ash": "cinders"}


static func build(t: TerrainRenderer, root: Node3D) -> void:
	_liquids(t, root)
	_ground_cover(t, root)
	_rough(t, root)
	_woods(t, root)
	_rocks(t, root)
	WorldHazards.build(t, root)
	WorldHorizon.build(t, root)
	WorldParticles.build(t, root)


static func foliage_material(sway: float, sway_height: float, leafy: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_height", sway_height)
	m.set_shader_parameter("leafy", leafy)
	return m


## One MultiMeshInstance3D of `mesh` at `xforms`.
static func multi(root: Node3D, node_name: String, mesh: Mesh, xforms: Array, mat: Material, shadows: bool = true) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


static func _colors(t: TerrainRenderer, path: String) -> Array[Color]:
	var out: Array[Color] = []
	for v: Variant in WorldStyle.value(t.style, path, []):
		out.append(WorldStyle.color(v))
	return out


static func _pick(list: Array, h: float) -> Variant:
	return list[int(h * list.size()) % list.size()]


# --- Liquids ---------------------------------------------------------------------------

static func _liquids(t: TerrainRenderer, root: Node3D) -> void:
	var by_tag := {}
	for c in t.map.cells():
		var l := t.liquid_of(c)
		if l != "":
			if not by_tag.has(l):
				by_tag[l] = []
			(by_tag[l] as Array).append(c)
	for tag: String in by_tag:
		var kind := tag
		if tag == "water":
			kind = str(WorldStyle.value(t.style, "liquid.kind", "water"))
		var m := ShaderMaterial.new()
		var depth := 0.3
		match kind:
			"toxic":
				m.shader = TOXIC_SHADER
				m.set_shader_parameter("glow", WorldStyle.col(t.style, "liquid.shallow", Color(0.45, 1.0, 0.25)))
				m.set_shader_parameter("deep", WorldStyle.col(t.style, "liquid.deep", Color(0.05, 0.18, 0.05)))
				depth = 0.25
			"lava":
				m.shader = TOXIC_SHADER
				m.set_shader_parameter("glow", Color(1.0, 0.42, 0.06))
				m.set_shader_parameter("deep", Color(0.25, 0.04, 0.01))
				m.set_shader_parameter("lava", 1.0)
				depth = 0.2
			_:
				m.shader = WATER_SHADER
				m.set_shader_parameter("shallow", WorldStyle.col(t.style, "liquid.shallow", Color(0.16, 0.34, 0.36)))
				m.set_shader_parameter("deep", WorldStyle.col(t.style, "liquid.deep", Color(0.05, 0.16, 0.22)))
				if kind == "ice":
					m.set_shader_parameter("ice", 1.0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c: Vector2i in by_tag[tag]:
			var y := t.top_y(c) + depth
			var pts := t.cell_corners(c, y, -0.02)
			var center := t.map.grid.to_world(c) + Vector3.UP * y
			for i in range(pts.size()):
				MeshKit.add_tri(st, center, pts[i], pts[(i + 1) % pts.size()], Vector3.UP)
		var mi := MeshInstance3D.new()
		mi.name = "Liquid_" + tag
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# --- Ground cover ------------------------------------------------------------------------

## Grass tufts, flowers and pebbles: never taller than FLAT.
static func _ground_cover(t: TerrainRenderer, root: Node3D) -> void:
	var density := int(WorldStyle.num(t.style, "flora.grass", 0.0))
	var greens := _colors(t, "flora.grass_colors")
	var flowers := _colors(t, "flora.flowers")
	var tall := WorldStyle.num(t.style, "flora.grass_height", 1.0)
	var groups := {}
	var fgroups := {}
	var pebbles: Array = []
	for c in t.map.cells():
		var kind := t.surface(c)
		if t.structure_cells.has(c) or not (kind == TerrainRenderer.KIND_GROUND or kind == TerrainRenderer.KIND_ROUGH or kind == TerrainRenderer.KIND_ROCK):
			continue
		var key := "g" + str(c)
		var n := density
		if kind == TerrainRenderer.KIND_ROUGH:
			n = density / 2
		elif kind == TerrainRenderer.KIND_ROCK:
			n = density / 4
		if t.is_woods(c):
			n += 3
		for i in range(n if not greens.is_empty() else 0):
			var p := t.random_point(c, key, i)
			var s := (0.09 + 0.09 * WorldRand.f(key, i + 100)) * tall
			var flower := not flowers.is_empty() and WorldRand.f(key, i + 200) < 0.07
			var basis := Basis(Vector3.UP, WorldRand.f(key, i + 150) * TAU)
			if flower:
				var fc: Color = _pick(flowers, WorldRand.f(key, i + 260))
				if not fgroups.has(fc):
					fgroups[fc] = []
				(fgroups[fc] as Array).append(Transform3D(basis.scaled(Vector3.ONE * minf(s * 1.1, FLAT)), p))
			else:
				var g: Color = _pick(greens, WorldRand.f(key, i + 250))
				if not groups.has(g):
					groups[g] = []
				(groups[g] as Array).append(Transform3D(basis.scaled(Vector3(s * 1.5, minf(s, FLAT), s * 1.5)), p))
		if kind == TerrainRenderer.KIND_GROUND and WorldRand.f(key, 900) < 0.25:
			var p := t.random_point(c, key, 901, 0.8)
			var s := 0.04 + 0.05 * WorldRand.f(key, 902)
			pebbles.append(Transform3D(Basis(Vector3.UP, WorldRand.f(key, 903) * TAU).scaled(Vector3(s * 1.4, s * 0.5, s)), p))
	var mat := foliage_material(0.22, 1.0, 0.0)
	for g: Color in groups:
		multi(root, "Grass", Flora.tuft(g), groups[g], mat, false)
	for f: Color in fgroups:
		multi(root, "Flowers", Flora.flower(f), fgroups[f], mat, false)
	var stone := WorldStyle.col(t.style, "flora.stones", Color(0.5, 0.48, 0.45))
	multi(root, "Pebbles", Flora.rock(stone, 0), pebbles, foliage_material(0.0, 1.0, 0.0), false)


## Difficult ground: clutter that reads as hard going but stays well below cover height.
static func _rough(t: TerrainRenderer, root: Node3D) -> void:
	var gstyle := str(WorldStyle.value(t.style, "ground.style", "grass"))
	var look := str(WorldStyle.value(t.style, "flora.rough", ROUGH.get(gstyle, "stones")))
	var stone := WorldStyle.col(t.style, "flora.stones", Color(0.5, 0.48, 0.45))
	var chunks: Array = [[], [], []]
	var sticks: Array = []
	for c in t.map.cells():
		if t.surface(c) != TerrainRenderer.KIND_ROUGH or t.structure_cells.has(c):
			continue
		var key := "r" + str(c)
		var n := 7 if look in ["rubble", "scree"] else 5
		for i in range(n):
			var p := t.random_point(c, key, i, 0.8)
			var s := 0.07 + 0.11 * WorldRand.f(key, i + 20)
			var flat := 0.45 if look != "ice" else 0.6
			var b := Basis(Vector3.UP, WorldRand.f(key, i + 30) * TAU) * Basis(Vector3.RIGHT, (WorldRand.f(key, i + 40) - 0.5) * 0.6)
			chunks[i % 3].append(Transform3D(b.scaled(Vector3(s * 1.3, minf(s * flat, FLAT * 0.8), s)), p + Vector3.UP * s * 0.12))
		if look == "rubble" and WorldRand.f(key, 99) < 0.6:
			var p := t.random_point(c, key, 98, 0.6)
			sticks.append(Transform3D(Basis(Vector3.UP, WorldRand.f(key, 97) * TAU) * Basis(Vector3.FORWARD, 1.2), p + Vector3.UP * 0.05))
	var col := stone
	match look:
		"rubble":
			col = WorldStyle.col(t.style, "ground.wall", Color(0.55, 0.52, 0.48))
		"ice":
			col = Color(0.78, 0.88, 0.95)
		"cinders":
			col = Color(0.12, 0.1, 0.09)
	var mat := foliage_material(0.0, 1.0, 0.0)
	for i in range(3):
		var tint := col.darkened(0.12 * i) if look != "rubble" or i < 2 else Color(0.3, 0.29, 0.28)
		multi(root, "Rough", Flora.rock(tint, 10 + i), chunks[i], mat, true)
	if not sticks.is_empty():
		var rebar := MeshKit.mech_material(Color(0.35, 0.2, 0.12), 0.5, 0.7, Color.BLACK, false)
		multi(root, "Rebar", MeshKit.cylinder(0.012, 0.35, 4), sticks, rebar, false)


# --- Woods (soft cover) ------------------------------------------------------------------

## Trees and brush on every soft_cover cell, kept inside the cell so neighbors stay clear.
static func _woods(t: TerrainRenderer, root: Node3D) -> void:
	var species: Array = WorldStyle.value(t.style, "flora.woods", ["broadleaf"])
	var leaves := _colors(t, "flora.leaf_colors")
	if leaves.is_empty():
		leaves = [Color(0.2, 0.35, 0.12)]
	var bark := WorldStyle.col(t.style, "flora.bark", Color(0.3, 0.22, 0.15))
	var groups := {}
	for c in t.map.cells():
		if not t.is_woods(c) or t.structure_cells.has(c):
			continue
		var key := "w" + str(c)
		var count := 2 + int(WorldRand.f(key, 0) * 2.0)
		for i in range(count):
			var sp: String = _pick(species, WorldRand.f(key, i + 10))
			var leaf: Color = _pick(leaves, WorldRand.f(key, i + 20))
			var variant := int(WorldRand.f(key, i + 30) * 3.0)
			var p := t.random_point(c, key, i + 40, 0.45 if i > 0 else 0.15)
			var s := 0.62 + 0.22 * WorldRand.f(key, i + 50)
			if sp in ["bush", "shrub"]:
				s *= 1.3
			var g := "%s|%s|%d" % [sp, leaf.to_html(), variant]
			if not groups.has(g):
				groups[g] = [sp, leaf, variant, []]
			(groups[g][3] as Array).append(Transform3D(Basis(Vector3.UP, WorldRand.f(key, i + 60) * TAU).scaled(Vector3.ONE * s), p))
	var mat := foliage_material(0.035, 1.6)
	for g: String in groups:
		var e: Array = groups[g]
		multi(root, "Woods", Flora.plant(e[0], e[1], bark, e[2]), e[3], mat, true)


# --- Rock outcrops -----------------------------------------------------------------------

## Rock columns become stacks of big faceted boulders that fill the column and are clipped
## flat at its exact top (so where a mech stands is plain to see) and at its foot. They bulge
## past the cell edge by a few centimeters at most; the column is solid hard cover anyway.
static func _rocks(t: TerrainRenderer, root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in t.map.cells():
		if t.surface(c) != TerrainRenderer.KIND_ROCK or t.structure_cells.has(c):
			continue
		any = true
		var top := t.top_y(c)
		var low := top
		for n in t.map.grid.neighbors(c):
			low = minf(low, t.floor_y(n) if t.map.has_cell(n) else -TerrainRenderer.BASE_DEPTH)
		low = maxf(low, -TerrainRenderer.BASE_DEPTH)
		if top - low < 0.2:
			continue
		var center := t.map.grid.to_world(c)
		var key := "rk" + str(c)
		var layers := maxi(1, int(ceil((top - low) / 0.8)))
		for k in range(layers):
			var y := low + (k + 0.5) * (top - low) / layers
			var rad := 0.58 + 0.06 * WorldRand.f(key, k)
			var basis := Basis(Vector3.UP, WorldRand.f(key, k + 10) * TAU) * Basis(Vector3.RIGHT, (WorldRand.f(key, k + 20) - 0.5) * 0.5)
			var b := Flora.blob(rad, key + str(k), 0.22, 1.0, 9)
			var verts: PackedVector3Array = b[0]
			var idx: PackedInt32Array = b[2]
			var half := (top - low) / layers * 0.5 + 0.35
			for tri in range(0, idx.size(), 3):
				var pts: Array[Vector3] = []
				for q in range(3):
					var v := basis * verts[idx[tri + q]]
					v.y = clampf(v.y * half / rad, -half, half) + y
					v.y = clampf(v.y, low - 0.05, top - 0.004)
					var flat := Vector2(v.x, v.z)
					if flat.length() > 0.56:
						flat = flat.normalized() * 0.56
					pts.append(center + Vector3(flat.x, v.y, flat.y))
				var nrm := (pts[1] - pts[0]).cross(pts[2] - pts[0])
				if nrm.length() < 1e-6:
					continue
				nrm = nrm.normalized()
				# Front faces point away from the column's core.
				var mid := (pts[0] + pts[1] + pts[2]) / 3.0
				var out := mid - Vector3(center.x, y, center.z)
				if nrm.dot(out) < 0.0:
					nrm = -nrm
					pts = [pts[0], pts[2], pts[1]]
				var flat_top := absf(mid.y - (top - 0.004)) < 0.001
				st.set_color(Color(TerrainRenderer.KIND_ROCK / 16.0, WorldRand.f(str(c)) if flat_top else WorldRand.f(key, tri), 0.0, 1.0))
				st.set_uv2(Vector2(0, top))
				for q in [0, 2, 1]:
					st.set_normal(Vector3.UP if flat_top else nrm)
					st.add_vertex(pts[q])
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "RockStacks"
	mi.mesh = st.commit()
	mi.material_override = t.material
	root.add_child(mi)
