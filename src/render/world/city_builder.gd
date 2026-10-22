class_name CityBuilder
extends RefCounted
## Buildings for city and settlement styles. Every raised column that is a structure (tag
## "building", or any plain raised column in a style with `architecture`) is drawn as part
## of a building: walls exactly on the cell edges and exactly as tall as the column, a flat
## roof at the column's top (where units stand), and the architecture painted on: floors,
## windows, storefronts, trim, damage and lights (building.gdshader).
## Connected columns of the same height form one building; steps in height are setbacks.
## What sticks out of the footprint stays tiny: parapets, signs, awnings, eaves (< 0.15).

const SHADER := preload("res://src/render/shaders/building.gdshader")
const TYPES := {"concrete": 0, "brick": 1, "plaster": 2, "metal": 3, "stone": 4, "wood": 5, "glass": 6, "timber": 7}
const PARAPET := 0.06
## Tags that keep a raised column out of buildings (it is rock, a wall, woods...).
const NOT_BUILDING := ["rock", "crystal", "wall", "woods", "chasm", "soft_cover", "bulkhead", "container", "machinery", "deck", "platform"]

var t: TerrainRenderer
var arch: Dictionary
var enabled := false
var material: ShaderMaterial
## cell -> building index; buildings: [{cells, top, type, color, seed, lot}]
var building_of := {}
var buildings: Array = []
var lot_of := {}


func _init(terrain: TerrainRenderer) -> void:
	t = terrain
	arch = t.style.get("architecture", {})
	# In a city every plain raised column is a building; elsewhere only "building" tags are.
	enabled = bool(t.style.get("urban", false))


func is_structure(c: Vector2i) -> bool:
	var col := t.map.column(c)
	if col == null or col.ground < 1 or col.gap_top > 0:
		return false
	if col.has_tag("building"):
		return true
	if not enabled or t.liquid_of(c) != "":
		return false
	for tag: String in NOT_BUILDING:
		if col.has_tag(tag):
			return false
	return true


## Marks the cells this builder draws (TerrainRenderer.structure_cells).
func claim() -> void:
	for c in t.map.cells():
		if is_structure(c):
			t.structure_cells[c] = true
	if t.structure_cells.is_empty():
		return
	if arch.is_empty():
		arch = {"style": "modern"}
	_group()


## Lots: connected structure cells. Buildings: connected cells of one height within a lot.
func _group() -> void:
	var lot := 0
	for c: Vector2i in t.structure_cells:
		if lot_of.has(c):
			continue
		var stack: Array[Vector2i] = [c]
		lot_of[c] = lot
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for n in t.map.grid.neighbors(cur):
				if t.structure_cells.has(n) and not lot_of.has(n):
					lot_of[n] = lot
					stack.append(n)
		lot += 1
	var mats: Array = arch.get("materials", ["concrete"])
	var walls: Array = arch.get("walls", ["#9a948a"])
	for c: Vector2i in t.structure_cells:
		if building_of.has(c):
			continue
		var h := t.map.ground_height(c)
		var idx := buildings.size()
		var cells: Array[Vector2i] = []
		var stack: Array[Vector2i] = [c]
		building_of[c] = idx
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			cells.append(cur)
			for n in t.map.grid.neighbors(cur):
				if t.structure_cells.has(n) and not building_of.has(n) and t.map.ground_height(n) == h:
					building_of[n] = idx
					stack.append(n)
		var key := "b%s" % str(c)
		var lot_key := "lot%d" % lot_of[c]
		# Most buildings on one lot share a material; some differ.
		var mat_key := lot_key if WorldRand.f(key, 1) < 0.7 else key
		buildings.append({"cells": cells, "top": h * GridLayout.LEVEL_HEIGHT, "lot": lot_of[c],
			"type": TYPES.get(str(mats[int(WorldRand.f(mat_key, 2) * mats.size()) % mats.size()]), 0),
			"color": WorldStyle.color(walls[int(WorldRand.f(key, 3) * walls.size()) % walls.size()]),
			"seed": WorldRand.f(key, 4)})


static func make_material(arch: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var nums := {"floors": "floors", "bay": "bay", "window_w": "window_w", "window_h": "window_h", "lit_windows": "lit",
		"ruined": "ruined", "burning": "burning", "storefront": "storefront", "neon": "neon", "wet": "wet", "arched": "arched"}
	for k: String in nums:
		if arch.has(k):
			m.set_shader_parameter(nums[k], float(arch[k]))
	for k: String in ["rim_strength", "rim_glow", "backdrop"]:
		if arch.has(k):
			m.set_shader_parameter(k, float(arch[k]))
	if arch.has("rim"):
		m.set_shader_parameter("rim_color", WorldStyle.color(arch["rim"]))
	m.set_shader_parameter("roof_style", {"tar": 0, "tiles": 1, "shingles": 2, "panels": 3, "metal": 4}.get(str(arch.get("roof_surface", "tar")), 0))
	var cols := {"trim": "trim", "glass": "glass", "window_light": "window_light", "shop_light": "shop_light", "roof": "roof_color",
		"fire": "fire_color", "neon_a": "neon_a", "neon_b": "neon_b"}
	for k: String in cols:
		if arch.has(k):
			m.set_shader_parameter(cols[k], WorldStyle.color(arch[k]))
	return m


func build(root: Node3D) -> void:
	if buildings.is_empty():
		return
	material = make_material(arch)
	t.building_material = material
	t.building_looks = {}
	for b: Dictionary in buildings:
		for c: Vector2i in b["cells"]:
			t.building_looks[c] = {"color": b["color"], "seed": b["seed"], "type": b["type"], "top": b["top"]}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var shape := MeshKit.cell_shape(t.map.grid)
	var corners: PackedVector2Array = shape["corners"]
	var edge_n: Array[Vector2i] = shape["edge_neighbors"]
	var faces: Array = []  # street-facing faces for signs: [a, b, out, bottom, top, building]
	for bi in range(buildings.size()):
		var b: Dictionary = buildings[bi]
		var top: float = b["top"]
		var vcol: Color = b["color"]
		vcol.a = b["seed"]
		for c: Vector2i in b["cells"]:
			var center := t.map.grid.to_world(c)
			# Roof.
			var custom := Color(1.0, top, 0.0, float(b["type"]))
			_fan(st, center, corners, top, vcol, custom)
			for i in range(corners.size()):
				var other := c + edge_n[i]
				var bottom := _wall_bottom(other, top)
				if bottom >= top - 0.001:
					continue
				var a := center + Vector3(corners[i].x, 0, corners[i].y)
				var bb := center + Vector3(corners[(i + 1) % corners.size()].x, 0, corners[(i + 1) % corners.size()].y)
				var out := ((a + bb) * 0.5 - center).normalized()
				var w := a.distance_to(bb)
				var cu := Color(w, top, 0.0, float(b["type"]))
				_wall(st, a, bb, bottom, top, out, vcol, cu)
				_roof_edge(st, c, i, a, bb, top, out, vcol, cu)
				if bottom <= 0.05:
					faces.append([a, bb, out, bottom, top, bi])
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = st.commit()
	mi.material_override = material
	root.add_child(mi)
	CityProps.build(self, root, faces)


## The roof's rim along one open edge, in the culture's style (all under 0.15 high):
## parapet, battlement (merlons and gaps), eaves (a thin sloped overhang; upturned at the
## ends for "eaves_up"), chrome (a rounded bright band) or none.
func _roof_edge(st: SurfaceTool, c: Vector2i, i: int, a: Vector3, b: Vector3, top: float, out: Vector3, vcol: Color, cu: Color) -> void:
	var edge := str(arch.get("roof_edge", "parapet"))
	if edge == "none" or _broken_parapet(c, i):
		return
	match edge:
		"battlement":
			var n := maxi(2, int(round(a.distance_to(b) / 0.16)))
			for k in range(n):
				var t0 := float(k) / n
				var t1 := float(k + 1) / n
				var hgt := 0.13 if k % 2 == 0 else 0.05
				_rim(st, a.lerp(b, t0), a.lerp(b, t1), top, top + hgt, out, 0.07, vcol, cu)
		"eaves", "eaves_up":
			var reach := float(arch.get("eave_reach", 0.12))
			var drop := 0.07
			var lift := 0.06 if edge == "eaves_up" else 0.0
			var roof := Color(WorldStyle.color(arch.get("roof", "#3a3a3a")))
			roof.a = vcol.a
			var oa := a + out * reach + Vector3.UP * (top - drop + lift)
			var ob := b + out * reach + Vector3.UP * (top - drop + lift)
			var ia := Vector3(a.x, top + 0.02, a.z)
			var ib := Vector3(b.x, top + 0.02, b.z)
			var mid := (oa + ob) * 0.5 - Vector3.UP * lift
			var rcu := Color(cu.r, cu.g, cu.b, cu.a)
			_slab(st, [ia, ib, ob, mid, oa], vcol, rcu)
		"chrome":
			_rim(st, a, b, top, top + 0.05, out, 0.03, Color(0.85, 0.87, 0.9, vcol.a), Color(cu.r, top + 0.05, cu.b, 3.0))
		_:
			_rim(st, a, b, top, top + PARAPET, out, 0.05, vcol, cu)


## A low wall on the roof's edge: outer face, inner face and cap.
func _rim(st: SurfaceTool, a: Vector3, b: Vector3, y0: float, y1: float, out: Vector3, thick: float, vcol: Color, cu: Color) -> void:
	_wall(st, a, b, y0, y1, out, vcol, cu)
	var ia := a - out * thick
	var ib := b - out * thick
	_wall(st, ib, ia, y0, y1, -out, vcol, cu)
	_cap(st, a, b, ib, ia, y1, vcol, cu)


## A sloped roof skirt from the wall top out to the eave line (polygon fan, both faces).
static func _slab(st: SurfaceTool, pts: Array, vcol: Color, cu: Color) -> void:
	var n := ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3)).normalized()
	if n.y < 0.0:
		n = -n
	for side in [1.0, -1.0]:
		for k in range(1, pts.size() - 1):
			var tri := [pts[0], pts[k], pts[k + 1]]
			var tn := ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3))
			if (tn.dot(n) > 0.0) == (side > 0.0):
				tri = [tri[0], tri[2], tri[1]]
			for v: Vector3 in tri:
				st.set_color(vcol)
				st.set_custom(0, cu)
				st.set_normal(n * side)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)


## Where a wall facing `other` starts: the top of whatever is next door.
func _wall_bottom(other: Vector2i, top: float) -> float:
	if not t.map.has_cell(other):
		return t._bottom
	if t.structure_cells.has(other):
		return minf(t.top_y(other), top)
	var col := t.map.column(other)
	if col.gap_top > 0:
		return col.gap_bottom * GridLayout.LEVEL_HEIGHT
	return minf(t.floor_y(other), top)


func _broken_parapet(c: Vector2i, edge: int) -> bool:
	var ruin := float(arch.get("ruined", 0.0))
	return WorldRand.f("pp" + str(c), edge) < ruin * 0.6 or str(arch.get("parapet", "yes")) == "no"


static func _fan(st: SurfaceTool, center: Vector3, corners: PackedVector2Array, y: float, vcol: Color, cu: Color) -> void:
	for i in range(corners.size()):
		var p := corners[i]
		var q := corners[(i + 1) % corners.size()]
		var tri := [Vector3(center.x, y, center.z), center + Vector3(p.x, y, p.y), center + Vector3(q.x, y, q.y)]
		if ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).y > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for v: Vector3 in tri:
			st.set_color(vcol)
			st.set_custom(0, cu)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)


static func _cap(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, y: float, vcol: Color, cu: Color) -> void:
	var q := [Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), Vector3(c.x, y, c.z), Vector3(d.x, y, d.z)]
	var order := [0, 1, 2, 0, 2, 3]
	if ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3)).y > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		st.set_color(vcol)
		st.set_custom(0, cu)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2((q[k] as Vector3).x, (q[k] as Vector3).z))
		st.add_vertex(q[k])


## A wall quad from a to b, y0..y1, facing `out`. UV = (distance along the face, world y).
static func _wall(st: SurfaceTool, a: Vector3, b: Vector3, y0: float, y1: float, out: Vector3, vcol: Color, cu: Color) -> void:
	var w := a.distance_to(b)
	var q := [[Vector3(a.x, y0, a.z), Vector2(0, y0)], [Vector3(b.x, y0, b.z), Vector2(w, y0)],
		[Vector3(b.x, y1, b.z), Vector2(w, y1)], [Vector3(a.x, y1, a.z), Vector2(0, y1)]]
	var order := [0, 1, 2, 0, 2, 3]
	if ((q[1][0] as Vector3) - (q[0][0] as Vector3)).cross((q[2][0] as Vector3) - (q[0][0] as Vector3)).dot(out) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		st.set_color(vcol)
		st.set_custom(0, cu)
		st.set_normal(out)
		st.set_uv(q[k][1])
		st.add_vertex(q[k][0])
