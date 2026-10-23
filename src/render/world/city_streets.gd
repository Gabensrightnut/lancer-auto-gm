class_name CityStreets
extends RefCounted
## Street life on road cells, by culture (architecture.street): parked vehicles on the cells
## the map marks `vehicle` (objects: soft cover, breakable; TerrainGen._parked_vehicles),
## traffic lights at crossings, kiosks and steam vents, overhead wires (with lanterns in East
## Asian towns), and moving traffic on the city's streets beyond the board. Apart from the
## parked vehicles it is all scenery: poles and wires are thin, and the rules see none of it.

const VEHICLE_HEIGHT := 0.28
## Parked vehicles on the board are objects (cover): drawn about a cell long.
const VEHICLE_SCALE := 1.45


static func build(t: TerrainRenderer, root: Node3D) -> void:
	var street: Dictionary = WorldStyle.value(t.style, "architecture.street", {}) if t.style.has("architecture") else {}
	var roads: Array[Vector2i] = []
	for c in t.map.cells():
		if t.surface(c) == TerrainRenderer.KIND_ROAD and t.map.column(c).has_tag("road"):
			roads.append(c)  # streets only: yards and lots stay clear of parked cars
	if roads.is_empty():
		return
	var kinds: Array = street.get("vehicles", ["car"] if t.style.get("urban", false) else ["cart"])
	_parked(t, root, roads, kinds)
	if bool(street.get("traffic_lights", false)):
		_traffic_lights(t, root, roads)
	if float(street.get("kiosks", 0.0)) > 0.0:
		_kiosks(t, root, float(street["kiosks"]))
	if float(street.get("vents", 0.0)) > 0.0:
		_vents(t, root, roads, float(street["vents"]))
	if float(street.get("wires", 0.0)) > 0.0:
		_wires(t, root, roads, float(street["wires"]), bool(street.get("lanterns_on_wires", false)))


static func _axis(t: TerrainRenderer, c: Vector2i) -> String:
	var col := t.map.column(c)
	return "crossing" if col.has_tag("crossing") else ("z" if col.has_tag("road_z") else "x")


## Parked along the side of the lane, nose along the road, one every few spaces.
static func _parked(t: TerrainRenderer, root: Node3D, roads: Array[Vector2i], kinds: Array) -> void:
	var groups := {}
	for c in roads:
		var axis := _axis(t, c)
		var key := "pk" + str(c)
		if axis == "crossing" or not t.map.column(c).has_tag("vehicle"):
			continue  # only the map's own vehicles: what you see is what gives cover
		var kind: String = kinds[int(WorldRand.f(key, 1) * kinds.size()) % kinds.size()]
		var paint := Vehicles.paint_for(kind, WorldRand.f(key, 2))
		var side := 1.0 if WorldRand.f(key, 3) < 0.5 else -1.0
		var base := t.map.grid.to_world(c) + Vector3.UP * t.top_y(c)
		var yaw := 0.0 if axis == "x" else PI * 0.5
		if WorldRand.f(key, 4) < 0.5:
			yaw += PI
		var off := Vector3(0, 0, side * 0.27) if axis == "x" else Vector3(side * 0.27, 0, 0)
		# At object scale: about a cell long, so it reads as the cover it is.
		var xf := Transform3D(Basis(Vector3.UP, yaw + (WorldRand.f(key, 5) - 0.5) * (0.5 if kind == "wreck" else 0.08)) * Basis.from_scale(Vector3.ONE * VEHICLE_SCALE), base + off * 0.4)
		var g := "%s|%s" % [kind, paint.to_html()]
		if not groups.has(g):
			groups[g] = [kind, paint, []]
		(groups[g][2] as Array).append(xf)
	var mat := WorldDressing.foliage_material(0.0, 1.0, 0.0)
	for g: String in groups:
		var e: Array = groups[g]
		WorldDressing.multi(root, "Vehicles", Vehicles.mesh(e[0], e[1]), e[2], mat, true)


## A pole on one corner of each crossing with a three-light head cycling green-amber-red.
static func _traffic_lights(t: TerrainRenderer, root: Node3D, roads: Array[Vector2i]) -> void:
	var dark := MeshKit.mech_material(Color(0.1, 0.1, 0.11), 0.6, 0.4, Color.BLACK, false)
	var n := 0
	for c in roads:
		if _axis(t, c) != "crossing" or WorldRand.f("tl" + str(c), 0) > 0.5 or n >= 24:
			continue
		n += 1
		var corners := t.cell_corners(c, t.top_y(c), 0.12)
		var p := corners[int(WorldRand.f("tl" + str(c), 1) * corners.size()) % corners.size()]
		MeshKit.part(root, MeshKit.cylinder(0.012, 0.75, 6), dark, p + Vector3.UP * 0.375)
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.05, 0.13, 0.05), 0.005), dark, p + Vector3.UP * 0.8)
		var light := TrafficLight.new()
		light.position = p + Vector3.UP * 0.8
		light.phase = WorldRand.f("tl" + str(c), 2) * 9.0
		root.add_child(light)


## Small booths with lit signs on open ground next to buildings (not on roads).
static func _kiosks(t: TerrainRenderer, root: Node3D, chance: float) -> void:
	var body := MeshKit.mech_material(Color(0.18, 0.18, 0.2), 0.4, 0.5, Color.BLACK, false)
	var neon_cols: Array = WorldStyle.value(t.style, "architecture.neon_colors", ["#ffcc22"])
	var xf: Array = []
	var signs := {}
	for c in t.map.cells():
		if t.surface(c) != TerrainRenderer.KIND_GROUND or t.structure_cells.has(c) or WorldRand.f("ks" + str(c), 0) > chance:
			continue
		var by_building := false
		var by_road := false
		for n in t.map.grid.neighbors(c):
			by_building = by_building or t.structure_cells.has(n)
			by_road = by_road or (t.map.has_cell(n) and t.surface(n) == TerrainRenderer.KIND_ROAD)
		if not (by_building and by_road):
			continue
		var p := t.random_point(c, "ks" + str(c), 1, 0.4)
		var rot := Basis(Vector3.UP, WorldRand.f("ks" + str(c), 2) * TAU)
		xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.32, 0.26, 0.22)), p + Vector3.UP * 0.13))
		var col := WorldStyle.color(neon_cols[int(WorldRand.f("ks" + str(c), 3) * neon_cols.size()) % neon_cols.size()])
		if not signs.has(col):
			signs[col] = []
		(signs[col] as Array).append(Transform3D(rot * Basis.from_scale(Vector3(0.3, 0.05, 0.02)), p + Vector3.UP * 0.29))
	WorldDressing.multi(root, "Kiosks", MeshKit.chamfer_box(Vector3.ONE, 0.04), xf, body, true)
	for col: Color in signs:
		WorldDressing.multi(root, "KioskSigns", MeshKit.chamfer_box(Vector3.ONE, 0.0), signs[col], MeshKit.mech_material(col, 0.0, 0.5, col * 2.0, false), false)


## Grates in the road with steam drifting up from some of them.
static func _vents(t: TerrainRenderer, root: Node3D, roads: Array[Vector2i], chance: float) -> void:
	var grate := MeshKit.mech_material(Color(0.12, 0.12, 0.13), 0.7, 0.5, Color.BLACK, false)
	var points := PackedVector3Array()
	var xf: Array = []
	for c in roads:
		if WorldRand.f("vt" + str(c), 0) > chance:
			continue
		var p := t.random_point(c, "vt" + str(c), 1, 0.3)
		xf.append(Transform3D(Basis.from_scale(Vector3(0.22, 0.01, 0.16)), p + Vector3.UP * 0.005))
		if WorldRand.f("vt" + str(c), 2) < 0.6:
			points.append(p)
	WorldDressing.multi(root, "Vents", MeshKit.chamfer_box(Vector3.ONE, 0.0), xf, grate, false)
	if points.is_empty():
		return
	var steam := CPUParticles3D.new()
	steam.name = "Steam"
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	steam.emission_points = points
	steam.amount = WorldQuality.particles(mini(points.size() * 8, 600))
	steam.lifetime = 3.0
	steam.preprocess = 3.0
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.gravity = Vector3(0.1, 0.15, 0)
	steam.initial_velocity_min = 0.2
	steam.initial_velocity_max = 0.4
	steam.scale_amount_min = 0.6
	steam.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = WorldHazards._quad_material(Color(1, 1, 1), false)
	steam.mesh = q
	steam.color_ramp = WorldHazards._ramp([[0.0, Color(0.85, 0.88, 0.92, 0.0)], [0.2, Color(0.85, 0.88, 0.92, 0.18)], [1.0, Color(0.9, 0.92, 0.95, 0.0)]])
	root.add_child(steam)


## Cables strung across streets between the buildings on either side, sagging; East Asian
## towns hang lanterns on them.
static func _wires(t: TerrainRenderer, root: Node3D, roads: Array[Vector2i], chance: float, lanterns: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lantern_xf: Array = []
	var count := 0
	for c in roads:
		var axis := _axis(t, c)
		if axis == "crossing" or WorldRand.f("wr" + str(c), 0) > chance:
			continue
		# Walk across the street both ways to the first building.
		var step_a: Vector3 = Vector3(0, 0, 1) if axis == "x" else Vector3(1, 0, 0)
		var base := t.map.grid.to_world(c)
		var ends: Array = []
		for s: float in [-1.0, 1.0]:
			for k in range(1, 6):
				var q := t.map.grid.from_world(base + step_a * s * k)
				if t.structure_cells.has(q):
					var hgt := minf(t.top_y(q), 2.5)
					ends.append(base + step_a * s * (k - 0.5) + Vector3.UP * hgt * 0.8)
					break
		if ends.size() < 2:
			continue
		count += 1
		var a: Vector3 = ends[0]
		var b: Vector3 = ends[1]
		var sag := a.distance_to(b) * 0.08
		var prev := a
		for i in range(1, 9):
			var u := i / 8.0
			var p := a.lerp(b, u) - Vector3.UP * sag * 4.0 * u * (1.0 - u)
			_cable(st, prev, p)
			prev = p
			if lanterns and i % 2 == 0 and i < 8:
				lantern_xf.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.06), p - Vector3.UP * 0.06))
	if count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Wires"
	mi.mesh = st.commit()
	mi.material_override = MeshKit.mech_material(Color(0.05, 0.05, 0.05), 0.2, 0.7, Color.BLACK, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if not lantern_xf.is_empty():
		var lc := Color(1.0, 0.45, 0.25)
		WorldDressing.multi(root, "Lanterns", MeshKit.sphere(1.0, 8), lantern_xf, MeshKit.mech_material(lc, 0.0, 0.5, lc * 2.5, false), false)


static func _cable(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP).normalized() * 0.006
	var up := Vector3.UP * 0.006
	MeshKit.add_quad(st, a - side, b - side, b + side, a + side, Vector3.UP)
	MeshKit.add_quad(st, a - up, b - up, b + up, a + up, side)
