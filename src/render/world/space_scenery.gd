class_name SpaceScenery
extends RefCounted
## Scenery for space maps (outside the board only): two ships docked side by side for a
## boarding fight (their hulls running off past the board, open space between them); a station's superstructure of modules,
## trusses and lit habitat rings; a ship's hull running away from the board with its
## superstructure and engines; drifting asteroids around airless rocks. No names or markings.


static func build(t: TerrainRenderer, root: Node3D, b: Rect2, kind: String) -> void:
	var hull := WorldStyle.col(t.style, "ground.metal_b", Color(0.25, 0.26, 0.28))
	var plate := WorldStyle.col(t.style, "ground.metal_a", Color(0.4, 0.42, 0.45))
	var light := WorldStyle.col(t.style, "ground.strip_light", Color(0.6, 0.85, 1.0))
	var c := Vector3(b.get_center().x, 0, b.get_center().y)
	var r0 := maxf(b.size.x, b.size.y) * 0.5
	var hull_m := MeshKit.paint(hull, 0.6, 0.5, 0.6)
	var plate_m := MeshKit.paint(plate, 0.7, 0.4, 0.5)
	var glow := MeshKit.mech_material(light, 0.0, 0.4, light * 2.0, false)
	var gap := _void_band(t) if kind == "boarding" else Vector2.ZERO
	_greebles(t, root, b, hull_m, plate_m, glow, gap)
	if kind == "boarding":
		_docked(root, b, gap, hull_m, plate_m, glow)
	elif kind == "ship":
		_ship(root, c, r0, hull_m, plate_m, glow, light)
	else:
		_station(root, c, r0, hull_m, plate_m, glow)


## Low machinery blocks, pipes and vents on the deck around the board: low near it, taller
## further away. Scenery only (outside the map).
static func _greebles(t: TerrainRenderer, root: Node3D, b: Rect2, hull_m: Material, plate_m: Material, glow: Material, gap: Vector2 = Vector2.ZERO) -> void:
	var boxes: Array = [[], []]
	var lights: Array = []
	var n := WorldQuality.scenery(int((b.size.x + b.size.y) * 6.0))
	for i in range(n):
		var key := "gr"
		var x := b.position.x - 30.0 + WorldRand.f(key, i) * (b.size.x + 60.0)
		var z := b.position.y - 30.0 + WorldRand.f(key, i + 5000) * (b.size.y + 60.0)
		if b.grow(1.5).has_point(Vector2(x, z)) or (gap != Vector2.ZERO and z > gap.x - 2.0 and z < gap.y + 2.0):
			continue
		var dist := maxf(maxf(b.position.x - x, x - b.end.x), maxf(b.position.y - z, z - b.end.y))
		var hgt := 0.3 + WorldRand.f(key, i + 9000) * (0.5 + dist * 0.25)
		var sx := 0.6 + 2.4 * WorldRand.f(key, i + 2000)
		var sz := 0.6 + 2.4 * WorldRand.f(key, i + 3000)
		boxes[i % 2].append(Transform3D(Basis.from_scale(Vector3(sx, hgt, sz)), Vector3(x, hgt * 0.5 - 0.05, z)))
		if WorldRand.f(key, i + 4000) < 0.25:
			lights.append(Transform3D(Basis.from_scale(Vector3(sx * 0.8, 0.04, 0.06)), Vector3(x, hgt + 0.01, z + sz * 0.3)))
	WorldDressing.multi(root, "HullBlocks", MeshKit.chamfer_box(Vector3.ONE, 0.04), boxes[0], hull_m, false)
	WorldDressing.multi(root, "HullBlocks", MeshKit.chamfer_box(Vector3.ONE, 0.04), boxes[1], plate_m, false)
	WorldDressing.multi(root, "HullLights", MeshKit.chamfer_box(Vector3.ONE, 0.0), lights, glow, false)


static func _station(root: Node3D, c: Vector3, r0: float, hull_m: Material, plate_m: Material, glow: Material) -> void:
	# A great habitat ring standing far behind, spokes to a hub, and modules on trusses.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 150.0
	tm.outer_radius = 162.0
	tm.rings = 96
	tm.ring_segments = 12
	ring.mesh = tm
	ring.material_override = plate_m
	ring.position = c + Vector3(0, 30, -260 - r0)
	ring.rotation_degrees = Vector3(80, 0, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var band := MeshInstance3D.new()
	var tb := TorusMesh.new()
	tb.inner_radius = 161.0
	tb.outer_radius = 162.5
	tb.rings = 96
	tb.ring_segments = 6
	band.mesh = tb
	band.material_override = glow
	band.position = ring.position
	band.rotation_degrees = ring.rotation_degrees
	root.add_child(band)
	for k in range(4):
		var spoke := MeshKit.part(root, MeshKit.cylinder(3.0, 300.0, 8), hull_m, ring.position)
		spoke.rotation_degrees = Vector3(80, 0, 45 + k * 90)
	MeshKit.part(root, MeshKit.sphere(22.0, 16), plate_m, ring.position)
	for i in range(10):
		var a := deg_to_rad(-170.0 + i * 36.0 + WorldRand.f("mod", i) * 14.0)
		var dist := r0 + 50.0 + 40.0 * WorldRand.f("modr", i)
		var p := c + Vector3(cos(a) * dist, 0, sin(a) * dist)
		var hgt := 8.0 + 30.0 * WorldRand.f("modh", i)
		var truss := MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.5, hgt, 1.5), 0.1), hull_m, p + Vector3(0, hgt * 0.5, 0))
		truss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mod := MeshKit.part(root, MeshKit.cylinder(4.0 + 3.0 * WorldRand.f("modw", i), 14.0, 16), plate_m, p + Vector3(0, hgt, 0), Vector3(0, 0, 90))
		mod.rotation_degrees.y = rad_to_deg(a)
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.4, 0.4, 12.0), 0.02), glow, p + Vector3(0, hgt + 4.5, 0), Vector3(0, -rad_to_deg(a), 0))


static func _ship(root: Node3D, c: Vector3, r0: float, hull_m: Material, plate_m: Material, glow: Material, light: Color) -> void:
	# The hull keeps going: a long spine with stepped superstructure, then the engines.
	var spine_len := 260.0
	var x0 := c.x - r0 - 60.0
	for k in range(8):
		var len := 22.0 + 10.0 * WorldRand.f("sp", k)
		var hgt := 6.0 + 18.0 * WorldRand.f("sph", k)
		var wid := 16.0 + 18.0 * WorldRand.f("spw", k)
		var x := x0 - k * spine_len / 8.0
		var blk := MeshKit.part(root, MeshKit.chamfer_box(Vector3(len, hgt, wid), 0.4), hull_m if k % 2 else plate_m, Vector3(x, hgt * 0.5 - 2.0, c.z + (WorldRand.f("spz", k) - 0.5) * 20.0))
		blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(len * 0.8, 0.3, 0.3), 0.02), glow, Vector3(x, hgt - 1.6, c.z + wid * 0.5 - 4.0))
	# Engines: big bells with glowing exhaust, past the far end.
	var ex := x0 - spine_len - 30.0
	for s: float in [-1.0, 0.0, 1.0]:
		var p := Vector3(ex, 8.0 + absf(s) * -4.0, c.z + s * 26.0)
		var bell := MeshKit.part(root, MeshKit.cylinder(10.0, 24.0, 20, 14.0), hull_m, p, Vector3(0, 0, 90))
		bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fire := MeshKit.part(root, MeshKit.cylinder(12.5, 0.6, 20), MeshKit.mech_material(Color(0.1, 0.1, 0.1), 0.0, 0.5, Color(0.5, 0.75, 1.0) * 4.0, false), p - Vector3(12.0, 0, 0), Vector3(0, 0, 90))
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fins and the bow beyond the board on the other side.
	var bow := MeshKit.part(root, SmoothKit.loft([{"y": 0.0, "w": 40.0, "d": 14.0, "n": 3.0}, {"y": 60.0, "w": 4.0, "d": 4.0, "n": 2.0}], 12), plate_m, Vector3(c.x + r0 + 40.0, -2.0, c.z), Vector3(0, 0, -90))
	bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = light
	l.light_energy = 0.0
	root.add_child(l)


## Rocks drifting slowly around the field, near and far (low gravity, airless).
static func asteroids(root: Node3D, b: Rect2, color: Color) -> void:
	var c := Vector3(b.get_center().x, 0, b.get_center().y)
	var r0 := maxf(b.size.x, b.size.y) * 0.5
	var spin := Spinner.new()
	spin.name = "Asteroids"
	spin.axis = Vector3.UP
	spin.speed = 0.004
	spin.position = c
	root.add_child(spin)
	var groups: Array = [[], [], []]
	for i in range(WorldQuality.scenery(90)):
		var a := WorldRand.f("ast", i) * TAU
		var dist := r0 + 25.0 + 160.0 * WorldRand.f("astr", i)
		var y := 6.0 + 70.0 * WorldRand.f("asty", i)
		var s := 1.5 + 14.0 * pow(WorldRand.f("asts", i), 2.0)
		var axis := (Vector3(WorldRand.f("ax", i), WorldRand.f("ay", i), WorldRand.f("az", i)) + Vector3(0.01, 0, 0)).normalized()
		var basis := Basis(axis, WorldRand.f("aa", i) * TAU)
		groups[i % 3].append(Transform3D(basis * Basis.from_scale(Vector3(s, s * 0.8, s * 0.9)), Vector3(cos(a) * dist, y, sin(a) * dist)))
	var mat := WorldDressing.foliage_material(0.0, 1.0, 0.0)
	for k in range(3):
		var mmi := WorldDressing.multi(spin, "Asteroids", Flora.rock(color.darkened(0.15 * k), 40 + k), groups[k], mat, false)
		if mmi:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The z range (min, max) of the open space between two docked hulls ("void" cells).
static func _void_band(t: TerrainRenderer) -> Vector2:
	var z0 := INF
	var z1 := -INF
	for c in t.map.cells():
		if t.map.column(c).has_tag("void"):
			var z := t.map.grid.to_world(c).z
			z0 = minf(z0, z)
			z1 = maxf(z1, z)
	if z0 == INF:
		return Vector2.ZERO
	return Vector2(z0 - 0.5, z1 + 0.5)


## Two hulls side by side: deck slabs running out past the board on either side of the gap,
## their armored flanks dropping away into space, a superstructure on the far ship, a few
## more docking tubes and grapples off the board, and running lights along both edges.
static func _docked(root: Node3D, b: Rect2, gap: Vector2, hull_m: Material, plate_m: Material, glow: Material) -> void:
	if gap == Vector2.ZERO:
		return
	var x0 := b.position.x - 160.0
	var x1 := b.end.x + 160.0
	var cx := (x0 + x1) * 0.5
	var depth := 26.0
	for side: float in [-1.0, 1.0]:
		var edge := gap.x if side < 0.0 else gap.y
		var far := edge + side * 180.0
		var zc := (edge + far) * 0.5
		var slab := MeshKit.part(root, MeshKit.chamfer_box(Vector3(x1 - x0, depth, absf(far - edge)), 0.6), hull_m,
			Vector3(cx, -depth * 0.5 - 0.06, zc))
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Deck plating just under the board's surface, so the decks read as one hull.
		var deck := MeshKit.part(root, MeshKit.chamfer_box(Vector3(x1 - x0, 0.1, absf(far - edge)), 0.0), plate_m, Vector3(cx, -0.1, zc))
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Armor belts down the flank facing the gap, and running lights on the edge.
		for k in range(3):
			var belt := MeshKit.part(root, MeshKit.chamfer_box(Vector3(x1 - x0, 1.6, 0.8), 0.1), plate_m, Vector3(cx, -3.0 - k * 6.0, edge + side * 0.2))
			belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(x1 - x0, 0.12, 0.12), 0.0), glow, Vector3(cx, -0.5, edge + side * 0.05))
	# The far ship's superstructure (north, away from the camera) and the near ship's low.
	for k in range(6):
		var x := x0 + 30.0 + k * (x1 - x0 - 60.0) / 5.0
		var hgt := 8.0 + 14.0 * WorldRand.f("bss", k)
		var blk := MeshKit.part(root, MeshKit.chamfer_box(Vector3(18.0, hgt, 14.0), 0.4), plate_m if k % 2 else hull_m,
			Vector3(x, hgt * 0.5, gap.x - 40.0 - 20.0 * WorldRand.f("bsz", k)))
		blk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# More docking tubes off the board, so the ships are clamped all along.
	for k in range(6):
		var x := (b.position.x - 20.0 - 25.0 * k) if k % 2 == 0 else (b.end.x + 20.0 + 25.0 * (k - 1))
		var tube := MeshKit.part(root, MeshKit.cylinder(1.2, gap.y - gap.x + 1.0, 10), hull_m, Vector3(x, -0.6, (gap.x + gap.y) * 0.5), Vector3(90, 0, 0))
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
