class_name SmoothKit
extends RefCounted
## Smooth, curved meshes for hand-modeled frames (until the Blender pipeline exists):
## lofts through rounded cross-sections, lathes, superellipsoids and rounded boxes, all with
## smooth normals. Shapes point up (+y) and face -z, like the rest of the mech parts.

static var _cache: Dictionary = {}


## Point on a superellipse of half-sizes a, b. n = 2 is an ellipse; higher n is squarer.
static func _se(t: float, a: float, b: float, n: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	return Vector2(a * signf(c) * pow(absf(c), 2.0 / n), b * signf(s) * pow(absf(s), 2.0 / n))


## Lofts through cross-sections, bottom to top. Each section: {y, w, d, n?, x?, z?}
## (width along x, depth along z, squareness n, center offset). `caps` closes the ends.
static func loft(sections: Array, ring: int = 24, caps: bool = true) -> ArrayMesh:
	var key := "loft|%s|%d|%s" % [str(sections), ring, caps]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := sections.size()
	for i in range(rows):
		var s: Dictionary = sections[i]
		for j in range(ring):
			var t := TAU * j / ring
			var p := _se(t, float(s["w"]) / 2.0, float(s["d"]) / 2.0, float(s.get("n", 2.0)))
			st.set_uv(Vector2(float(j) / ring, float(i) / maxf(1.0, rows - 1)))
			st.add_vertex(Vector3(p.x + float(s.get("x", 0.0)), float(s["y"]), p.y + float(s.get("z", 0.0))))
	for i in range(rows - 1):
		for j in range(ring):
			var jn := (j + 1) % ring
			var a := i * ring + j
			var a1 := i * ring + jn
			var b := (i + 1) * ring + j
			var b1 := (i + 1) * ring + jn
			st.add_index(a)
			st.add_index(a1)
			st.add_index(b)
			st.add_index(a1)
			st.add_index(b1)
			st.add_index(b)
	st.generate_normals()
	var mesh := st.commit()
	if caps:
		for end in [0, rows - 1]:
			var s: Dictionary = sections[end]
			var cst := SurfaceTool.new()
			cst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var c := Vector3(float(s.get("x", 0.0)), float(s["y"]), float(s.get("z", 0.0)))
			var up: bool = end != 0
			for j in range(ring):
				var p0 := _se(TAU * j / ring, float(s["w"]) / 2.0, float(s["d"]) / 2.0, float(s.get("n", 2.0)))
				var p1 := _se(TAU * (j + 1) / ring, float(s["w"]) / 2.0, float(s["d"]) / 2.0, float(s.get("n", 2.0)))
				var v0 := Vector3(c.x + p0.x, c.y, c.z + p0.y)
				var v1 := Vector3(c.x + p1.x, c.y, c.z + p1.y)
				for v in ([c, v0, v1] if up else [c, v1, v0]):
					cst.set_normal(Vector3.UP if up else Vector3.DOWN)
					cst.set_uv(Vector2(v.x, v.z))
					cst.add_vertex(v)
			cst.commit(mesh)
	_cache[key] = mesh
	return mesh


## Revolves a profile of Vector2(radius, y) points around the y axis.
static func lathe(profile: Array, ring: int = 24, caps: bool = true) -> ArrayMesh:
	var sections: Array = []
	for p: Vector2 in profile:
		sections.append({"y": p.y, "w": p.x * 2.0, "d": p.x * 2.0})
	return loft(sections, ring, caps)


## A superellipsoid: e = 1 is an ellipsoid, smaller is boxier, larger is pinched.
## `cut` keeps only the part above y >= -cut * half height (1 = whole, 0 = top half: a dome).
static func blob(size: Vector3, e_vertical: float = 0.6, e_around: float = 0.6, cut: float = 1.0, seg: int = 20) -> ArrayMesh:
	var key := "blob|%s|%.2f|%.2f|%.2f|%d" % [size, e_vertical, e_around, cut, seg]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var rows := seg / 2
	var v_min := -asin(clampf(cut, 0.0, 1.0)) if cut < 1.0 else -PI / 2.0
	var f := func(w: float, m: float) -> float: return signf(w) * pow(absf(w), m)
	for i in range(rows + 1):
		var v := lerpf(v_min, PI / 2.0, float(i) / rows)
		for j in range(seg):
			var u := -PI + TAU * j / seg
			var cv: float = f.call(cos(v), e_vertical)
			var p := Vector3(h.x * cv * f.call(cos(u), e_around), h.y * f.call(sin(v), e_vertical), h.z * cv * f.call(sin(u), e_around))
			st.set_uv(Vector2(float(j) / seg, float(i) / rows))
			st.add_vertex(p)
	for i in range(rows):
		for j in range(seg):
			var jn := (j + 1) % seg
			st.add_index(i * seg + j)
			st.add_index(i * seg + jn)
			st.add_index((i + 1) * seg + j)
			st.add_index(i * seg + jn)
			st.add_index((i + 1) * seg + jn)
			st.add_index((i + 1) * seg + j)
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A box with properly rounded edges (radius r), smooth shaded.
static func rounded_box(size: Vector3, r: float, seg: int = 4) -> ArrayMesh:
	var e := clampf(r / (minf(size.x, minf(size.y, size.z)) * 0.5), 0.05, 1.0)
	# A superellipsoid with small exponents is a good rounded box at this scale.
	return blob(size, 0.15 + 0.6 * e, 0.15 + 0.6 * e, 1.0, 12 + seg * 4)


## A tube following a path of points (hoses, cables, pipes). `radii` is one radius or one
## per point. Smooth normals; ends are left open (cap them with a blob if needed).
static func tube(points: Array, radii: Variant, sides: int = 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var up := Vector3.UP
	var prev_side := Vector3.ZERO
	for i in range(n):
		var p: Vector3 = points[i]
		var t: Vector3 = ((points[mini(i + 1, n - 1)] as Vector3) - (points[maxi(i - 1, 0)] as Vector3)).normalized()
		var side: Vector3
		if i == 0:
			side = t.cross(up)
			if side.length() < 0.01:
				side = t.cross(Vector3.RIGHT)
		else:
			# Parallel transport: keep the frame from twisting along the tube.
			side = (prev_side - t * prev_side.dot(t))
		side = side.normalized()
		prev_side = side
		var bin := t.cross(side).normalized()
		var r: float = radii[i] if radii is Array else float(radii)
		for j in range(sides):
			var a := TAU * j / sides
			var nrm := side * cos(a) + bin * sin(a)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(j) / sides, float(i) / (n - 1)))
			st.add_vertex(p + nrm * r)
	for i in range(n - 1):
		for j in range(sides):
			var jn := (j + 1) % sides
			var a := i * sides + j
			var b := (i + 1) * sides + j
			for k: int in [a, b, i * sides + jn, i * sides + jn, b, (i + 1) * sides + jn]:
				st.add_index(k)
	return st.commit()


## Points along a cubic Bezier from a to d with handles b, c.
static func bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, steps: int = 16) -> Array:
	var out: Array = []
	for i in range(steps + 1):
		var t := float(i) / steps
		var u := 1.0 - t
		out.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return out
