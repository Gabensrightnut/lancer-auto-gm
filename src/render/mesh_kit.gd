class_name MeshKit
extends RefCounted
## Mesh and material helpers shared by the renderer. Everything here is generated in code;
## no imported models.

const MECH_SHADER := preload("res://src/render/shaders/mech.gdshader")
const FX_SHADER := preload("res://src/render/shaders/fx_additive.gdshader")

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _cell_shape_cache: Dictionary = {}


## Outline of one grid cell around its own center on the ground plane (x, z), plus the
## neighbor offset across each edge (edge i runs corner i -> corner i+1). Worked out from
## the neighbors' centers (each edge is halfway to a neighbor), so it needs no knowledge of
## hex vs square and stays correct for any GridLayout.
## Returns {"corners": PackedVector2Array, "edge_neighbors": Array[Vector2i]}.
static func cell_shape(grid: GridLayout) -> Dictionary:
	if _cell_shape_cache.has(grid.shape):
		return _cell_shape_cache[grid.shape]
	var c0 := grid.to_world(Vector2i.ZERO)
	var poly: Array[Vector2] = [Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)]
	var tags: Array = [null, null, null, null]
	for n in grid.neighbors(Vector2i.ZERO):
		var w := grid.to_world(n) - c0
		var d := Vector2(w.x, w.z)
		var limit := d.length_squared() / 2.0
		var out_poly: Array[Vector2] = []
		var out_tags: Array = []
		for i in range(poly.size()):
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var a_in := a.dot(d) <= limit + 1e-4
			var b_in := b.dot(d) <= limit + 1e-4
			if a_in:
				out_poly.append(a)
				out_tags.append(tags[i])
			if a_in != b_in:
				var t := (limit - a.dot(d)) / (b - a).dot(d)
				out_poly.append(a.lerp(b, t))
				out_tags.append(n if a_in else tags[i])
		poly = out_poly
		tags = out_tags
	# Drop zero-length edges (corner-only neighbors such as square diagonals).
	var corners := PackedVector2Array()
	var edge_neighbors: Array[Vector2i] = []
	for i in range(poly.size()):
		if poly[i].distance_to(poly[(i + 1) % poly.size()]) < 1e-3:
			continue
		corners.append(poly[i])
		edge_neighbors.append(tags[i] if tags[i] != null else Vector2i(9999, 9999))
	# Make the winding counter-clockwise seen from above (+y): signed area in (x, z) < 0.
	var area := 0.0
	for i in range(corners.size()):
		var p := corners[i]
		var q := corners[(i + 1) % corners.size()]
		area += p.x * q.y - q.x * p.y
	if area > 0.0:
		corners.reverse()
		var rev: Array[Vector2i] = []
		for i in range(edge_neighbors.size()):
			# Edge i of the reversed list is old edge (n - 2 - i) mod n.
			rev.append(edge_neighbors[(edge_neighbors.size() * 2 - 2 - i) % edge_neighbors.size()])
		edge_neighbors = rev
	var shape := {"corners": corners, "edge_neighbors": edge_neighbors}
	_cell_shape_cache[grid.shape] = shape
	return shape


## Adds a triangle facing `outward` (Godot treats clockwise as the front face).
static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, uv_scale: float = 1.0) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var normal := -n.normalized()
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_uv(_box_uv(v, normal) * uv_scale)
		st.add_vertex(v)


static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, uv_scale: float = 1.0) -> void:
	add_tri(st, a, b, c, outward, uv_scale)
	add_tri(st, a, c, d, outward, uv_scale)


static func _box_uv(v: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return Vector2(v.x, v.z)
	if an.x >= an.z:
		return Vector2(v.z, -v.y)
	return Vector2(v.x, -v.y)


## A box with chamfered edges, so armor plates catch light along their edges.
## `taper` scales the top face (x, z); `shear` pushes the top forward along -z.
static func chamfer_box(size: Vector3, bevel: float = 0.03, taper: float = 1.0, shear: float = 0.0) -> ArrayMesh:
	var key := "box|%s|%.4f|%.3f|%.3f" % [size, bevel, taper, shear]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var h := size / 2.0
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vert := func(s: Vector3, axis: int) -> Vector3:
		var p := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
		p[axis] = s[axis] * h[axis]
		var f := (p.y + h.y) / (2.0 * h.y)
		var k := lerpf(1.0, taper, f)
		return Vector3(p.x * k, p.y, p.z * k - shear * f)
	var signs := [-1.0, 1.0]
	var ctr := Vector3(0, 0, -shear * 0.5)
	# Faces.
	for axis in range(3):
		for s in signs:
			var u := (axis + 1) % 3
			var w := (axis + 2) % 3
			var q: Array[Vector3] = []
			for su: float in [-1.0, 1.0, 1.0, -1.0]:
				var sw: float = -1.0 if q.size() < 2 else 1.0
				var sv := Vector3.ZERO
				sv[axis] = s
				sv[u] = su
				sv[w] = sw
				q.append(vert.call(sv, axis))
			add_quad(st, q[0], q[1], q[2], q[3], (q[0] + q[2]) * 0.5 - ctr)
	# Edges.
	for a1 in range(3):
		for a2 in range(a1 + 1, 3):
			var third := 3 - a1 - a2
			for s1 in signs:
				for s2 in signs:
					var p: Array[Vector3] = []
					for s3: float in [-1.0, 1.0]:
						var sv := Vector3.ZERO
						sv[a1] = s1
						sv[a2] = s2
						sv[third] = s3
						p.append(vert.call(sv, a1))
						p.append(vert.call(sv, a2))
					add_quad(st, p[0], p[1], p[3], p[2], (p[0] + p[3]) * 0.5 - ctr)
	# Corners.
	for sx in signs:
		for sy in signs:
			for sz in signs:
				var sv := Vector3(sx, sy, sz)
				var a: Vector3 = vert.call(sv, 0)
				var bb: Vector3 = vert.call(sv, 1)
				var c: Vector3 = vert.call(sv, 2)
				add_tri(st, a, bb, c, (a + bb + c) / 3.0 - ctr)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## A cylinder along +y, centred on the origin. Cached by its parameters.
static func cylinder(radius: float, height: float, sides: int = 12, top_radius: float = -1.0) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%d|%.3f" % [radius, height, sides, top_radius]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	_mesh_cache[key] = m
	return m


static func sphere(radius: float, segments: int = 12) -> SphereMesh:
	var key := "sph|%.3f|%d" % [radius, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = segments / 2
	_mesh_cache[key] = m
	return m


## Painted armor material. `wear` adds scuffed edges; `emit` makes the part glow.
static func mech_material(color: Color, metallic: float = 0.55, roughness: float = 0.45, emit: Color = Color.BLACK, panels: bool = true) -> ShaderMaterial:
	var key := "mech|%s|%.2f|%.2f|%s|%s" % [color.to_html(), metallic, roughness, emit.to_html(), panels]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = MECH_SHADER
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic_value", metallic)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("emission_color", emit)
	m.set_shader_parameter("panel_strength", 1.0 if panels else 0.0)
	_mat_cache[key] = m
	return m


## Paint for hand-modeled frames: like mech_material but with a panel-line strength
## (smooth curved parts look best with faint lines).
static func paint(color: Color, metallic: float = 0.45, roughness: float = 0.45, panel_strength: float = 0.3, emit: Color = Color.BLACK) -> ShaderMaterial:
	var key := "paint|%s|%.2f|%.2f|%.2f|%s" % [color.to_html(), metallic, roughness, panel_strength, emit.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = MECH_SHADER
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic_value", metallic)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("emission_color", emit)
	m.set_shader_parameter("panel_strength", panel_strength)
	_mat_cache[key] = m
	return m


## Bright additive material for beams, tracers, glows. Ignores lighting.
## `soft` fades edges that face away from the camera (for tubes and spheres); turn it off
## for flat ribbons.
static func fx_material(color: Color, energy: float = 2.0, soft: bool = true) -> ShaderMaterial:
	var key := "fx|%s|%.2f|%s" % [color.to_html(), energy, soft]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = FX_SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("soft_edges", 1.0 if soft else 0.0)
	_mat_cache[key] = m
	return m


## Plain unshaded, see-through material for overlays.
static func overlay_material(color: Color, on_top: bool = false, cull: bool = true) -> StandardMaterial3D:
	var key := "ov|%s|%s|%s" % [color.to_html(), on_top, cull]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = on_top
	m.cull_mode = BaseMaterial3D.CULL_BACK if cull else BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.render_priority = 2 if on_top else 1
	_mat_cache[key] = m
	return m


## Adds a mesh child with a material, returns it.
static func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scale
	parent.add_child(mi)
	return mi


## Stable pseudo-random number in [0, 1) from a string and an index, so generated models
## look the same every time.
static func hash01(key: String, i: int = 0) -> float:
	var h := hash("%s#%d" % [key, i])
	return float(h & 0xFFFF) / 65536.0
