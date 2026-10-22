class_name Flora
extends RefCounted
## Plant meshes made in code: trees, bushes, cacti, alien growths, grass tufts and rocks.
## Each is one mesh with vertex colors (sRGB): alpha 1 = wood/bark, alpha < 1 = foliage
## (the foliage shader lights it softly and sways it; alpha 0 also glows for alien plants).
## Sizes are in board units for scale 1: a size-1 mech is about 1 unit tall.

static var _cache: Dictionary = {}


## A noise-displaced sphere (a leaf clump or boulder).
static func blob(radius: float, seed_key: String, rough: float = 0.25, squash: float = 1.0, segments: int = 10) -> Array:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segments
	sm.rings = maxi(4, segments / 2)
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var s := float(hash(seed_key) % 1000)
	for i in range(verts.size()):
		var v := verts[i]
		var d := v.normalized() if v.length() > 0.0001 else Vector3.UP
		var n := sin(d.x * 5.1 + s) * sin(d.y * 4.3 + s * 0.7) * sin(d.z * 6.2 + s * 1.3) + 0.5 * sin(d.x * 11.0 - d.z * 9.0 + s)
		var r := radius * (1.0 + rough * n)
		verts[i] = Vector3(d.x * r, d.y * r * squash, d.z * r)
		norms[i] = d
	return [verts, norms, arr[Mesh.ARRAY_INDEX]]


## Appends mesh arrays to `st` with a transform and a color; `shade` darkens the underside.
static func add(st: SurfaceTool, mesh_arrays: Array, xf: Transform3D, color: Color, shade: float = 0.35) -> void:
	var verts: PackedVector3Array = mesh_arrays[0]
	var norms: PackedVector3Array = mesh_arrays[1]
	var idx: PackedInt32Array = mesh_arrays[2]
	for k in idx:
		var n := (xf.basis * norms[k]).normalized()
		var c := color
		var ao := 1.0 - shade * clampf(0.5 - n.y * 0.5, 0.0, 1.0)
		c = Color(c.r * ao, c.g * ao, c.b * ao, c.a)
		st.set_color(c)
		st.set_normal(n)
		st.add_vertex(xf * verts[k])


static func _arrays(m: Mesh) -> Array:
	var a := m.surface_get_arrays(0)
	return [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX]]


static func _trunk(st: SurfaceTool, bottom: Vector3, top: Vector3, r0: float, r1: float, color: Color) -> void:
	var len := bottom.distance_to(top)
	var cyl := MeshKit.cylinder(r0, len, 7, r1)
	var up := (top - bottom).normalized()
	var basis := Basis()
	if absf(up.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(up).normalized()
		basis = Basis(axis, Vector3.UP.angle_to(up))
	add(st, _arrays(cyl), Transform3D(basis, (bottom + top) * 0.5), color, 0.2)


## Mesh for a plant species. `leaf` and `bark` are sRGB colors; variant picks a shape.
static func plant(species: String, leaf: Color, bark: Color, variant: int = 0) -> ArrayMesh:
	var key := "%s|%s|%s|%d" % [species, leaf.to_html(), bark.to_html(), variant]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := "%s%d" % [species, variant]
	var lf := Color(leaf.r, leaf.g, leaf.b, 0.5)
	match species:
		"conifer", "snow_conifer":
			var h := 1.7 + 0.5 * _r(k, 0)
			_trunk(st, Vector3.ZERO, Vector3(0, h * 0.4, 0), 0.06, 0.04, bark)
			var tiers := 5
			for i in range(tiers):
				var t := float(i) / tiers
				var y := h * (0.18 + 0.72 * t)
				var rad := 0.5 * (1.0 - t * 0.8) + 0.04
				var cone := MeshKit.cylinder(rad, h * 0.3, 9, 0.02)
				var c := lf.darkened(0.15 * (1.0 - t))
				add(st, _arrays(cone), Transform3D(Basis(Vector3.UP, _r(k, i + 10) * TAU), Vector3(0, y + h * 0.1, 0)), c, 0.5)
				if species == "snow_conifer":
					var cap := MeshKit.cylinder(rad * 0.75, h * 0.08, 9, rad * 0.45)
					add(st, _arrays(cap), Transform3D(Basis(Vector3.UP, _r(k, i + 10) * TAU), Vector3(0, y + h * 0.12, 0)), Color(0.93, 0.95, 0.98, 0.5), 0.15)
		"bush":
			for i in range(4):
				var a := _r(k, i) * TAU
				var p := Vector3(cos(a), 0, sin(a)) * 0.15 * _r(k, i + 5) + Vector3(0, 0.18 + 0.08 * _r(k, i + 9), 0)
				add(st, blob(0.2 + 0.08 * _r(k, i + 3), k + str(i), 0.3, 0.8, 8), Transform3D(Basis(), p), lf.lightened(0.08 * i), 0.45)
		"shrub":
			# Dry, twiggy desert bush.
			for i in range(9):
				var a := TAU * i / 9.0 + _r(k, i)
				var tip := Vector3(cos(a) * 0.25, 0.25 + 0.15 * _r(k, i + 20), sin(a) * 0.25)
				_trunk(st, Vector3.ZERO, tip, 0.015, 0.005, bark)
				add(st, blob(0.07, k + str(i), 0.4, 0.8, 6), Transform3D(Basis(), tip), lf, 0.3)
		"cactus":
			var h := 1.2 + 0.4 * _r(k, 0)
			var green := Color(leaf.r, leaf.g, leaf.b, 1.0)
			add(st, _arrays(MeshKit.cylinder(0.09, h, 8, 0.08)), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), green, 0.25)
			add(st, blob(0.085, k + "t", 0.05, 1.0, 8), Transform3D(Basis(), Vector3(0, h, 0)), green, 0.2)
			for i in range(2):
				var s := 1.0 if i == 0 else -1.0
				var y0 := h * (0.35 + 0.2 * _r(k, i + 3))
				var out := Vector3(s * 0.22, 0, 0)
				_trunk(st, Vector3(s * 0.05, y0, 0), Vector3(0, y0, 0) + out, 0.055, 0.055, green)
				var arm_h := 0.3 + 0.25 * _r(k, i + 6)
				add(st, _arrays(MeshKit.cylinder(0.055, arm_h, 7, 0.05)), Transform3D(Basis(), Vector3(0, y0 + arm_h * 0.5, 0) + out), green, 0.25)
				add(st, blob(0.052, k + str(i), 0.05, 1.0, 7), Transform3D(Basis(), Vector3(0, y0 + arm_h, 0) + out), green, 0.2)
		"dead_tree":
			var h := 1.5 + 0.5 * _r(k, 0)
			_trunk(st, Vector3.ZERO, Vector3(0.05, h, 0), 0.08, 0.03, bark)
			for i in range(5):
				var y := h * (0.4 + 0.12 * i)
				var a := _r(k, i + 2) * TAU
				var tip := Vector3(cos(a) * (0.5 - i * 0.07), y + 0.3, sin(a) * (0.5 - i * 0.07))
				_trunk(st, Vector3(0.03, y, 0), tip, 0.035, 0.008, bark)
		"alien_tree":
			# A tall curving stalk with a drooping umbrella crown and glowing pods.
			var h := 1.9 + 0.6 * _r(k, 0)
			var bend := Vector3(0.2 * (_r(k, 1) - 0.5), 0, 0.2 * (_r(k, 2) - 0.5))
			_trunk(st, Vector3.ZERO, Vector3(0, h * 0.5, 0) + bend, 0.09, 0.06, bark)
			_trunk(st, Vector3(0, h * 0.5, 0) + bend, Vector3(0, h, 0) - bend * 0.5, 0.06, 0.04, bark)
			var crown := Vector3(0, h, 0) - bend * 0.5
			var cap := blob(0.62, k + "cap", 0.15, 0.32, 12)
			add(st, cap, Transform3D(Basis(), crown + Vector3(0, 0.05, 0)), Color(bark.r * 1.6, bark.g * 1.4, bark.b * 1.8, 0.6), 0.6)
			for i in range(8):
				var a := TAU * i / 8.0 + _r(k, i + 4)
				var p := crown + Vector3(cos(a) * 0.5, -0.12 - 0.25 * _r(k, i + 12), sin(a) * 0.5)
				_trunk(st, crown + Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), p, 0.012, 0.01, bark)
				add(st, blob(0.06, k + str(i), 0.1, 1.2, 6), Transform3D(Basis(), p), Color(leaf.r, leaf.g, leaf.b, 0.0), 0.0)
		"glow_fungus":
			var h := 1.2 + 0.5 * _r(k, 0)
			add(st, _arrays(MeshKit.cylinder(0.12, h, 8, 0.08)), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), Color(0.85, 0.82, 0.9, 1.0).darkened(0.4), 0.3)
			add(st, blob(0.55, k + "c", 0.08, 0.45, 12), Transform3D(Basis(), Vector3(0, h, 0)), Color(leaf.r * 0.5, leaf.g * 0.5, leaf.b * 0.5, 0.35), 0.7)
			# Glowing gills under the cap.
			add(st, _arrays(MeshKit.cylinder(0.5, 0.05, 12, 0.15)), Transform3D(Basis(), Vector3(0, h - 0.12, 0)), Color(leaf.r, leaf.g, leaf.b, 0.0), 0.0)
		"palm":
			# A curved, ringed trunk and a crown of long drooping fronds.
			var h := 1.8 + 0.5 * _r(k, 0)
			var bend := Vector3(0.45 * (_r(k, 1) - 0.3), 0, 0.3 * (_r(k, 2) - 0.5))
			var prev := Vector3.ZERO
			for i in range(5):
				var t := float(i + 1) / 5.0
				var p := Vector3(0, h * t, 0) + bend * t * t
				_trunk(st, prev, p, 0.07 - 0.02 * t, 0.06 - 0.02 * t, bark.lightened(0.08 * (i % 2)))
				prev = p
			for i in range(8):
				var a := TAU * i / 8.0 + _r(k, i + 10) * 0.4
				var dir := Vector3(cos(a), 0, sin(a))
				var mid := prev + dir * 0.45 + Vector3.UP * 0.12
				var tip := prev + dir * 0.85 + Vector3.DOWN * 0.3
				var side := dir.cross(Vector3.UP) * 0.13
				for seg: Array in [[prev, mid], [mid, tip]]:
					var a0: Vector3 = seg[0]
					var b0: Vector3 = seg[1]
					var wa := 0.4 if a0 == prev else 1.0
					var nrm := (b0 - a0).cross(side).normalized()
					if nrm.y < 0:
						nrm = -nrm
					for v: Vector3 in [a0 - side * wa, a0 + side * wa, b0 + side * 0.4, a0 - side * wa, b0 + side * 0.4, b0 - side * 0.4]:
						st.set_color(lf.lightened(0.05 * (i % 3)))
						st.set_normal(nrm)
						st.add_vertex(v)
			add(st, blob(0.1, k + "nut", 0.2, 1.0, 6), Transform3D(Basis(), prev + Vector3(0, -0.08, 0)), Color(0.35, 0.28, 0.15, 1.0), 0.2)
		"jungle_tree":
			# A tall straight trunk on buttress roots, layered flat canopies and hanging vines.
			var h := 2.4 + 0.6 * _r(k, 0)
			_trunk(st, Vector3.ZERO, Vector3(0, h, 0), 0.12, 0.07, bark)
			for i in range(4):
				var a := TAU * i / 4.0 + _r(k, i)
				_trunk(st, Vector3(cos(a), 0, sin(a)) * 0.3, Vector3(0, 0.5, 0), 0.05, 0.03, bark)
			for layer in range(2):
				var y := h * (0.75 + 0.25 * layer)
				var rad := 0.75 - 0.2 * layer
				for i in range(6):
					var a := TAU * i / 6.0 + _r(k, i + 20 + layer * 10)
					var p := Vector3(cos(a) * rad * 0.6, y, sin(a) * rad * 0.6)
					add(st, blob(0.36 + 0.1 * _r(k, i + 40), k + str(layer * 10 + i), 0.25, 0.45, 9), Transform3D(Basis(), p), lf.lightened(0.06 * layer), 0.55)
				add(st, blob(rad * 0.8, k + "c" + str(layer), 0.2, 0.4, 10), Transform3D(Basis(), Vector3(0, y + 0.05, 0)), lf.darkened(0.1), 0.6)
			for i in range(6):
				var a := TAU * i / 6.0 + _r(k, i + 60)
				var top := Vector3(cos(a) * 0.6, h * 0.78, sin(a) * 0.6)
				_trunk(st, top, top + Vector3(0, -0.8 - 0.6 * _r(k, i + 70), 0), 0.012, 0.008, Color(lf.r * 0.8, lf.g * 0.8, lf.b * 0.8, 0.5))
		"cherry":
			# Blossom tree: a crooked trunk and wide flat clouds of blossom.
			var h := 1.2 + 0.4 * _r(k, 0)
			var bend := Vector3(0.25 * (_r(k, 1) - 0.5), 0, 0.25 * (_r(k, 2) - 0.5))
			_trunk(st, Vector3.ZERO, Vector3(0, h * 0.5, 0) + bend, 0.08, 0.06, bark)
			_trunk(st, Vector3(0, h * 0.5, 0) + bend, Vector3(0.1, h * 0.8, 0) - bend, 0.06, 0.03, bark)
			var crown := Vector3(0, h * 0.85, 0)
			for i in range(7):
				var a := TAU * i / 7.0 + _r(k, i + 40)
				var p := crown + Vector3(cos(a) * 0.45, 0.05 + 0.2 * _r(k, i + 50), sin(a) * 0.45)
				add(st, blob(0.28 + 0.08 * _r(k, i + 60), k + str(i), 0.25, 0.6, 9), Transform3D(Basis(), p), lf.lightened(0.1 * _r(k, i + 70)), 0.35)
			add(st, blob(0.4, k + "core", 0.2, 0.6, 10), Transform3D(Basis(), crown + Vector3(0, 0.2, 0)), lf, 0.4)
		"glow_cap":
			# A little glowing mushroom, about 1 unit tall before scaling.
			_trunk(st, Vector3.ZERO, Vector3(0, 0.6, 0), 0.08, 0.06, bark)
			add(st, blob(0.32, k + "c", 0.1, 0.5, 9), Transform3D(Basis(), Vector3(0, 0.62, 0)), Color(leaf.r, leaf.g, leaf.b, 0.0), 0.0)
		"glow_frond":
			for i in range(3):
				var a := TAU * i / 3.0 + _r(k, i)
				var tip := Vector3(cos(a) * 0.35, 0.9, sin(a) * 0.35)
				_trunk(st, Vector3.ZERO, tip, 0.05, 0.015, Color(leaf.r * 0.5, leaf.g * 0.5, leaf.b * 0.5, 0.3))
				add(st, blob(0.07, k + str(i), 0.1, 1.3, 6), Transform3D(Basis(), tip), Color(leaf.r, leaf.g, leaf.b, 0.0), 0.0)
		"bamboo":
			for i in range(5):
				var a := TAU * i / 5.0 + _r(k, i)
				var base := Vector3(cos(a), 0, sin(a)) * 0.18 * _r(k, i + 7)
				var h := 1.8 + 0.6 * _r(k, i + 3)
				var lean := Vector3(cos(a), 0, sin(a)) * 0.12
				_trunk(st, base, base + Vector3(0, h, 0) + lean, 0.035, 0.03, Color(0.55, 0.62, 0.3, 1.0))
				for j in range(3):
					var p := base + Vector3(0, h * (0.6 + 0.15 * j), 0) + lean * (0.6 + 0.15 * j)
					add(st, blob(0.16, k + str(i * 3 + j), 0.5, 0.5, 6), Transform3D(Basis(), p), lf.lightened(0.05 * j), 0.35)
		_:
			# Broadleaf: trunk with two limbs and a crown of 6-8 clumps.
			var h := 1.35 + 0.45 * _r(k, 0)
			var lean := Vector3(0.12 * (_r(k, 1) - 0.5), 0, 0.12 * (_r(k, 2) - 0.5))
			_trunk(st, Vector3.ZERO, Vector3(0, h * 0.62, 0) + lean, 0.085, 0.055, bark)
			var crown := Vector3(0, h * 0.75, 0) + lean
			for i in range(2):
				var a := _r(k, i + 30) * TAU
				_trunk(st, Vector3(0, h * 0.42, 0) + lean * 0.6, crown + Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.3), 0.04, 0.02, bark)
			var n := 6 + int(_r(k, 3) * 3.0)
			for i in range(n):
				var a := TAU * i / n + _r(k, i + 40)
				var up := _r(k, i + 50)
				var p := crown + Vector3(cos(a) * 0.35 * (1.0 - up * 0.5), 0.05 + up * 0.45, sin(a) * 0.35 * (1.0 - up * 0.5))
				var c := lf.lightened(0.12 * up).darkened(0.1 * (1.0 - up))
				add(st, blob(0.26 + 0.1 * _r(k, i + 60), k + str(i), 0.22, 0.85, 9), Transform3D(Basis(), p), c, 0.55)
			add(st, blob(0.36, k + "core", 0.2, 0.85, 10), Transform3D(Basis(), crown + Vector3(0, 0.22, 0)), lf.darkened(0.1), 0.6)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A grass tuft about 1 unit tall before scaling (fan of curved blades, dark root to light tip).
static func tuft(color: Color, blades: int = 9) -> ArrayMesh:
	var key := "tuft|%s|%d" % [color.to_html(), blades]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(blades):
		var a := TAU * i / blades + 0.5 * sin(i * 3.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var base := dir * 0.06 * (0.5 + 0.5 * sin(i * 2.7))
		var h := 0.65 + 0.35 * absf(sin(i * 2.3))
		var mid := base + dir * 0.12 + Vector3.UP * h * 0.55
		var tip := base + dir * (0.28 + 0.12 * sin(i * 1.7)) + Vector3.UP * h
		var root := color.darkened(0.45)
		var mid_c := color.darkened(0.1)
		var tip_c := color.lightened(0.18)
		root.a = 0.5
		mid_c.a = 0.5
		tip_c.a = 0.5
		var n := (side.cross(Vector3.UP) * -1.0).normalized()
		var quad := [[base - side, root], [base + side, root], [mid + side * 0.6, mid_c], [mid - side * 0.6, mid_c]]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for q: int in tri:
				st.set_color(quad[q][1])
				st.set_normal((n + Vector3.UP * 0.6).normalized())
				st.add_vertex(quad[q][0])
		for v: Array in [[mid - side * 0.6, mid_c], [mid + side * 0.6, mid_c], [tip, tip_c]]:
			st.set_color(v[1])
			st.set_normal((n + Vector3.UP * 0.6).normalized())
			st.add_vertex(v[0])
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A flower: a short stem and a small colored head (about 1 unit tall before scaling).
static func flower(color: Color) -> ArrayMesh:
	var key := "flower|%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.25, 0.4, 0.15, 0.5)
	_trunk(st, Vector3.ZERO, Vector3(0.05, 0.8, 0), 0.02, 0.015, stem)
	var head := Color(color.r, color.g, color.b, 0.5)
	add(st, blob(0.12, "fl" + color.to_html(), 0.35, 0.5, 6), Transform3D(Basis(), Vector3(0.05, 0.85, 0)), head, 0.2)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A faceted boulder about 1 unit across before scaling (alpha 1: lit like stone).
static func rock(color: Color, variant: int) -> ArrayMesh:
	var key := "rock|%s|%d" % [color.to_html(), variant]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := blob(0.5, "rock%d" % variant, 0.28, 0.7, 7)
	add(st, b, Transform3D(), Color(color.r, color.g, color.b, 1.0), 0.45)
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _r(k: String, i: int) -> float:
	return WorldRand.f(k, i)
