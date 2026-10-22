class_name TerrainRenderer
extends Node3D
## Draws a BattleMap as terraced blocks in a world style (WorldStyle: landscape + culture),
## with grid lines on every surface a unit can stand on, dressing on the board and a full
## horizon around it. Call build() again whenever the map changes.
##
## What you see is what the rules use. Every look comes from the map data:
## - raised columns are solid (ground, rock, crystal, walls, buildings): hard cover/obstacles;
## - `soft_cover` columns get woods (or another tall see-through look): soft cover;
## - `difficult` gets rough ground (mud, rubble, scree, brush), `dangerous` glows/burns,
##   `impassable` at ground level is a chasm, `destructible` shows cracks and can break;
## - decoration everywhere else stays small and flat (grass, flowers, pebbles, litter).
## Visual-only tags pick a look without changing rules: water, toxic, lava, ice (liquids),
## rock, crystal, wall, building, woods, rubble, chasm. See src/render/world/README.md.
## Works on any GridLayout: cell outlines come from MeshKit.cell_shape().

const WORLD_SHADER := preload("res://src/render/shaders/terrain_world.gdshader")
## How far the board slab extends below level 0.
const BASE_DEPTH := 0.6
## How deep an impassable chasm looks.
const CHASM_DEPTH := 3.0
## Liquid beds sit this far below the cell's ground; the surface is just under ground level.
const LIQUID_SINK := 0.35
const LIQUID_SURFACE := 0.07
## Surface kinds, stored in vertex color red (kind / 16) for the terrain shader.
const KIND_GROUND := 0
const KIND_ROUGH := 1
const KIND_ROCK := 2
const KIND_HAZARD := 3
const KIND_BED := 4
const KIND_CRYSTAL := 6
const KIND_WALL := 7
const KIND_CHASM := 8
const KIND_BRIDGE := 9
const KIND_BULKHEAD := 10
const KIND_CONTAINER := 11
const KIND_DECK := 12
const KIND_MACHINERY := 13
const KIND_ROAD := 14
const KIND_FARM := 15
const ROAD_STYLES := {"dirt": 0, "cobble": 1, "asphalt": 2, "panels": 3}
## Liquid look tags (the cell's rules come from its other tags, e.g. difficult/dangerous).
const LIQUIDS := ["water", "toxic", "lava", "ice"]
const GROUND_STYLES := {"grass": 0, "sand": 1, "snow": 2, "moss": 3, "paving": 4, "ash": 5, "deck": 6, "regolith": 7}

var map: BattleMap
## Resolved kit name ("landscape" or "landscape/culture").
var kit := "grassy_hills"
var style: Dictionary = {}
var material: ShaderMaterial
var grid_lines: MeshInstance3D
## Cells drawn by a structure builder (buildings), which the block mesh leaves out.
var structure_cells: Dictionary = {}
## Cells whose terrain the rules destroyed (cell -> true). Remembered across rebuilds of the
## same board so the debris stays; reset when a different board is built.
var broken_cells: Dictionary = {}
## Sitrep objectives shown on the board ([zones, deployment, show_deployment]), redrawn on
## every rebuild. Set with show_objectives().
var objectives: Array = []
## The facade material of this board's buildings (CityBuilder), for collapse pieces.
var building_material: Material
## Building look per structure cell from the last build: cell -> {color, type, top}.
var building_looks: Dictionary = {}
## Damage on destructible columns' top sections, {"x,y": damage} (GameState.terrain_damage):
## shown as deeper cracks. Set with show_damage().
var damage: Dictionary = {}
var _props: Node3D
var _shape: Dictionary
var _bottom := -BASE_DEPTH


func build(battle_map: BattleMap, kit_name: String = "grassy_hills") -> void:
	if battle_map != map:
		broken_cells = {}
	map = battle_map
	style = WorldStyle.resolve(kit_name)
	kit = style["kit"]
	for c in get_children():
		remove_child(c)
		if is_inside_tree():
			c.queue_free()
		else:
			c.free()  # queue_free never runs outside the tree
	_shape = MeshKit.cell_shape(map.grid)
	material = make_material(style)
	structure_cells = {}
	_bottom = -BASE_DEPTH
	for cell in map.cells():
		if is_chasm(cell):
			_bottom = -BASE_DEPTH - CHASM_DEPTH
			break
	var city := CityBuilder.new(self)
	_lap("start")
	city.claim()
	_build_blocks()
	_lap("blocks")
	_build_grid_lines()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	city.build(_props)
	_lap("city")
	WorldDressing.build(self, _props)
	_lap("dressing")
	if not objectives.is_empty():
		_draw_objectives()


## Build timing for profiling: set TerrainRenderer.profile = true to print each step.
static var profile := false
static var _lap_t := 0


static func _lap(step: String) -> void:
	if profile:
		var now := Time.get_ticks_msec()
		if step != "start":
			print("  terrain %s: %d ms" % [step, now - _lap_t])
		_lap_t = now


## Draws the sitrep's zones on the board (ObjectiveMarkers): zone name -> [[x, y]] and side
## -> [[x, y]] as in Mission.zones / Mission.deployment. Pass only what the seat may know.
## Empty zones and deployment clear the markers. Deployment tints are for the setup phase.
func show_objectives(zones: Dictionary, deployment: Dictionary = {}, show_deployment: bool = true) -> void:
	objectives = [] if zones.is_empty() and deployment.is_empty() else [zones, deployment, show_deployment]
	_draw_objectives()


func _draw_objectives() -> void:
	var old := get_node_or_null("Objectives")
	if old:
		remove_child(old)
		if is_inside_tree():
			old.queue_free()
		else:
			old.free()
	if objectives.is_empty() or map == null:
		return
	var m := ObjectiveMarkers.new()
	m.name = "Objectives"
	add_child(m)
	m.setup(self, objectives[0], objectives[1], objectives[2])


## Sky, sun and fog for this board's style (BattleView calls it after build()).
func apply_environment(env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D = null) -> void:
	WorldAtmosphere.apply(style, env, sun, fill)


func set_grid_visible(on: bool) -> void:
	if grid_lines:
		grid_lines.visible = on


static func make_material(s: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WORLD_SHADER
	var g: Dictionary = s.get("ground", {})
	m.set_shader_parameter("top_style", GROUND_STYLES.get(str(g.get("style", "grass")), 0))
	for k: String in ["top_a", "top_b", "top_dry", "soil", "rock_a", "rock_b", "bed"]:
		if g.has(k):
			m.set_shader_parameter(k, WorldStyle.color(g[k]))
	var pairs := {"rough": "rough_col", "hazard": "hazard_col", "veins": "vein_col", "crystal": "crystal_col", "wall": "wall_col",
		"metal_a": "metal_a", "metal_b": "metal_b", "stripe": "stripe_col", "strip_light": "strip_light",
		"cargo_a": "cargo_a", "cargo_b": "cargo_b", "cargo_c": "cargo_c"}
	for k: String in pairs:
		if g.has(k):
			m.set_shader_parameter(pairs[k], WorldStyle.color(g[k]))
	var road: String = str(WorldStyle.value(s, "architecture.street.road", g.get("road", "asphalt" if s.has("architecture") else "dirt")))
	m.set_shader_parameter("road_style", ROAD_STYLES.get(road, 2))
	for k: String in ["strata", "soil_depth", "wetness", "vein_strength", "columnar", "rim_strength", "rim_glow", "backdrop_fade"]:
		if g.has(k):
			m.set_shader_parameter(k, float(g[k]))
	if g.has("rim"):
		m.set_shader_parameter("rim_color", WorldStyle.color(g["rim"]))
	return m


## World-space height of the top surface of a cell.
func top_y(cell: Vector2i) -> float:
	return map.ground_height(cell) * GridLayout.LEVEL_HEIGHT


## Where a cell's visible floor is: its ground, or the bottom of a chasm.
func floor_y(cell: Vector2i) -> float:
	if is_chasm(cell):
		return -CHASM_DEPTH
	if liquid_of(cell) != "":
		return top_y(cell) - LIQUID_SINK
	return top_y(cell)


## Cell outline corners in world space at height y.
func cell_corners(cell: Vector2i, y: float, inset: float = 0.0) -> PackedVector3Array:
	var c := map.grid.to_world(cell)
	var out := PackedVector3Array()
	for p: Vector2 in _shape["corners"]:
		var q := p * (1.0 - inset)
		out.append(Vector3(c.x + q.x, y, c.z + q.y))
	return out


## A random point inside a cell (on its floor), stable for `key` and `i`.
func random_point(cell: Vector2i, key: String, i: int, spread: float = 0.85) -> Vector3:
	var corners: PackedVector2Array = _shape["corners"]
	var k := int(WorldRand.f(key, i) * corners.size()) % corners.size()
	var a := corners[k]
	var b := corners[(k + 1) % corners.size()]
	var u := WorldRand.f(key, i + 1000)
	var v := WorldRand.f(key, i + 2000)
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var p := (a * u + b * v) * spread
	return map.grid.to_world(cell) + Vector3(p.x, floor_y(cell), p.y)


func liquid_of(cell: Vector2i) -> String:
	var col := map.column(cell)
	for t: String in LIQUIDS:
		if col.has_tag(t):
			return t
	return ""


func is_chasm(cell: Vector2i) -> bool:
	var col := map.column(cell)
	return col != null and (col.has_tag("chasm") or (col.has_tag(BattleMap.TAG_IMPASSABLE) and col.ground == 0 and liquid_of(cell) == ""))


func is_woods(cell: Vector2i) -> bool:
	var col := map.column(cell)
	return col.has_tag(Sight.TAG_SOFT_COVER) and not col.has_tag("smoke")


## Surface kind of a cell from its rules tags and look tags.
func surface(cell: Vector2i) -> int:
	var col := map.column(cell)
	if liquid_of(cell) != "":
		return KIND_BED
	if is_chasm(cell):
		return KIND_CHASM
	if col.has_tag(BattleMap.TAG_DANGEROUS):
		return KIND_HAZARD
	if col.has_tag("crystal"):
		return KIND_CRYSTAL
	if col.has_tag("rock") or (col.has_tag(BattleMap.TAG_IMPASSABLE) and col.ground > 0):
		return KIND_ROCK
	if (col.has_tag("road") or col.has_tag("lot") or col.has_tag("plaza") or col.has_tag("rail")) and not col.has_tag(BattleMap.TAG_DANGEROUS) and col.gap_top == 0:
		return KIND_ROAD
	if col.has_tag("farm"):
		return KIND_FARM
	if col.has_tag("bulkhead"):
		return KIND_BULKHEAD
	if col.has_tag("container"):
		return KIND_CONTAINER
	if col.has_tag("machinery"):
		return KIND_MACHINERY
	if col.has_tag("deck") or col.has_tag("platform"):
		return KIND_DECK
	if col.gap_top > 0 and col.gap_top > col.gap_bottom:
		return KIND_BRIDGE
	if col.has_tag("wall") or col.has_tag("building"):
		return KIND_WALL
	if col.has_tag(BattleMap.TAG_DIFFICULT):
		return KIND_ROUGH
	return KIND_GROUND


## Kept for older callers: the surface kind.
func hills_kind(cell: Vector2i) -> int:
	return surface(cell)


## Solid spans [y0, y1) of a column as the eye sees it (gap carved out; chasms sunk).
func _spans(cell: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var col := map.column(cell)
	if col == null:
		return out
	if is_chasm(cell):
		out.append(Vector2(_bottom, -CHASM_DEPTH))
		return out
	var top := floor_y(cell)
	if col.gap_top > 0 and col.gap_top > col.gap_bottom:
		out.append(Vector2(_bottom, col.gap_bottom * GridLayout.LEVEL_HEIGHT))
		if col.gap_top < col.ground:
			out.append(Vector2(col.gap_top * GridLayout.LEVEL_HEIGHT, top))
	else:
		out.append(Vector2(_bottom, top))
	return out


## Parts of `a` not covered by `b` (both sorted, non-overlapping).
static func _subtract(a: Array[Vector2], b: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in a:
		var parts: Array[Vector2] = [s]
		for t in b:
			var next: Array[Vector2] = []
			for p in parts:
				if t.y <= p.x or t.x >= p.y:
					next.append(p)
					continue
				if t.x > p.x:
					next.append(Vector2(p.x, t.x))
				if t.y < p.y:
					next.append(Vector2(t.y, p.y))
			parts = next
		for p in parts:
			if p.y - p.x > 0.001:
				out.append(p)
	return out


func _drops(cell: Vector2i, edge: int, y: float) -> bool:
	var other: Vector2i = cell + (_shape["edge_neighbors"] as Array)[edge]
	return not map.has_cell(other) or floor_y(other) < y - 0.01 or structure_cells.has(other) != structure_cells.has(cell)


func _build_blocks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: PackedVector2Array = _shape["corners"]
	var edge_n: Array[Vector2i] = _shape["edge_neighbors"]
	var sides: Array = []
	var corner_normals := {}
	var span_cache := {}
	for cell in map.cells():
		span_cache[cell] = _spans(cell)
	for cell in map.cells():
		if structure_cells.has(cell):
			continue
		var col := map.column(cell)
		var center := map.grid.to_world(cell)
		var kind := surface(cell)
		var variation := WorldRand.f(str(cell))
		if kind == KIND_ROAD:
			# Roads carry their direction for the lane markings (shader): along x, along z, crossing.
			# Lots (yards, sidewalks, squares between a settlement's buildings): 0.97, no markings.
			# Straight roads add their lane (i across, n wide; tag "lane<i>_<n>") in 1/255 steps:
			# along x 0.05 + code, along z 0.4 + code (code = n * 6 + i), so the shader can draw
			# centre lines, lane lines, medians and curbs where they belong.
			if col.has_tag("rail"):
				variation = 0.915 if col.has_tag("rail_z") else 0.9
			elif col.has_tag("plaza") and not col.has_tag("road"):
				variation = 0.99
			elif col.has_tag("lot") and not col.has_tag("road"):
				variation = 0.97
			elif col.has_tag("crossing"):
				variation = 0.85
			else:
				var code := 0
				for t in col.tags:
					if t.begins_with("lane"):
						var p := t.trim_prefix("lane").split("_")
						code = int(p[1]) * 6 + int(p[0])
				if col.has_tag("crosswalk"):
					code += 42
				variation = (0.45 if col.has_tag("road_z") else 0.05) + code / 255.0
		elif kind == KIND_FARM:
			variation = (0.75 if col.has_tag("dry") else 0.25) + 0.2 * WorldRand.f(str(cell), 3)
		var base_col := Color(kind / 16.0, variation, 0.0, 1.0)
		# UV2.x: 0 sturdy, 1 + damage fraction for destructible (the shader cracks it deeper).
		var flags := 0.0
		if col.has_tag(BattleMap.TAG_DESTRUCTIBLE):
			flags = 1.0 + clampf(float(damage.get("%d,%d" % [cell.x, cell.y], 0)) / 10.0, 0.0, 0.95)
		var spans: Array[Vector2] = span_cache[cell]
		var top := spans[spans.size() - 1].y
		st.set_color(base_col)
		st.set_uv2(Vector2(flags, top))
		# Tops of every span (the ground, and the floor under an overhang). Alpha marks edges
		# that drop away so the shader can wear them.
		for s in spans:
			var y := s.y
			var n := corners.size()
			var c3 := Vector3(center.x, y, center.z)
			for i in range(n):
				var j := (i + 1) % n
				var ai := 0.0 if (_drops(cell, (i + n - 1) % n, y) or _drops(cell, i, y)) else 1.0
				var aj := 0.0 if (_drops(cell, i, y) or _drops(cell, j, y)) else 1.0
				_tri_colored(st, [c3, c3 + Vector3(corners[i].x, 0, corners[i].y), c3 + Vector3(corners[j].x, 0, corners[j].y)],
					[1.0, ai, aj], base_col)
			st.set_color(base_col)
		# Ceilings under overhangs.
		for k in range(spans.size() - 1):
			_fan(st, center, corners, spans[k + 1].x, Vector3.DOWN)
		# Sides: every span that is solid here but open next door.
		for i in range(corners.size()):
			var other := cell + edge_n[i]
			var a := center + Vector3(corners[i].x, 0, corners[i].y)
			var b := center + Vector3(corners[(i + 1) % corners.size()].x, 0, corners[(i + 1) % corners.size()].y)
			var outward := ((a + b) * 0.5 - center).normalized()
			var theirs: Array[Vector2] = []
			if map.has_cell(other) and not structure_cells.has(other):
				theirs = span_cache[other]
			elif structure_cells.has(other):
				# Buildings draw their own walls down to their foot; keep ours below it.
				theirs = [Vector2(_bottom, minf(top_y(other), top))]
			if kind == KIND_CRYSTAL:
				continue  # crystal prisms (WorldDressing) form the sides
			for s in _subtract(spans, theirs):
				sides.append([a, b, s, outward, base_col, Vector2(flags, top)])
				for p: Vector3 in [a, b]:
					var key := Vector2i(roundi(p.x * 512.0), roundi(p.z * 512.0))
					corner_normals[key] = corner_normals.get(key, Vector3.ZERO) + outward
	# Side walls get normals averaged across neighboring faces at each vertical edge, so a
	# cliff made of hex facets is lit like one rounded rock face instead of stripes.
	for e: Array in sides:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var s: Vector2 = e[2]
		var n: Vector3 = e[3]
		var na := _smooth_normal(corner_normals, a, n)
		var nb := _smooth_normal(corner_normals, b, n)
		st.set_color(e[4])
		st.set_uv2(e[5])
		st.set_uv(Vector2(0, s.x))  # the floor this wall rises from
		var quad := [[a + Vector3(0, s.x, 0), na], [b + Vector3(0, s.x, 0), nb], [b + Vector3(0, s.y, 0), nb], [a + Vector3(0, s.y, 0), na]]
		# Wind so the front faces outward (clockwise seen from outside).
		var order := [0, 1, 2, 0, 2, 3]
		if ((quad[1][0] as Vector3) - (quad[0][0] as Vector3)).cross((quad[2][0] as Vector3) - (quad[0][0] as Vector3)).dot(n) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(quad[k][1])
			st.add_vertex(quad[k][0])
	var mi := MeshInstance3D.new()
	mi.name = "Blocks"
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)


static func _smooth_normal(sums: Dictionary, p: Vector3, face: Vector3) -> Vector3:
	var sum: Vector3 = sums.get(Vector2i(roundi(p.x * 512.0), roundi(p.z * 512.0)), face)
	var n := (sum.normalized() + face * 0.35).normalized()
	return n if n.length() > 0.5 else face


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
		# Tops: UV is the offset from the cell's center (for road markings).
		st.set_uv(Vector2((v[k] as Vector3).x - a.x, (v[k] as Vector3).z - a.z))
		st.add_vertex(v[k])


func _fan(st: SurfaceTool, center: Vector3, corners: PackedVector2Array, y: float, facing: Vector3) -> void:
	var c := Vector3(center.x, y, center.z)
	for i in range(corners.size()):
		var p := corners[i]
		var q := corners[(i + 1) % corners.size()]
		MeshKit.add_tri(st, c, c + Vector3(p.x, 0, p.y), c + Vector3(q.x, 0, q.y), facing)


func _build_grid_lines() -> void:
	# Two-tone lines: a soft dark band under a light core, so the grid reads on bright sand
	# and snow as well as on dark rock and night streets.
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	dark.set_color(Color(1, 1, 1, 1))
	var light := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	light.set_color(Color(1, 1, 1, 1))
	for cell in map.cells():
		if is_chasm(cell):
			continue
		var col := map.column(cell)
		var ys: Array[float] = [col.ground * GridLayout.LEVEL_HEIGHT]
		if col.gap_top > 0:
			ys.append(col.gap_bottom * GridLayout.LEVEL_HEIGHT)
		for y in ys:
			add_outline(dark, cell, y + 0.01, 0.025, 0.06)
			add_outline(light, cell, y + 0.014, 0.04, 0.036)
		_board_edge(light, dark, cell, col.ground * GridLayout.LEVEL_HEIGHT)
	grid_lines = MeshInstance3D.new()
	grid_lines.name = "GridLines"
	grid_lines.mesh = light.commit()
	var line_mat := MeshKit.overlay_material(WorldStyle.color(WorldStyle.value(style, "grid_color", [0.92, 0.97, 1.0, 0.32]))).duplicate() as StandardMaterial3D
	line_mat.render_priority = 2  # always over its shade band
	grid_lines.material_override = line_mat
	grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_lines)
	var under := MeshInstance3D.new()
	under.name = "GridShade"
	under.mesh = dark.commit()
	under.material_override = MeshKit.overlay_material(WorldStyle.color(WorldStyle.value(style, "grid_shade", [0.0, 0.0, 0.0, 0.22])))
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Hidden and shown with the grid.
	grid_lines.add_child(under)


## The board's outer boundary: a wider light band with a dark shadow outside it, along every
## cell edge that has no neighbor on the map.
func _board_edge(light: SurfaceTool, dark: SurfaceTool, cell: Vector2i, y: float) -> void:
	var edge_n: Array[Vector2i] = _shape["edge_neighbors"]
	var outer := cell_corners(cell, y + 0.016, 0.0)
	var inner := cell_corners(cell, y + 0.016, 0.1)
	var shade := cell_corners(cell, y + 0.012, -0.06)
	for i in range(outer.size()):
		if map.has_cell(cell + edge_n[i]):
			continue
		var j := (i + 1) % outer.size()
		MeshKit.add_quad(light, outer[i], outer[j], inner[j], inner[i], Vector3.UP)
		MeshKit.add_quad(dark, shade[i], shade[j], outer[j], outer[i], Vector3.UP)


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


## Bounds of the board on the ground plane (x, z), grown by `margin`.
func bounds(margin: float = 0.6) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in map.cells():
		var p := map.grid.to_world(c)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return Rect2(lo, hi - lo).grow(margin)


## The material a column is made of ("material_*" tag), or "" if none.
static func material_of(col: BattleMap.Column) -> String:
	if col == null:
		return ""
	for t in col.tags:
		if t.begins_with("material_"):
			return t.substr(9)
	return ""


## Shows damage on destructible terrain ({"x,y": damage}, as GameState.terrain_damage):
## cracks deepen as a section loses its 10 HP. Only the block mesh is rebuilt.
func show_damage(d: Dictionary) -> void:
	damage = d.duplicate()
	var old := get_node_or_null("Blocks")
	if old == null:
		return
	remove_child(old)
	if is_inside_tree():
		old.queue_free()
	else:
		old.free()
	_build_blocks()


## A hit on a terrain column (event terrain_damaged): splinters for wood, chips and dust for
## stone and concrete, sparks and a dent flash for metal and fortified walls. `from` is where
## the attack came from (optional), so debris flies back toward it.
func hit_terrain(cell: Vector2i, amount: int = 5, from: Vector3 = Vector3.INF) -> void:
	TerrainBreak.hit(self, cell, amount, from)


## Terrain destroyed by the rules: the map already has the new columns. Shows the old
## structures breaking apart at `cells` (old_heights: cell -> old ground) and rebuilds.
func break_cells(cells: Array, old_heights: Dictionary = {}) -> void:
	for c: Vector2i in cells:
		broken_cells[c] = true
	TerrainBreak.play(self, cells, old_heights)
	build(map, kit)


## Brings the board up to date with a newer copy of the map (the rules' current terrain, e.g.
## from a fresh view after an attack). Every destructible column that got lower collapses
## visibly; then the board is rebuilt from the new data. Returns the cells that broke.
## What's left is whatever the new data says: rubble that slows you only if the rules tagged
## the cell difficult, otherwise flat debris.
func sync_map(new_map: BattleMap) -> Array:
	var broke: Array = []
	var old := {}
	if map != null:
		for c in new_map.cells():
			var was := map.column(c)
			var now := new_map.column(c)
			if was != null and now != null and was.has_tag(BattleMap.TAG_DESTRUCTIBLE) and now.ground < was.ground:
				broke.append(c)
				old[c] = was.ground
	var keep := broken_cells
	map = new_map
	broken_cells = keep
	if broke.is_empty():
		build(map, kit)
	else:
		break_cells(broke, old)
	return broke
