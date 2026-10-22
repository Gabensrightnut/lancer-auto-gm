class_name WorldHorizon
extends RefCounted
## Everything beyond the board, so a battle never floats in a void: land that carries on from
## the board's edge heights and rolls away into hills, mesas or spires (style horizon.land),
## woods on it, and a far ring of mountains, mesas, volcanoes, a city skyline or alien
## megastructures (horizon.far), plus an optional storm wall. None of it is on the map.

const FAR_SHADER := preload("res://src/render/shaders/storm.gdshader")
const FAR_LAND := preload("res://src/render/shaders/far_land.gdshader")
const LAND_EXT := 150.0


static func build(t: TerrainRenderer, root: Node3D) -> void:
	var hz: Dictionary = t.style.get("horizon", {})
	var land := str(hz.get("land", "hills"))
	var b := t.bounds(0.0)
	var edge := _edge_sampler(t, b)
	var rivers := _rivers(t, b)
	var height_fn := func(x: float, z: float) -> float:
		var h := _height(x, z, b, edge, land, float(hz.get("land_height", 8.0)))
		for r: Dictionary in rivers:
			var k := _carve(r, x, z)
			if k > 0.0:
				h = lerpf(h, float(r["y"]) - 0.35, k)
		return h
	_land(t, root, b, height_fn)
	_river_water(t, root, rivers)
	_forest(t, root, b, height_fn, float(hz.get("forest", 0.0)))
	var far_kind := str(hz.get("far", "mountains"))
	if far_kind in ["mountains", "mesas", "volcanoes"]:
		# A nearer, darker layer of foothills in front of the far range.
		_ring(root, b, t.style, "foothills", 95.0, 5, 14.0, float(hz.get("land_height", 8.0)) * 2.2)
	match far_kind:
		"mountains":
			_ring(root, b, t.style, "mountains")
		"mesas":
			_ring(root, b, t.style, "mesas")
		"volcanoes":
			_ring(root, b, t.style, "volcanoes")
		"megastructures":
			_ring(root, b, t.style, "spires")
			_megastructures(root, b)
		"skyline":
			Skyline.build(t, root, b)
	if hz.get("storm", false):
		_storm(root, b, t.style)


## Liquids that reach the board's edge carry on outside: a meandering channel for each run
## of edge cells on one side. Returns [{pts: Array[Vector2], width, y, kind}].
static func _rivers(t: TerrainRenderer, b: Rect2) -> Array:
	var sides := {}
	for c in t.map.cells():
		var l := t.liquid_of(c)
		if l == "":
			continue
		var open := false
		for n in t.map.grid.neighbors(c):
			if not t.map.has_cell(n):
				open = true
				break
		if not open:
			continue
		var p := t.map.grid.to_world(c)
		var d := [p.x - b.position.x, b.end.x - p.x, p.z - b.position.y, b.end.y - p.z]
		var side := 0
		for i in range(4):
			if d[i] < d[side]:
				side = i
		if d[side] > 1.0:
			continue
		var key := "%d|%s" % [side, l]
		if not sides.has(key):
			sides[key] = []
		(sides[key] as Array).append([c, p])
	var out: Array = []
	var dirs := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	for key: String in sides:
		var side := int(key.split("|")[0])
		var along_x := side >= 2
		var list: Array = sides[key]
		list.sort_custom(func(a: Array, c: Array) -> bool: return ((a[1] as Vector3).x if along_x else (a[1] as Vector3).z) < ((c[1] as Vector3).x if along_x else (c[1] as Vector3).z))
		# Split into runs of neighboring cells.
		var runs: Array = [[list[0]]]
		for i in range(1, list.size()):
			var prev: Vector3 = (runs[-1] as Array)[-1][1]
			var cur: Vector3 = list[i][1]
			if (cur.x - prev.x if along_x else cur.z - prev.z) > 1.3:
				runs.append([])
			(runs[-1] as Array).append(list[i])
		for run: Array in runs:
			var lo: Vector3 = run[0][1]
			var hi: Vector3 = run[-1][1]
			var mid := (lo + hi) * 0.5
			var width := (hi.x - lo.x if along_x else hi.z - lo.z) + 1.0
			var dir: Vector2 = dirs[side]
			var lateral := Vector2(dir.y, -dir.x)
			var start := Vector2(mid.x, mid.z)
			match side:
				0: start.x = b.position.x - 0.5
				1: start.x = b.end.x + 0.5
				2: start.y = b.position.y - 0.5
				_: start.y = b.end.y + 0.5
			var pts: Array[Vector2] = []
			var seed := WorldRand.f(key, run.size()) * 10.0
			for i in range(40):
				var dist := i * 2.0
				var wiggle := sin(dist * 0.07 + seed) * minf(dist * 0.25, 7.0) + sin(dist * 0.19 + seed * 2.0) * minf(dist * 0.1, 2.0)
				pts.append(start - dir * 0.6 + dir * dist + lateral * wiggle)
			var c0: Vector2i = run[0][0]
			out.append({"pts": pts, "width": width, "y": t.top_y(c0) - TerrainRenderer.LIQUID_SURFACE, "kind": t.liquid_of(c0),
				"box": _poly_box(pts).grow(width * 0.5 + 3.0)})
	return out


static func _poly_box(pts: Array[Vector2]) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## How much a point is carved into a river channel: 1 in the bed, 0 past the banks.
static func _carve(r: Dictionary, x: float, z: float) -> float:
	var q := Vector2(x, z)
	if not (r["box"] as Rect2).has_point(q):
		return 0.0
	var pts: Array[Vector2] = r["pts"]
	var best := INF
	for i in range(pts.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1]).distance_to(q))
	var half := float(r["width"]) * 0.5
	return 1.0 - smoothstep(half - 0.1, half + 2.2, best)


## Water ribbons along the river channels.
static func _river_water(t: TerrainRenderer, root: Node3D, rivers: Array) -> void:
	for r: Dictionary in rivers:
		var pts: Array[Vector2] = r["pts"]
		var half := float(r["width"]) * 0.5 + 0.35
		var y := float(r["y"])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(pts.size() - 1):
			var d0 := (pts[i + 1] - pts[i]).normalized()
			var d1 := (pts[mini(i + 2, pts.size() - 1)] - pts[i + 1]).normalized() if i + 2 < pts.size() else d0
			var n0 := Vector2(-d0.y, d0.x) * half
			var n1 := Vector2(-d1.y, d1.x) * half
			var a := Vector3(pts[i].x - n0.x, y, pts[i].y - n0.y)
			var bb := Vector3(pts[i].x + n0.x, y, pts[i].y + n0.y)
			var c := Vector3(pts[i + 1].x + n1.x, y, pts[i + 1].y + n1.y)
			var d := Vector3(pts[i + 1].x - n1.x, y, pts[i + 1].y - n1.y)
			MeshKit.add_quad(st, a, bb, c, d, Vector3.UP)
		var mi := MeshInstance3D.new()
		mi.name = "River"
		mi.mesh = st.commit()
		var liquid := t.find_child("Liquid_" + str(r["kind"]), true, false) as MeshInstance3D
		if liquid:
			mi.material_override = liquid.material_override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi, true)


## Returns a function giving the ground height at the nearest board cell to (x, z).
static func _edge_sampler(t: TerrainRenderer, b: Rect2) -> Callable:
	var cache := {}
	return func(x: float, z: float) -> float:
		var cx := clampf(x, b.position.x, b.end.x)
		var cz := clampf(z, b.position.y, b.end.y)
		var cell := t.map.grid.from_world(Vector3(cx, 0, cz))
		if cache.has(cell):
			return cache[cell]
		# The lowest ground among this edge cell and its neighbors, so a lone pillar or wall
		# at the edge doesn't drag the land up into a ramp.
		var h := INF
		var around: Array[Vector2i] = [cell]
		around.append_array(t.map.grid.neighbors(cell))
		for n in around:
			if t.map.has_cell(n):
				h = minf(h, maxf(t.floor_y(n), 0.0))
		if h == INF:
			h = 0.0
		cache[cell] = h
		return h


static func _dist(x: float, z: float, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


static func _height(x: float, z: float, b: Rect2, edge: Callable, land: String, amp: float) -> float:
	var d := _dist(x, z, b)
	# Flat (city) land stays at street level next to the board even where edge cells are tall.
	var near: float = (edge.call(x, z) if land != "flat" else 0.0) - 0.03
	var n := DemoMap.fbm(x * 0.035 + 11.0, z * 0.035 + 3.0)
	var detail := DemoMap.fbm(x * 0.3, z * 0.3) * 0.5
	var far := 0.0
	match land:
		"flat":
			far = 0.15 * detail
		"mesas":
			var plateau := smoothstep(0.52, 0.56, n) * amp * (0.6 + 0.4 * floorf(DemoMap.fbm(x * 0.02, z * 0.02) * 3.0) / 2.0)
			far = detail * 0.8 + plateau
		"spires":
			var mesa := floorf(n * 6.0) / 6.0 * amp * 0.8
			var spire := pow(maxf(0.0, DemoMap.fbm(x * 0.22, z * 0.22) - 0.64), 1.5) * amp * 5.0
			far = mesa + spire * smoothstep(20.0, 40.0, d)
		_:
			far = n * amp + detail - amp * 0.25
	var k := smoothstep(1.5, 26.0, d)
	return lerpf(near, maxf(far, near - 1.0 if land != "flat" else near), k)


static func _coords(lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := lo
	var step := 0.5
	var left: Array[float] = []
	while x > lo - LAND_EXT:
		x -= step
		step *= 1.075
		left.append(x)
	left.reverse()
	for v in left:
		out.append(v)
	var n := maxi(1, int((hi - lo) / 1.0))
	for i in range(n + 1):
		out.append(lerpf(lo, hi, float(i) / n))
	x = hi
	step = 0.5
	while x < hi + LAND_EXT:
		x += step
		step *= 1.075
		out.append(x)
	return out


static func _land(t: TerrainRenderer, root: Node3D, b: Rect2, height_fn: Callable) -> void:
	var xs := _coords(b.position.x, b.end.x)
	var zs := _coords(b.position.y, b.end.y)
	var hs := PackedFloat32Array()
	hs.resize(xs.size() * zs.size())
	for j in range(zs.size()):
		for i in range(xs.size()):
			hs[j * xs.size() + i] = height_fn.call(xs[i], zs[j])
	var inner := b.grow(-0.3)
	var w := xs.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert := func(i: int, j: int) -> void:
		var p := Vector3(xs[i], hs[j * w + i], zs[j])
		var il := maxi(i - 1, 0)
		var ir := mini(i + 1, w - 1)
		var jl := maxi(j - 1, 0)
		var jr := mini(j + 1, zs.size() - 1)
		var dx := Vector3(xs[ir] - xs[il], hs[j * w + ir] - hs[j * w + il], 0)
		var dz := Vector3(0, hs[jr * w + i] - hs[jl * w + i], zs[jr] - zs[jl])
		var n := dz.cross(dx).normalized()
		if n.y < 0:
			n = -n
		var dist := _dist(p.x, p.z, b)
		var dim := 0.1 * smoothstep(0.0, 2.0, dist) + 0.25 * smoothstep(20.0, 140.0, dist)
		st.set_color(Color(TerrainRenderer.KIND_GROUND / 16.0, WorldRand.f("l", i * 1000 + j), dim, 1.0))
		# Soil/stone depth on slopes: measure from a little above this point.
		st.set_uv2(Vector2(0, p.y + 0.05))
		st.set_normal(n)
		st.add_vertex(p)
	for j in range(zs.size() - 1):
		for i in range(w - 1):
			var mid := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			if inner.has_point(mid):
				continue
			# Clockwise seen from above = front face up.
			for k: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				vert.call(k[0], k[1])
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = st.commit()
	mi.material_override = t.material
	root.add_child(mi)


## Woods on the land around the board: full trees close by, simple ones further out.
static func _forest(t: TerrainRenderer, root: Node3D, b: Rect2, height_fn: Callable, density: float) -> void:
	if density <= 0.0:
		return
	var species: Array = WorldStyle.value(t.style, "flora.woods", ["broadleaf"])
	var leaves: Array = WorldStyle.value(t.style, "flora.leaf_colors", ["#2f5418"])
	var bark := WorldStyle.col(t.style, "flora.bark", Color(0.3, 0.22, 0.15))
	var groups := {}
	var n := 0
	var reach := 70.0
	var area := (b.size.x + 2.0 * reach) * (b.size.y + 2.0 * reach)
	var tries := int(area * 0.09 * density)
	for i in range(tries):
		n += 1
		var x := b.position.x - reach + WorldRand.f("fx", n) * (b.size.x + 2.0 * reach)
		var z := b.position.y - reach + WorldRand.f("fz", n) * (b.size.y + 2.0 * reach)
		var d := _dist(x, z, b)
		if d < 2.2:
			continue
		var f := DemoMap.fbm(x * 0.06 + 5.0, z * 0.06 + 1.0)
		var keep := smoothstep(0.42, 0.55, f) * (0.35 + 0.65 * smoothstep(2.0, 12.0, d)) * (1.0 - smoothstep(45.0, 70.0, d))
		if WorldRand.f("fk", n) > keep:
			continue
		var sp: String = species[int(WorldRand.f("fs", n) * species.size()) % species.size()]
		var far := d > 26.0
		var variant := int(WorldRand.f("fv", n) * 3.0)
		var leaf := WorldStyle.color(leaves[int(WorldRand.f("fl", n) * leaves.size()) % leaves.size()])
		var key := "%s|%s|%d|%s" % [sp, leaf.to_html(), variant, far]
		if not groups.has(key):
			groups[key] = [sp, leaf, variant, far, []]
		var s := (1.1 + 0.9 * WorldRand.f("fsz", n)) * (1.0 + 0.3 * smoothstep(5.0, 30.0, d))
		var y: float = height_fn.call(x, z)
		(groups[key][4] as Array).append(Transform3D(Basis(Vector3.UP, WorldRand.f("fr", n) * TAU).scaled(Vector3.ONE * s), Vector3(x, y - 0.05, z)))
	var mat := WorldDressing.foliage_material(0.03, 2.2)
	var far_mat := WorldDressing.foliage_material(0.0, 2.0, 0.6)
	for k: String in groups:
		var e: Array = groups[k]
		var mesh: Mesh = Flora.plant(e[0], e[1], bark, e[2]) if not e[3] else _far_tree(e[0], e[1], bark)
		WorldDressing.multi(root, "Forest", mesh, e[4], far_mat if e[3] else mat, not e[3])


## A cheap tree for far away: a trunk and one or two clumps.
static func _far_tree(species: String, leaf: Color, bark: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lf := Color(leaf.r, leaf.g, leaf.b, 0.5)
	if species in ["conifer", "snow_conifer"]:
		Flora.add(st, Flora._arrays(MeshKit.cylinder(0.45, 1.6, 6, 0.0)), Transform3D(Basis(), Vector3(0, 1.0, 0)), lf, 0.4)
	elif species in ["cactus", "shrub", "dead_tree"]:
		return Flora.plant(species, leaf, bark, 0)
	else:
		Flora.add(st, Flora._arrays(MeshKit.cylinder(0.06, 0.7, 5, 0.04)), Transform3D(Basis(), Vector3(0, 0.35, 0)), bark, 0.2)
		Flora.add(st, Flora.blob(0.55, species, 0.2, 0.85, 7), Transform3D(Basis(), Vector3(0, 1.05, 0)), lf, 0.5)
	return st.commit()


## A far ring of big landforms, hazed by fog into silhouettes.
static func _ring(root: Node3D, b: Rect2, style: Dictionary, kind: String, start: float = 170.0, rows: int = 8, spacing: float = 18.0, height: float = -1.0) -> void:
	var hz: Dictionary = style.get("horizon", {})
	var base := WorldStyle.color(hz.get("far_color", "#6d7f95"))
	var amp := float(hz.get("far_height", 50.0)) if height < 0.0 else height
	var snow := bool(hz.get("snowcaps", false)) and kind == "mountains"
	if kind == "foothills":
		base = base.lerp(WorldStyle.col(style, "ground.top_a", base), 0.6).darkened(0.45)
	var c := b.get_center()
	var r0 := start + maxf(b.size.x, b.size.y) * 0.5
	var steps := 260
	var hot := WorldStyle.col(style, "ground.hazard", Color(1.0, 0.4, 0.1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for j in range(rows + 1):
		var row: Array = []
		var rr := r0 + j * spacing
		for i in range(steps + 1):
			var a := TAU * float(i) / steps
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			var u := float(i) / steps * 40.0
			var prof := pow(sin(PI * 0.5 * float(j) / rows + 0.0001), 0.7) * (1.0 - smoothstep(0.85, 1.0, float(j) / rows))
			var h := 0.0
			match kind:
				"mesas":
					var m := DemoMap.fbm(u * 0.35, j * 0.4)
					h = (smoothstep(0.45, 0.5, m) * 0.6 + smoothstep(0.62, 0.66, m) * 0.4) * amp * prof
				"volcanoes":
					var peak := DemoMap.fbm(u * 0.25, 3.0)
					var cone := maxf(0.0, 1.0 - absf(fposmod(u * 0.18, 1.0) - 0.5) * 3.2)
					h = (DemoMap.fbm(u * 0.6, j * 0.5) * 0.4 + cone * (0.6 + 0.6 * peak)) * amp * prof
				"spires":
					var sp := pow(maxf(0.0, DemoMap.fbm(u * 1.4, j * 0.9) - 0.5), 1.6) * 6.0
					h = (DemoMap.fbm(u * 0.4, j * 0.5) * 0.5 + sp) * amp * prof
				"foothills":
					h = (DemoMap.fbm(u * 0.9 + 7.0, j * 0.6) * 0.8 + 0.2) * amp * prof
				_:
					var ridge := 1.0 - absf(DemoMap.fbm(u * 0.5, j * 0.3) * 2.0 - 1.0)
					h = (pow(ridge, 1.6) * 0.85 + DemoMap.fbm(u * 2.0, j) * 0.25) * amp * prof
			row.append(Vector3(x, h - 2.0, z))
		pts.append(row)
	for j in range(rows):
		for i in range(steps):
			var q: Array = [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			var qrow: Array = [j, j, j + 1, j + 1]
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri:
					var p: Vector3 = q[k]
					st.set_uv(Vector2(float(qrow[k]) / rows, 0.0))
					var col := base.darkened(0.25 * DemoMap.fbm(p.x * 0.05, p.z * 0.05))
					if snow and p.y > amp * 0.62 + 8.0 * DemoMap.fbm(p.x * 0.1, p.z * 0.1):
						col = Color(0.92, 0.94, 0.98)
					if kind == "volcanoes" and p.y > amp * 0.8:
						col = col.lerp(hot, 0.6)
					st.set_color(col)
					st.add_vertex(p)
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "FarRing_" + kind
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = FAR_LAND
	var haze := WorldStyle.color(hz.get("haze_color", WorldStyle.value(style, "sky.horizon", "#c8c0b8")))
	m.set_shader_parameter("haze_color", haze)
	var near_far: Array = hz.get("haze_" + kind, [0.12, 0.35] if kind == "foothills" else [0.35, 0.72])
	m.set_shader_parameter("haze_near", float(near_far[0]))
	m.set_shader_parameter("haze_far", float(near_far[1]))
	m.set_shader_parameter("base_y", -2.0)
	m.set_shader_parameter("top_y", amp)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if kind == "volcanoes":
		_volcano_glow(root, pts, amp, hot)


## Glowing smoke columns over the tallest far peaks.
static func _volcano_glow(root: Node3D, pts: Array, amp: float, hot: Color) -> void:
	var tops: Array[Vector3] = []
	for row: Array in pts:
		for p: Vector3 in row:
			if p.y > amp * 0.85:
				var near := false
				for q in tops:
					if q.distance_to(p) < 60.0:
						near = true
						break
				if not near:
					tops.append(p)
	for p in tops.slice(0, 4):
		var smoke := CPUParticles3D.new()
		smoke.amount = 60
		smoke.lifetime = 14.0
		smoke.preprocess = 14.0
		smoke.direction = Vector3(0.3, 1, 0)
		smoke.spread = 12.0
		smoke.gravity = Vector3(1.0, 0.5, 0)
		smoke.initial_velocity_min = 3.0
		smoke.initial_velocity_max = 5.0
		smoke.scale_amount_min = 0.7
		smoke.scale_amount_max = 1.6
		smoke.position = p
		var q := QuadMesh.new()
		q.size = Vector2(14, 14)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = Fx.soft_texture()
		m.vertex_color_use_as_albedo = true
		q.material = m
		smoke.mesh = q
		smoke.color_ramp = WorldHazards._ramp([[0.0, Color(hot.r * 1.5, hot.g, hot.b * 0.5, 0.7)], [0.25, Color(0.2, 0.15, 0.14, 0.5)], [1.0, Color(0.15, 0.13, 0.13, 0.0)]])
		smoke.visibility_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 300, 400))
		root.add_child(smoke)


## Colossal ancient structures: an arch, a broken ring standing on edge and obelisks with
## faint glowing lines. Far enough out that fog turns them into silhouettes.
static func _megastructures(root: Node3D, b: Rect2) -> void:
	var stone := MeshKit.paint(Color(0.1, 0.09, 0.12), 0.5, 0.6, 0.0)
	var lines := MeshKit.paint(Color(0.05, 0.05, 0.05), 0.2, 0.3, 0.0, Color(0.35, 0.9, 1.0))
	var c := Vector3(b.get_center().x, -1.0, b.get_center().y)
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
		var a := deg_to_rad(-150.0 + i * 38.0 + WorldRand.f("ob", i) * 12.0)
		var r := 80.0 + 30.0 * WorldRand.f("obr", i)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r * 0.9)
		var h := 25.0 + 40.0 * WorldRand.f("obh", i)
		var ob := MeshKit.part(root, SmoothKit.loft([{"y": 0.0, "w": 5.0, "d": 5.0, "n": 6.0}, {"y": h * 0.9, "w": 2.6, "d": 2.6, "n": 6.0}, {"y": h, "w": 0.3, "d": 0.3, "n": 6.0}]), stone, p)
		MeshKit.part(ob, MeshKit.chamfer_box(Vector3(0.25, h * 0.7, 0.25), 0.04), lines, Vector3(0, h * 0.4, -2.0))


## A curved cloud wall on part of the horizon, flickering with lightning.
static func _storm(root: Node3D, b: Rect2, style: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(b.get_center().x, -2.0, b.get_center().y)
	var r := 150.0 + maxf(b.size.x, b.size.y) * 0.5
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
	m.shader = FAR_SHADER
	var sc: Variant = WorldStyle.value(style, "horizon.storm_color")
	if sc != null:
		m.set_shader_parameter("cloud", WorldStyle.color(sc))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
