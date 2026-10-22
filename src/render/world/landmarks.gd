class_name Landmarks
extends RefCounted
## Big recognizable structures far beyond the board that say what kind of world this is:
## a castle on a hill, a frontier water tower and windmill, atomic-age domes and a monorail,
## pagodas and a shrine gate, white Union towers and a space elevator rising into orbit,
## factory smokestacks, harbor container cranes.
## horizon.landmarks lists them. Scenery only (far outside the map).

const SPOTS := 7


static func build(t: TerrainRenderer, root: Node3D, b: Rect2, height_fn: Callable) -> void:
	var list: Array = WorldStyle.value(t.style, "horizon.landmarks", [])
	if list.is_empty():
		return
	var arch: Dictionary = t.style.get("architecture", {})
	var c := b.get_center()
	var r0 := maxf(b.size.x, b.size.y) * 0.5
	for i in range(list.size()):
		var kind := str(list[i])
		# Spread them around the far side of the board (the camera usually looks north).
		var a := deg_to_rad(-90.0 + (i - (list.size() - 1) * 0.5) * 38.0 + (WorldRand.f(kind, i) - 0.5) * 14.0)
		var dist := r0 + 38.0 + 30.0 * WorldRand.f(kind, i + 10)
		if kind in ["space_elevator", "monorail", "white_towers", "saucer_tower"]:
			dist = r0 + 100.0 + 40.0 * WorldRand.f(kind, i + 20)
		var p := Vector2(c.x + cos(a) * dist, c.y + sin(a) * dist)
		var y: float = height_fn.call(p.x, p.y)
		var node := Node3D.new()
		node.name = "Landmark_" + kind
		node.position = Vector3(p.x, y - 0.3, p.y)
		node.rotation.y = -a + PI * 0.5
		root.add_child(node)
		match kind:
			"castle":
				_castle(node, arch)
			"water_tower":
				_water_tower(node)
			"windmill":
				_windmill(node)
			"headframe":
				_headframe(node)
			"domes":
				_domes(node, arch)
			"saucer_tower":
				_saucer_tower(node, arch)
			"monorail":
				node.position = Vector3(c.x, 0, c.y)
				node.rotation.y = 0
				_monorail(node, r0 + 26.0, height_fn, Vector2(c.x, c.y), arch)
			"pagoda":
				_pagoda(node, arch, 5)
			"torii":
				_torii(node)
			"white_towers":
				_white_towers(node, arch)
			"space_elevator":
				_space_elevator(node)
			"rig":
				_rig(node)
			"smokestacks":
				_smokestacks(node, arch)
			"cranes":
				_cranes(node, arch)


static func _mat(color: Color, metal: float = 0.1, rough: float = 0.8, emit: Color = Color.BLACK) -> Material:
	return MeshKit.mech_material(color, metal, rough, emit, false)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return MeshKit.part(parent, MeshKit.chamfer_box(size, minf(0.15, size.x * 0.05)), mat, pos, rot)


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, top_r: float = -1.0, sides: int = 14) -> MeshInstance3D:
	return MeshKit.part(parent, MeshKit.cylinder(r, h, sides, top_r), mat, pos + Vector3.UP * h * 0.5)


## Crenellated wall top along the x axis, centered at `pos`.
static func _crenels(parent: Node3D, length: float, pos: Vector3, mat: Material, rot_y: float = 0.0) -> void:
	var n := int(length / 1.2)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = rot_y
	parent.add_child(holder)
	for k in range(n):
		if k % 2 == 0:
			_box(holder, Vector3(0.6, 0.8, 1.2), Vector3(-length * 0.5 + (k + 0.5) * length / n, 0.4, 0), mat)


static func _castle(n: Node3D, arch: Dictionary) -> void:
	var stone := _mat(WorldStyle.color(arch.get("landmark_stone", "#8a8478")), 0.0, 0.95)
	var roof := _mat(WorldStyle.color(arch.get("roof", "#4a3a5a")), 0.1, 0.7)
	var banner := _mat(WorldStyle.color(arch.get("banner", "#a02a2a")), 0.0, 0.8)
	# A mound to sit on.
	MeshKit.part(n, SmoothKit.blob(Vector3(36, 8, 30), 0.9, 0.8, 0.0, 18), _mat(Color(0.3, 0.38, 0.2), 0.0, 1.0), Vector3(0, -1.0, 0))
	var base := Vector3(0, 2.5, 0)
	# Curtain walls and corner towers.
	var w := 16.0
	for k in range(4):
		var holder := Node3D.new()
		holder.rotation_degrees.y = k * 90.0
		holder.position = base
		n.add_child(holder)
		_box(holder, Vector3(w, 6.0, 1.4), Vector3(0, 3.0, w * 0.5), stone)
		_crenels(holder, w, Vector3(0, 6.0, w * 0.5), stone)
		_cyl(holder, 1.8, 9.0, Vector3(w * 0.5, 0, w * 0.5), stone)
		_cyl(holder, 2.1, 3.2, Vector3(w * 0.5, 9.0, w * 0.5), roof, 0.0)
	# Keep with a tall roof, banners.
	_box(n, Vector3(7, 13, 7), base + Vector3(0, 6.5, 0), stone)
	_crenels(n, 7.0, base + Vector3(0, 13.0, 3.3), stone)
	_crenels(n, 7.0, base + Vector3(0, 13.0, -3.3), stone)
	_cyl(n, 2.0, 7.0, base + Vector3(-2.0, 13.0, -1.5), stone)
	_cyl(n, 2.4, 4.0, base + Vector3(-2.0, 20.0, -1.5), roof, 0.0)
	_cyl(n, 0.08, 4.0, base + Vector3(-2.0, 24.0, -1.5), _mat(Color(0.2, 0.2, 0.2)))
	_box(n, Vector3(2.2, 1.2, 0.05), base + Vector3(-0.9, 27.2, -1.5), banner)
	# The gate.
	_box(n, Vector3(3.0, 4.0, 0.3), base + Vector3(0, 2.0, w * 0.5 + 0.6), _mat(Color(0.12, 0.08, 0.05)))


static func _water_tower(n: Node3D) -> void:
	var wood := _mat(Color(0.42, 0.3, 0.2), 0.0, 0.9)
	var metal := _mat(Color(0.45, 0.42, 0.38), 0.5, 0.6)
	for k in range(4):
		var a := k * PI * 0.5 + PI * 0.25
		var leg := Vector3(cos(a), 0, sin(a)) * 2.2
		MeshKit.part(n, MeshKit.cylinder(0.18, 9.0, 6), wood, leg * 0.85 + Vector3.UP * 4.5, Vector3(rad_to_deg(sin(a)) * 0.15, 0, -rad_to_deg(cos(a)) * 0.15))
	_cyl(n, 2.6, 4.0, Vector3(0, 9.0, 0), wood)
	_cyl(n, 2.9, 1.6, Vector3(0, 13.0, 0), metal, 0.2)
	for y in [9.5, 11.0, 12.5]:
		_cyl(n, 2.66, 0.12, Vector3(0, y, 0), metal)


static func _windmill(n: Node3D) -> void:
	var metal := _mat(Color(0.5, 0.5, 0.5), 0.6, 0.5)
	MeshKit.part(n, MeshKit.cylinder(0.9, 14.0, 4, 0.2), metal, Vector3(0, 7.0, 0))
	var hub := Spinner.new()
	hub.position = Vector3(0, 14.0, 0.5)
	hub.axis = Vector3.BACK
	hub.speed = 0.8
	n.add_child(hub)
	for k in range(14):
		var blade := Node3D.new()
		blade.rotation.z = TAU * k / 14.0
		hub.add_child(blade)
		_box(blade, Vector3(0.5, 3.0, 0.05), Vector3(0, 1.9, 0), metal, Vector3(0, 20, 0))
	_box(n, Vector3(0.05, 1.4, 2.4), Vector3(0, 14.0, -1.6), metal)


static func _headframe(n: Node3D) -> void:
	var wood := _mat(Color(0.35, 0.26, 0.18), 0.0, 0.9)
	for s: float in [-1.0, 1.0]:
		_box(n, Vector3(0.5, 16.0, 0.5), Vector3(s * 3.0, 7.5, 0), wood, Vector3(0, 0, s * 10.0))
		_box(n, Vector3(0.4, 15.0, 0.4), Vector3(s * 2.0, 7.0, -4.0), wood, Vector3(-28, 0, s * 6.0))
	for y in [4.0, 8.0, 12.0]:
		_box(n, Vector3(6.5 - y * 0.2, 0.35, 0.35), Vector3(0, y, 0), wood)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.4
	tm.outer_radius = 1.7
	wheel.mesh = tm
	wheel.material_override = _mat(Color(0.3, 0.3, 0.3), 0.7, 0.4)
	wheel.position = Vector3(0, 15.5, 0)
	wheel.rotation_degrees = Vector3(90, 0, 0)
	n.add_child(wheel)
	_box(n, Vector3(8, 4, 6), Vector3(5, 2, 4), _mat(Color(0.4, 0.3, 0.22), 0.0, 0.9))


static func _domes(n: Node3D, arch: Dictionary) -> void:
	var white := _mat(WorldStyle.color(arch.get("landmark_color", "#e8e4d8")), 0.3, 0.3)
	var chrome := _mat(Color(0.85, 0.87, 0.9), 0.95, 0.15)
	var glow := _mat(Color(0.1, 0.1, 0.1), 0.0, 0.5, WorldStyle.color(arch.get("accent", "#40e0d0")) * 2.0)
	var spots := [[0.0, 0.0, 12.0], [16.0, 6.0, 7.0], [-14.0, 5.0, 8.0], [6.0, -14.0, 5.0]]
	for s: Array in spots:
		var r: float = s[2]
		var p := Vector3(s[0], 0, s[1])
		MeshKit.part(n, SmoothKit.blob(Vector3(r * 2.0, r * 1.6, r * 2.0), 1.0, 1.0, 0.0, 24), white, p)
		_cyl(n, r * 1.02, r * 0.08, p, chrome)
		_cyl(n, r * 0.86, r * 0.04, p + Vector3.UP * r * 0.42, glow)
	_cyl(n, 0.8, 28.0, Vector3.ZERO, chrome, 0.3)


static func _saucer_tower(n: Node3D, arch: Dictionary) -> void:
	var white := _mat(WorldStyle.color(arch.get("landmark_color", "#e8e4d8")), 0.3, 0.3)
	var chrome := _mat(Color(0.85, 0.87, 0.9), 0.95, 0.15)
	var glow := _mat(Color(0.1, 0.1, 0.1), 0.0, 0.5, WorldStyle.color(arch.get("accent", "#40e0d0")) * 2.5)
	for k in range(3):
		var a := TAU * k / 3.0
		MeshKit.part(n, MeshKit.cylinder(0.5, 34.0, 8, 0.25), white, Vector3(cos(a), 0, sin(a)) * 2.2 + Vector3.UP * 17.0, Vector3(rad_to_deg(sin(a)) * 3.0, 0, -rad_to_deg(cos(a)) * 3.0))
	MeshKit.part(n, SmoothKit.blob(Vector3(14, 3.0, 14), 0.5, 1.0, 1.0, 24), chrome, Vector3(0, 34.0, 0))
	_cyl(n, 6.6, 0.4, Vector3(0, 33.8, 0), glow)
	_cyl(n, 0.12, 8.0, Vector3(0, 35.0, 0), chrome, 0.02)


## A ring of elevated track around the board with a train running on it.
static func _monorail(n: Node3D, radius: float, height_fn: Callable, center: Vector2, arch: Dictionary) -> void:
	var white := _mat(WorldStyle.color(arch.get("landmark_color", "#e8e4d8")), 0.3, 0.35)
	var chrome := _mat(Color(0.85, 0.87, 0.9), 0.9, 0.2)
	var h := 9.0
	var seg := 64
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(seg):
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius + Vector3.UP * h
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius + Vector3.UP * h
		var out0 := Vector3(cos(a0), 0, sin(a0))
		var out1 := Vector3(cos(a1), 0, sin(a1))
		MeshKit.add_quad(st, p0 - out0 * 0.5, p1 - out1 * 0.5, p1 + out1 * 0.5, p0 + out0 * 0.5, Vector3.UP)
		MeshKit.add_quad(st, p0 + out0 * 0.5, p1 + out1 * 0.5, p1 + out1 * 0.5 - Vector3.UP * 0.8, p0 + out0 * 0.5 - Vector3.UP * 0.8, out0)
		MeshKit.add_quad(st, p0 - out0 * 0.5, p1 - out1 * 0.5, p1 - out1 * 0.5 - Vector3.UP * 0.8, p0 - out0 * 0.5 - Vector3.UP * 0.8, -out0)
		if k % 4 == 0:
			var ground: float = height_fn.call(center.x + p0.x, center.y + p0.z)
			var pillar := MeshKit.part(n, MeshKit.cylinder(0.35, h - ground + 0.5, 8, 0.25), white, Vector3(p0.x, ground + (h - ground) * 0.5 - 0.4, p0.z))
			pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var track := MeshInstance3D.new()
	track.mesh = st.commit()
	track.material_override = white
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(track)
	var spinner := Spinner.new()
	spinner.axis = Vector3.UP
	spinner.speed = 0.05
	n.add_child(spinner)
	for car in range(4):
		var a := -car * 0.03
		var p := Vector3(cos(a), 0, sin(a)) * radius + Vector3.UP * (h + 0.7)
		var body := MeshKit.part(spinner, SmoothKit.rounded_box(Vector3(1.2, 1.1, 3.4), 0.5), chrome, p)
		body.rotation.y = -a
		var stripe := MeshKit.part(body, MeshKit.chamfer_box(Vector3(1.25, 0.15, 3.0), 0.02), _mat(Color(0.1, 0.1, 0.1), 0.0, 0.5, WorldStyle.color(arch.get("accent", "#ff6a3a")) * 2.0), Vector3(0, 0.1, 0))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _pagoda(n: Node3D, arch: Dictionary, tiers: int) -> void:
	var wall := _mat(WorldStyle.color(arch.get("landmark_color", "#8a2a1e")), 0.0, 0.8)
	var roof := _mat(WorldStyle.color(arch.get("roof", "#2a3438")), 0.3, 0.5)
	var gold := _mat(Color(0.8, 0.62, 0.25), 0.9, 0.3)
	_box(n, Vector3(12, 1.5, 12), Vector3(0, 0.75, 0), _mat(Color(0.55, 0.52, 0.48), 0.0, 0.9))
	var y := 1.5
	for k in range(tiers):
		var w := 7.5 - k * 1.0
		var hgt := 3.6 - k * 0.25
		_box(n, Vector3(w, hgt, w), Vector3(0, y + hgt * 0.5, 0), wall)
		# Sweeping eave: a wide shallow cone with upturned rim.
		MeshKit.part(n, SmoothKit.lathe([Vector2(w * 0.95, 0.0), Vector2(w * 0.85, 0.15), Vector2(w * 0.6, 0.55), Vector2(w * 0.3, 0.9), Vector2(0.01, 1.05)], 4, true), roof,
			Vector3(0, y + hgt, 0), Vector3(0, 45, 0))
		y += hgt + 0.8
	_cyl(n, 0.2, 6.0, Vector3(0, y, 0), gold, 0.05)
	for k in range(5):
		_cyl(n, 0.5 - k * 0.07, 0.12, Vector3(0, y + 1.0 + k * 0.8, 0), gold)


static func _torii(n: Node3D) -> void:
	var red := _mat(Color(0.72, 0.12, 0.08), 0.0, 0.6)
	var black := _mat(Color(0.08, 0.07, 0.07), 0.0, 0.6)
	for s: float in [-1.0, 1.0]:
		_cyl(n, 0.55, 12.0, Vector3(s * 4.5, 0, 0), red, 0.45)
	_box(n, Vector3(13.0, 0.9, 1.0), Vector3(0, 12.3, 0), black)
	_box(n, Vector3(12.0, 0.7, 0.8), Vector3(0, 11.3, 0), red)
	_box(n, Vector3(11.0, 0.6, 0.7), Vector3(0, 9.3, 0), red)
	_box(n, Vector3(0.6, 2.0, 0.6), Vector3(0, 10.3, 0), red)


static func _white_towers(n: Node3D, arch: Dictionary) -> void:
	var white := _mat(WorldStyle.color(arch.get("landmark_color", "#f2f4f6")), 0.2, 0.25)
	var glass := _mat(Color(0.25, 0.4, 0.5), 0.8, 0.08)
	var glow := _mat(Color(0.1, 0.1, 0.1), 0.0, 0.5, WorldStyle.color(arch.get("accent", "#7ad8ff")) * 2.0)
	var spots := [[0.0, 0.0, 70.0, 5.0], [12.0, 5.0, 48.0, 4.0], [-11.0, 4.0, 55.0, 4.5], [5.0, -10.0, 38.0, 3.5]]
	for s: Array in spots:
		var p := Vector3(s[0], 0, s[1])
		var h: float = s[2]
		var r: float = s[3]
		MeshKit.part(n, SmoothKit.loft([{"y": 0.0, "w": r * 2.4, "d": r * 2.0, "n": 2.5}, {"y": h * 0.55, "w": r * 1.9, "d": r * 1.7, "n": 2.5},
			{"y": h * 0.92, "w": r * 1.2, "d": r * 1.1, "n": 2.5}, {"y": h, "w": r * 0.2, "d": r * 0.2, "n": 2.0}], 20), white, p)
		MeshKit.part(n, SmoothKit.loft([{"y": 0.0, "w": r * 2.45, "d": r * 0.6, "n": 2.0}, {"y": h * 0.85, "w": r * 1.4, "d": r * 0.4, "n": 2.0}], 12), glass, p + Vector3(0, h * 0.05, 0))
		for k in range(4):
			_cyl(n, r * (1.15 - k * 0.12), 0.25, p + Vector3.UP * h * (0.3 + 0.15 * k), glow)


## An offshore platform on legs with a derrick tower, cranes and a gas flare.
static func _rig(n: Node3D) -> void:
	var steel := _mat(Color(0.45, 0.47, 0.5), 0.7, 0.45)
	var red := _mat(Color(0.7, 0.2, 0.12), 0.3, 0.6)
	var yellow := _mat(Color(0.85, 0.65, 0.15), 0.3, 0.6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(n, 1.0, 14.0, Vector3(sx * 7.0, -6.0, sz * 6.0), steel)
	_box(n, Vector3(20, 2.0, 17), Vector3(0, 9.0, 0), steel)
	_box(n, Vector3(10, 4.0, 8), Vector3(-4, 12.0, -3), red)
	for k in range(6):
		var y := 10.0 + k * 3.0
		var wdt := 4.0 - k * 0.5
		for s2: float in [-1.0, 1.0]:
			_box(n, Vector3(0.3, 3.2, 0.3), Vector3(5 + s2 * wdt * 0.5, y + 1.6, 3 + s2 * wdt * 0.5), steel, Vector3(0, 0, s2 * 6))
	_cyl(n, 0.25, 4.0, Vector3(5, 28, 3), steel, 0.05)
	_box(n, Vector3(14, 0.6, 0.6), Vector3(-2, 15, 6), yellow, Vector3(0, 30, 18))
	var flare := Node3D.new()
	flare.position = Vector3(10, 18, -8)
	n.add_child(flare)
	_box(flare, Vector3(0.4, 10, 0.4), Vector3(0, -5, 0), steel, Vector3(0, 0, -30))
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 1.2
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 5.0
	fire.scale_amount_min = 3.0
	fire.scale_amount_max = 5.0
	fire.position = Vector3(2.5, 4, 0)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.4)
	q.material = WorldHazards._quad_material(Color(1.6, 1.2, 0.9), true)
	fire.mesh = q
	fire.color_ramp = WorldHazards._ramp([[0.0, Color(1, 0.9, 0.5, 0.0)], [0.2, Color(1, 0.6, 0.2, 0.9)], [1.0, Color(0.6, 0.15, 0.0, 0.0)]])
	flare.add_child(fire)


## A tether climbing out of sight from a far base, with a station ring partway up and a
## climber pod moving along it.
static func _space_elevator(n: Node3D) -> void:
	var white := _mat(Color(0.92, 0.93, 0.95), 0.3, 0.3)
	var glow := _mat(Color(0.1, 0.1, 0.1), 0.0, 0.5, Color(0.5, 0.85, 1.0) * 3.0)
	MeshKit.part(n, SmoothKit.loft([{"y": 0.0, "w": 22.0, "d": 22.0, "n": 2.2}, {"y": 10.0, "w": 12.0, "d": 12.0, "n": 2.2}, {"y": 14.0, "w": 5.0, "d": 5.0, "n": 2.0}], 24), white)
	var tether := MeshKit.part(n, MeshKit.cylinder(0.6, 900.0, 8), glow, Vector3(0, 450.0, 0))
	tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.0
	tm.outer_radius = 11.0
	tm.rings = 32
	ring.mesh = tm
	ring.material_override = white
	ring.position = Vector3(0, 160.0, 0)
	n.add_child(ring)
	var climber := Spinner.new()
	climber.mode = "climb"
	climber.speed = 6.0
	climber.climb_range = Vector2(16.0, 300.0)
	n.add_child(climber)
	MeshKit.part(climber, SmoothKit.rounded_box(Vector3(3.0, 5.0, 3.0), 1.0), white)
	MeshKit.part(climber, MeshKit.cylinder(1.6, 0.3, 12), glow, Vector3(0, -2.6, 0))


## A factory hall with three tall brick chimneys, smoke leaning with the wind.
static func _smokestacks(n: Node3D, arch: Dictionary) -> void:
	var brick := _mat(WorldStyle.color(arch.get("landmark_color", "#8a5a44")), 0.0, 0.95)
	var metal := _mat(Color(0.36, 0.36, 0.38), 0.6, 0.5)
	_box(n, Vector3(26, 9, 12), Vector3(0, 4.5, 0), metal)
	_box(n, Vector3(26.4, 0.6, 12.4), Vector3(0, 9.2, 0), _mat(Color(0.28, 0.28, 0.3), 0.4, 0.6))
	for i in range(3):
		var x := -8.0 + i * 8.0
		var hgt := 30.0 + 6.0 * WorldRand.f("stack", i)
		_cyl(n, 1.7, hgt, Vector3(x, 0, -2.0), brick, 1.15, 12)
		_cyl(n, 1.3, 0.8, Vector3(x, hgt - 0.4, -2.0), metal, 1.3, 12)
		var smoke := CPUParticles3D.new()
		smoke.name = "StackSmoke"
		smoke.amount = WorldQuality.particles(36)
		smoke.lifetime = 14.0
		smoke.preprocess = 14.0
		smoke.direction = Vector3(0.3, 1, 0.1)
		smoke.spread = 8.0
		smoke.gravity = Vector3(0.5, 0.25, 0.1)
		smoke.initial_velocity_min = 1.2
		smoke.initial_velocity_max = 2.0
		smoke.scale_amount_min = 1.0
		smoke.scale_amount_max = 2.4
		smoke.position = Vector3(x, hgt + 0.5, -2.0)
		var q := QuadMesh.new()
		q.size = Vector2(3.0, 3.0)
		q.material = WorldHazards._quad_material(Color(1, 1, 1), false)
		smoke.mesh = q
		smoke.color_ramp = WorldHazards._ramp([[0.0, Color(0.55, 0.52, 0.5, 0.0)], [0.1, Color(0.6, 0.58, 0.55, 0.5)], [1.0, Color(0.7, 0.68, 0.66, 0.0)]])
		smoke.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 120, 120))
		n.add_child(smoke)


## Two harbor container cranes: four legs, a cross girder, and a long boom out over the water.
static func _cranes(n: Node3D, arch: Dictionary) -> void:
	var paint := _mat(WorldStyle.color(arch.get("landmark_color", "#e8a020")), 0.4, 0.5)
	var dark := _mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	for k in range(2):
		var c := Node3D.new()
		c.position = Vector3(-10.0 + k * 20.0, 0, 0)
		n.add_child(c)
		for x: float in [-4.0, 4.0]:
			for z: float in [-5.0, 5.0]:
				_box(c, Vector3(0.8, 22.0, 0.8), Vector3(x, 11.0, z), paint)
			_box(c, Vector3(0.6, 0.6, 10.8), Vector3(x, 6.0, 0), paint)
		_box(c, Vector3(9.0, 1.4, 1.2), Vector3(0, 22.0, -5.0), paint)
		_box(c, Vector3(9.0, 1.4, 1.2), Vector3(0, 22.0, 5.0), paint)
		# Boom over the water (+Z) and back stay with the machinery house.
		_box(c, Vector3(2.0, 1.6, 44.0), Vector3(0, 23.5, 10.0), paint)
		_box(c, Vector3(4.0, 3.0, 5.0), Vector3(0, 25.5, -6.0), dark)
		_box(c, Vector3(0.3, 12.0, 0.3), Vector3(0, 29.0, -3.0), paint, Vector3(-20, 0, 0))
		_box(c, Vector3(1.6, 1.0, 2.4), Vector3(0, 22.4, 18.0 + 6.0 * WorldRand.f("crane", k)), dark)
