class_name TerrainRenderer
extends Node3D
## Draws a BattleMap as terraced blocks in a terrain kit's (biome's) style, with grid lines
## on every surface a unit can stand on, low decorative props, and scenery beyond the board.
## Kits: "urban_ruins", "grassy_hills". Anything that looks like cover or an obstacle comes
## from the map data (raised columns, tags); decoration stays small and flat.
## Works on any GridLayout: cell outlines come from MeshKit.cell_shape().
## Call build() again whenever the map changes.

const TERRAIN_SHADER := preload("res://src/render/shaders/terrain.gdshader")
const HILLS_SHADER := preload("res://src/render/shaders/terrain_hills.gdshader")
const KITS := ["urban_ruins", "grassy_hills"]
## How far the board slab extends below level 0.
const BASE_DEPTH := 0.6
## Surface kinds, stored in vertex color red for the terrain shader.
const KIND_STREET := 0
const KIND_CONCRETE := 1
const KIND_BUILDING := 2
const KIND_HAZARD := 3
## Grassy hills kinds.
const KIND_GRASS := 0
const KIND_ROUGH := 1
const KIND_ROCK := 2
const KIND_RIVERBED := 4

var map: BattleMap
var kit := "urban_ruins"
var material: ShaderMaterial
var grid_lines: MeshInstance3D
var _props: Node3D
var _shape: Dictionary


func build(battle_map: BattleMap, kit_name: String = "urban_ruins") -> void:
	map = battle_map
	kit = kit_name
	for c in get_children():
		c.queue_free()
	_shape = MeshKit.cell_shape(map.grid)
	material = ShaderMaterial.new()
	material.shader = HILLS_SHADER if kit == "grassy_hills" else TERRAIN_SHADER
	_build_blocks()
	_build_grid_lines()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	if kit == "grassy_hills":
		HillsDressing.build(self, _props)
	else:
		_build_props()
		_build_backdrop()


func set_grid_visible(on: bool) -> void:
	if grid_lines:
		grid_lines.visible = on


## World-space height of the top surface of a cell.
func top_y(cell: Vector2i) -> float:
	return map.ground_height(cell) * GridLayout.LEVEL_HEIGHT


## Cell outline corners in world space at height y.
func cell_corners(cell: Vector2i, y: float, inset: float = 0.0) -> PackedVector3Array:
	var c := map.grid.to_world(cell)
	var out := PackedVector3Array()
	for p: Vector2 in _shape["corners"]:
		var q := p * (1.0 - inset)
		out.append(Vector3(c.x + q.x, y, c.z + q.y))
	return out


func _solid(cell: Vector2i, level: int) -> bool:
	var col := map.column(cell)
	if col == null:
		return false
	if level < 0:
		return true
	if level >= col.ground:
		return false
	return not (col.gap_top > 0 and level >= col.gap_bottom and level < col.gap_top)


func _kind(cell: Vector2i) -> int:
	var col := map.column(cell)
	if kit == "grassy_hills":
		return hills_kind(cell)
	if col.has_tag(BattleMap.TAG_DANGEROUS):
		return KIND_HAZARD
	if col.ground >= 2:
		return KIND_BUILDING
	if col.ground == 1 or col.has_tag(BattleMap.TAG_DIFFICULT):
		return KIND_CONCRETE
	return KIND_STREET


## Grassy hills: water tag = riverbed, rock tag or a lone raised column = bare rock.
func hills_kind(cell: Vector2i) -> int:
	var col := map.column(cell)
	if col.has_tag("water"):
		return KIND_RIVERBED
	if col.has_tag(BattleMap.TAG_DANGEROUS):
		return KIND_HAZARD
	if col.has_tag("rock"):
		return KIND_ROCK
	if col.has_tag(BattleMap.TAG_DIFFICULT):
		return KIND_ROUGH
	return KIND_GRASS


func _drops(cell: Vector2i, edge: int, y_level: int) -> bool:
	var other: Vector2i = cell + (_shape["edge_neighbors"] as Array)[edge]
	return not map.has_cell(other) or map.ground_height(other) < y_level


func _build_blocks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: PackedVector2Array = _shape["corners"]
	var edge_n: Array[Vector2i] = _shape["edge_neighbors"]
	for cell in map.cells():
		var col := map.column(cell)
		var center := map.grid.to_world(cell)
		var kind := _kind(cell)
		var variation := MeshKit.hash01(str(cell))
		var base_col := Color(kind / 4.0 + 0.01 if kind < 4 else 1.0, variation, 0.0, 1.0)
		st.set_color(base_col)
		st.set_uv2(Vector2(0, col.ground * GridLayout.LEVEL_HEIGHT))
		# Tops: the ground surface, plus the floor under an overhang. Alpha marks edges that
		# drop away so the shader can wear them (dirt lip on grass).
		var tops: Array[int] = [col.ground]
		if col.gap_top > 0:
			tops.append(col.gap_bottom)
		for t in tops:
			var y := t * GridLayout.LEVEL_HEIGHT
			var n := corners.size()
			var c3 := Vector3(center.x, y, center.z)
			for i in range(n):
				var j := (i + 1) % n
				var ai := 0.0 if (_drops(cell, (i + n - 1) % n, t) or _drops(cell, i, t)) else 1.0
				var aj := 0.0 if (_drops(cell, i, t) or _drops(cell, j, t)) else 1.0
				_tri_colored(st, [c3, c3 + Vector3(corners[i].x, 0, corners[i].y), c3 + Vector3(corners[j].x, 0, corners[j].y)],
					[1.0, ai, aj], base_col)
			st.set_color(base_col)
		if col.gap_top > 0 and col.gap_top < col.ground:
			_fan(st, center, corners, col.gap_top * GridLayout.LEVEL_HEIGHT, Vector3.DOWN)
		# Sides: every run of levels that is solid here but open next door.
		for i in range(corners.size()):
			var other := cell + edge_n[i]
			var a := center + Vector3(corners[i].x, 0, corners[i].y)
			var b := center + Vector3(corners[(i + 1) % corners.size()].x, 0, corners[(i + 1) % corners.size()].y)
			var outward := (a + b) * 0.5 - center
			var run_start := -999
			for level in range(-1, col.ground + 1):
				var exposed := level < col.ground and _solid(cell, level) and not _solid(other, level)
				if exposed and run_start == -999:
					run_start = level
				elif not exposed and run_start != -999:
					var y0 := -BASE_DEPTH if run_start < 0 else run_start * GridLayout.LEVEL_HEIGHT
					var y1 := level * GridLayout.LEVEL_HEIGHT
					MeshKit.add_quad(st, a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0), outward)
					run_start = -999
	var mi := MeshInstance3D.new()
	mi.name = "Blocks"
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)


## An upward triangle with a per-vertex alpha (edge wear), front face up.
func _tri_colored(st: SurfaceTool, v: Array, alphas: Array, base: Color) -> void:
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(Vector3.UP) > 0.0:
		order = [0, 2, 1]
	for k: int in order:
		var col := base
		col.a = alphas[k]
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2((v[k] as Vector3).x, (v[k] as Vector3).z))
		st.add_vertex(v[k])


func _fan(st: SurfaceTool, center: Vector3, corners: PackedVector2Array, y: float, facing: Vector3) -> void:
	var c := Vector3(center.x, y, center.z)
	for i in range(corners.size()):
		var p := corners[i]
		var q := corners[(i + 1) % corners.size()]
		MeshKit.add_tri(st, c, c + Vector3(p.x, 0, p.y), c + Vector3(q.x, 0, q.y), facing)


func _build_grid_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(1, 1, 1, 1))
	for cell in map.cells():
		var col := map.column(cell)
		var ys: Array[float] = [col.ground * GridLayout.LEVEL_HEIGHT]
		if col.gap_top > 0:
			ys.append(col.gap_bottom * GridLayout.LEVEL_HEIGHT)
		for y in ys:
			add_outline(st, cell, y + 0.012, 0.04, 0.035)
	grid_lines = MeshInstance3D.new()
	grid_lines.name = "GridLines"
	grid_lines.mesh = st.commit()
	grid_lines.material_override = MeshKit.overlay_material(Color(0.85, 0.95, 1.0, 0.22))
	grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_lines)


## Adds a flat band just inside a cell's outline (used for grid lines and overlays).
func add_outline(st: SurfaceTool, cell: Vector2i, y: float, inset: float, width: float) -> void:
	var outer := cell_corners(cell, y, inset)
	var inner := cell_corners(cell, y, inset + width * 1.8)
	for i in range(outer.size()):
		var j := (i + 1) % outer.size()
		MeshKit.add_quad(st, outer[i], outer[j], inner[j], inner[i], Vector3.UP)


## Adds a filled cell top (slightly inset) to a SurfaceTool.
func add_cell_fill(st: SurfaceTool, cell: Vector2i, y: float, inset: float = 0.06) -> void:
	var pts := cell_corners(cell, y, inset)
	var c := map.grid.to_world(cell) + Vector3(0, y, 0)
	for i in range(pts.size()):
		MeshKit.add_tri(st, c, pts[i], pts[(i + 1) % pts.size()], Vector3.UP)


# --- Props -------------------------------------------------------------------------------

func _prop_mat(color: Color, metal: float = 0.1, rough: float = 0.85) -> ShaderMaterial:
	return MeshKit.mech_material(color, metal, rough, Color.BLACK, false)


func _build_props() -> void:
	var concrete := _prop_mat(Color(0.46, 0.44, 0.41))
	var dark := _prop_mat(Color(0.22, 0.21, 0.2))
	var rust := _prop_mat(Color(0.36, 0.2, 0.12), 0.5, 0.7)
	var steel := _prop_mat(Color(0.3, 0.31, 0.33), 0.8, 0.45)
	var corners: PackedVector2Array = _shape["corners"]
	var edge_n: Array[Vector2i] = _shape["edge_neighbors"]
	for cell in map.cells():
		var col := map.column(cell)
		var key := str(cell)
		var r := MeshKit.hash01(key, 1)
		var base := map.grid.to_world(cell) + Vector3(0, top_y(cell), 0)
		if col.has_tag(BattleMap.TAG_DIFFICULT):
			# Rubble pile: rough ground, low enough not to look like cover.
			for i in range(7):
				var off := Vector3(MeshKit.hash01(key, 10 + i) - 0.5, 0, MeshKit.hash01(key, 20 + i) - 0.5) * 0.7
				var s := 0.08 + 0.14 * MeshKit.hash01(key, 30 + i)
				MeshKit.part(_props, MeshKit.chamfer_box(Vector3(s * 1.4, s, s), 0.02), concrete if i % 3 else dark,
					base + off + Vector3(0, s * 0.35, 0), Vector3(MeshKit.hash01(key, 40 + i) * 40 - 20, MeshKit.hash01(key, 50 + i) * 180, 15))
			if r < 0.5:
				MeshKit.part(_props, MeshKit.cylinder(0.015, 0.5, 5), rust, base + Vector3(0.15, 0.15, -0.1), Vector3(60, r * 360, 20))
		elif col.ground == 0 and not col.has_tag(BattleMap.TAG_DANGEROUS):
			if r < 0.16:
				for i in range(3):
					var off := Vector3(MeshKit.hash01(key, 10 + i) - 0.5, 0, MeshKit.hash01(key, 20 + i) - 0.5) * 0.6
					var s := 0.04 + 0.06 * MeshKit.hash01(key, 30 + i)
					MeshKit.part(_props, MeshKit.chamfer_box(Vector3(s * 1.5, s, s), 0.01), concrete, base + off + Vector3(0, s * 0.4, 0), Vector3(0, MeshKit.hash01(key, 50 + i) * 180, 0))
		elif col.ground >= 2:
			# Rooftop clutter.
			if r < 0.18:
				MeshKit.part(_props, MeshKit.chamfer_box(Vector3(0.28, 0.16, 0.2), 0.015), steel, base + Vector3(0.1, 0.08, 0.05), Vector3(0, r * 900, 0))
			elif r < 0.27:
				MeshKit.part(_props, MeshKit.cylinder(0.13, 0.22, 10), rust, base + Vector3(-0.1, 0.11, 0.1))
			elif r < 0.33:
				MeshKit.part(_props, MeshKit.cylinder(0.008, 0.5, 4), steel, base + Vector3(0.2, 0.25, -0.15))
			# Broken parapet and exposed rebar along roof edges that drop off.
			for i in range(corners.size()):
				var other := cell + edge_n[i]
				if map.has_cell(other) and map.ground_height(other) >= col.ground:
					continue
				var a := corners[i]
				var b := corners[(i + 1) % corners.size()]
				var mid := (a + b) * 0.5 * 0.94
				var len := a.distance_to(b)
				var ang := -rad_to_deg(atan2(b.y - a.y, b.x - a.x))
				var keep := MeshKit.hash01(key, 60 + i)
				if keep < 0.65:
					var seg := len * (0.4 + 0.55 * keep)
					MeshKit.part(_props, MeshKit.chamfer_box(Vector3(seg, 0.07, 0.05), 0.01), concrete, base + Vector3(mid.x, 0.035, mid.y), Vector3(0, ang, 0))
				elif keep < 0.85:
					for k in range(3):
						var t := 0.25 + 0.25 * k
						var p := a.lerp(b, t) * 0.93
						MeshKit.part(_props, MeshKit.cylinder(0.008, 0.14 + 0.1 * MeshKit.hash01(key, 70 + k), 4), rust,
							base + Vector3(p.x, 0.07, p.y), Vector3(MeshKit.hash01(key, 80 + k) * 30 - 15, 0, 10))


func _build_backdrop() -> void:
	# Bounds of the board in world space.
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for cell in map.cells():
		var p := map.grid.to_world(cell)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var center := (lo + hi) * 0.5
	# Ground around the board.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.01, 0.3, 0.45, 1))
	var e := 60.0
	var y := -BASE_DEPTH
	MeshKit.add_quad(st, center + Vector3(-e, y, -e), center + Vector3(e, y, -e), center + Vector3(e, y, e), center + Vector3(-e, y, e), Vector3.UP)
	# Ruined skyline: blocks of buildings outside the board on every side.
	var half := (hi - lo) * 0.5 + Vector3(5.0, 0, 5.0)
	st.set_color(Color(KIND_BUILDING / 4.0 + 0.01, 0.6, 0.55, 1))
	var n := 0
	for side in range(4):
		for i in range(9):
			n += 1
			var t := (i + 0.5) / 9.0 * 2.0 - 1.0
			var depth := 1.0 + 8.0 * MeshKit.hash01("sky", n)
			var pos: Vector3
			match side:
				0: pos = Vector3(t * (half.x + 4), 0, -half.z - depth)
				1: pos = Vector3(t * (half.x + 4), 0, half.z + depth)
				2: pos = Vector3(-half.x - depth, 0, t * (half.z + 4))
				_: pos = Vector3(half.x + depth, 0, t * (half.z + 4))
			var w := 1.6 + 2.2 * MeshKit.hash01("sky", n + 100)
			var hgt := 3.0 + 9.0 * pow(MeshKit.hash01("sky", n + 200), 1.5)
			if side == 1 or MeshKit.hash01("sky", n + 300) < 0.25:
				continue  # leave the near side open so the camera sees the board; gaps elsewhere
			_box(st, center + pos + Vector3(0, y, 0), Vector3(w, hgt, w * 0.9))
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)


func _box(st: SurfaceTool, base: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c := base + Vector3(0, h.y, 0)
	var p := func(x: float, yy: float, z: float) -> Vector3: return c + Vector3(x * h.x, yy * h.y, z * h.z)
	MeshKit.add_quad(st, p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1), Vector3.UP)
	MeshKit.add_quad(st, p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), Vector3.BACK)
	MeshKit.add_quad(st, p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(-1, 1, -1), Vector3.FORWARD)
	MeshKit.add_quad(st, p.call(1, -1, -1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(1, 1, -1), Vector3.RIGHT)
	MeshKit.add_quad(st, p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), Vector3.LEFT)
