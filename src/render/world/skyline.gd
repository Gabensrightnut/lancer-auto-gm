class_name Skyline
extends RefCounted
## The city around the board: street blocks of buildings right outside the map edge that
## rise into towers further out, built with the same facades as the board's buildings so
## the battle sits inside a whole city. Low next to the board so it never hides the fight.
## architecture.skyline: {"near": [min, max] height next to the board, "far": [min, max]
## towers out at the horizon, "density": 0..1, "towers": count of landmark megatowers}.


static func build(t: TerrainRenderer, root: Node3D, b: Rect2) -> void:
	var arch: Dictionary = t.style.get("architecture", {"materials": ["concrete", "glass", "brick"]})
	var sky: Dictionary = arch.get("skyline", {})
	var near: Array = sky.get("near", [1.0, 4.0])
	var far: Array = sky.get("far", [8.0, 45.0])
	var density := float(sky.get("density", 0.75))
	var mats: Array = arch.get("materials", ["concrete"])
	var walls: Array = arch.get("walls", ["#8a8072"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	# A street grid aligned to the board: blocks of `block` units with `street`-wide roads.
	var block := 5.0
	var street := 1.6
	var reach := 120.0
	var x0 := b.position.x - reach
	var z0 := b.position.y - reach
	var nx := int((b.size.x + 2.0 * reach) / (block + street))
	var nz := int((b.size.y + 2.0 * reach) / (block + street))
	var count := 0
	var roofs: Array = []
	for j in range(nz):
		for i in range(nx):
			var bx := x0 + i * (block + street)
			var bz := z0 + j * (block + street)
			var rect := Rect2(bx, bz, block, block)
			if rect.intersects(b.grow(1.2)):
				continue
			var d := _dist(rect.get_center(), b)
			if d > reach:
				continue
			# Split the block into 1-4 lots.
			var key := "sk%d_%d" % [i, j]
			var lots := _lots(rect, key)
			for k in range(lots.size()):
				var lot: Rect2 = lots[k]
				if WorldRand.f(key, 50 + k) > density:
					continue
				var dd := _dist(lot.get_center(), b)
				var tnear := clampf((dd - 5.0) / 40.0, 0.0, 1.0)
				var lo := lerpf(float(near[0]), float(far[0]), tnear)
				var hi := lerpf(float(near[1]), float(far[1]), pow(tnear, 0.7))
				var h := roundf(lerpf(lo, hi, pow(WorldRand.f(key, 60 + k), 1.6)) * 3.0) / 3.0
				if lot.get_center().y > b.end.y and dd < 40.0:
					h = minf(h, float(near[1]))  # the camera's side: nothing tall in the way
				var type: int = CityBuilder.TYPES.get(str(mats[int(WorldRand.f(key, 70 + k) * mats.size()) % mats.size()]), 0)
				if h > 15.0 and WorldRand.f(key, 75 + k) < 0.5:
					type = CityBuilder.TYPES["glass"]
				var col := WorldStyle.color(walls[int(WorldRand.f(key, 80 + k) * walls.size()) % walls.size()])
				col.a = WorldRand.f(key, 90 + k)
				var inset := 0.08 + 0.15 * WorldRand.f(key, 95 + k)
				var r := lot.grow(-inset)
				var plain := _tower(st, r, h, col, type, key, k, roofs)
				if h > 4.0:
					roofs.append([Vector3(r.get_center().x, h, r.get_center().y), minf(r.size.x, r.size.y), dd])
				# Setback crown on tall buildings.
				if plain and h > 8.0 and WorldRand.f(key, 100 + k) < 0.6:
					var r2 := r.grow(-minf(r.size.x, r.size.y) * 0.18)
					_box(st, r2, h, h + h * (0.12 + 0.2 * WorldRand.f(key, 110 + k)), col, type)
				count += 1
	if count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Skyline"
	mi.mesh = st.commit()
	var look: Dictionary = arch.duplicate()
	look.merge(sky.get("look", {}), true)
	look["backdrop"] = 1.0
	mi.material_override = CityBuilder.make_material(look)
	# No shadows: long evening shadows from the skyline would darken the board.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_spires(root, roofs)
	_ground_traffic(root, b, x0, z0, nx, nz, block, street, arch)
	var fires := WorldQuality.lights(int(sky.get("fires", 0)))
	if fires > 0:
		_fires(root, roofs, fires, WorldStyle.color(arch.get("fire", "#ff6a1a")))
	if bool(WorldStyle.value(t.style, "horizon.traffic", false)):
		var traffic := SkyTraffic.new()
		traffic.name = "SkyTraffic"
		traffic.setup(b, arch.get("neon_colors", ["#ff2aa8", "#20e8ff"]))
		root.add_child(traffic)


## Burning towers on the skyline: a glow at the roof and a tall column of smoke leaning
## with the wind. Off the board, so they're scenery only.
static func _fires(root: Node3D, roofs: Array, n: int, fire: Color) -> void:
	roofs.sort_custom(func(a: Array, b: Array) -> bool: return WorldRand.f("fr" + str(a[0])) < WorldRand.f("fr" + str(b[0])))
	var picked := 0
	for r: Array in roofs:
		if picked >= n:
			break
		if float(r[2]) < 8.0:
			continue
		picked += 1
		var at: Vector3 = r[0]
		var size: float = r[1]
		var smoke := CPUParticles3D.new()
		smoke.name = "SkylineSmoke"
		smoke.amount = 70
		smoke.lifetime = 16.0
		smoke.preprocess = 16.0
		smoke.direction = Vector3(0.25, 1, 0.1)
		smoke.spread = 10.0
		smoke.gravity = Vector3(0.6, 0.3, 0.15)
		smoke.initial_velocity_min = 1.5
		smoke.initial_velocity_max = 2.5
		smoke.scale_amount_min = 0.8
		smoke.scale_amount_max = 2.0
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		smoke.emission_box_extents = Vector3(size * 0.3, 0.2, size * 0.3)
		smoke.position = at
		var q := QuadMesh.new()
		q.size = Vector2(size * 1.4, size * 1.4)
		q.material = WorldHazards._quad_material(Color(1, 1, 1), false)
		smoke.mesh = q
		smoke.color_ramp = WorldHazards._ramp([[0.0, Color(fire.r, fire.g * 0.6, 0.1, 0.0)], [0.06, Color(fire.r * 0.8, fire.g * 0.4, 0.05, 0.6)], [0.2, Color(0.12, 0.1, 0.09, 0.55)], [1.0, Color(0.2, 0.18, 0.17, 0.0)]])
		smoke.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 160, 160))
		root.add_child(smoke)
		var flames := CPUParticles3D.new()
		flames.name = "SkylineFire"
		flames.amount = 40
		flames.lifetime = 1.2
		flames.preprocess = 1.2
		flames.direction = Vector3.UP
		flames.spread = 15.0
		flames.gravity = Vector3(0, 1.0, 0)
		flames.initial_velocity_min = 0.5
		flames.initial_velocity_max = 1.2
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.emission_box_extents = Vector3(size * 0.35, 0.1, size * 0.35)
		flames.position = at
		var fq := QuadMesh.new()
		fq.size = Vector2(size * 0.5, size * 0.7)
		fq.material = WorldHazards._quad_material(Color(1.5, 1.2, 1.0), true)
		flames.mesh = fq
		flames.color_ramp = WorldHazards._ramp([[0.0, Color(1, 0.8, 0.4, 0.0)], [0.2, Color(1, 0.6, 0.2, 0.8)], [1.0, Color(fire.r, fire.g * 0.3, 0, 0)]])
		root.add_child(flames)
		var light := FlickerLight.new()
		light.light_color = fire
		light.base_energy = 4.0
		light.omni_range = size * 4.0
		light.position = at + Vector3.UP * 0.6
		root.add_child(light)


static func _dist(p: Vector2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - p.x, p.x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - p.y, p.y - b.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


static func _lots(r: Rect2, key: String) -> Array:
	var u := WorldRand.f(key, 1)
	if u < 0.3:
		return [r]
	var sx := lerpf(0.35, 0.65, WorldRand.f(key, 2))
	var sz := lerpf(0.35, 0.65, WorldRand.f(key, 3))
	if u < 0.6:
		return [Rect2(r.position, Vector2(r.size.x * sx, r.size.y)), Rect2(r.position + Vector2(r.size.x * sx, 0), Vector2(r.size.x * (1.0 - sx), r.size.y))]
	return [Rect2(r.position, Vector2(r.size.x * sx, r.size.y * sz)), Rect2(r.position + Vector2(r.size.x * sx, 0), Vector2(r.size.x * (1.0 - sx), r.size.y * sz)),
		Rect2(r.position + Vector2(0, r.size.y * sz), Vector2(r.size.x * sx, r.size.y * (1.0 - sz))),
		Rect2(r.position + Vector2(r.size.x * sx, r.size.y * sz), Vector2(r.size.x * (1.0 - sx), r.size.y * (1.0 - sz)))]


## A skyline building of varied shape: a plain block, stepped tiers, an eight-sided tower,
## twin towers with a sky bridge, or a slab with a split crown; tall ones may get a spire.
static func _tower(st: SurfaceTool, r: Rect2, h: float, col: Color, type: int, key: String, k: int, roofs: Array) -> bool:
	var shape := WorldRand.f(key, 200 + k)
	if h < 6.0 or shape < 0.35:
		_box(st, r, 0.0, h, col, type)
		return true
	elif shape < 0.55:
		var rr := r
		var y := 0.0
		for i in range(3):
			var top := h * (0.55 + 0.45 * (i + 1) / 3.0) if i < 2 else h
			_box(st, rr, y, top, col, type)
			y = top
			rr = rr.grow(-minf(rr.size.x, rr.size.y) * 0.15)
	elif shape < 0.75:
		_prism(st, r, h, col, type, 8)
	elif shape < 0.88:
		var half := r.size.x * 0.4
		_box(st, Rect2(r.position, Vector2(half, r.size.y)), 0.0, h, col, type)
		_box(st, Rect2(r.position + Vector2(r.size.x - half, 0), Vector2(half, r.size.y)), 0.0, h * 0.85, col, type)
		_box(st, Rect2(r.position + Vector2(half, r.size.y * 0.35), Vector2(r.size.x - 2 * half, r.size.y * 0.3)), h * 0.55, h * 0.6, col, type)
	else:
		_box(st, r, 0.0, h * 0.85, col, type)
		var crown := r.grow(-minf(r.size.x, r.size.y) * 0.1)
		_box(st, Rect2(crown.position, Vector2(crown.size.x * 0.5, crown.size.y)), h * 0.85, h, col, type)
		_box(st, Rect2(crown.position + Vector2(crown.size.x * 0.5, 0), Vector2(crown.size.x * 0.5, crown.size.y)), h * 0.85, h * 0.93, col, type)
	if h > 18.0 and WorldRand.f(key, 220 + k) < 0.4:
		roofs.append([Vector3(r.get_center().x, h, r.get_center().y), -1.0, 0.0])  # spire
	return false


## An n-sided tower inscribed in the rectangle.
static func _prism(st: SurfaceTool, r: Rect2, h: float, col: Color, type: int, n: int) -> void:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var rad := minf(r.size.x, r.size.y) * 0.5
	var pts: Array[Vector3] = []
	for i in range(n):
		var a := TAU * (i + 0.5) / n
		pts.append(c + Vector3(cos(a), 0, sin(a)) * rad)
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		CityBuilder._wall(st, a, b, -0.6, h, ((a + b) * 0.5 - c).normalized(), col, Color(a.distance_to(b), h, 0.0, type))
	for i in range(n):
		st.set_color(col)
		st.set_custom(0, Color(1.0, h, 0.0, type))
		MeshKit.add_tri(st, c + Vector3.UP * h, pts[i] + Vector3.UP * h, pts[(i + 1) % n] + Vector3.UP * h, Vector3.UP)


## A box building on a rectangle from y0 to y1: four facades and a roof.
static func _box(st: SurfaceTool, r: Rect2, y0: float, y1: float, col: Color, type: int) -> void:
	var c := [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
	var center := Vector3(r.get_center().x, 0, r.get_center().y)
	for i in range(4):
		var a: Vector3 = c[i]
		var bb: Vector3 = c[(i + 1) % 4]
		var out := ((a + bb) * 0.5 - center).normalized()
		CityBuilder._wall(st, a, bb, y0 - (0.6 if y0 <= 0.0 else 0.0), y1, out, col, Color(a.distance_to(bb), y1, 0.0, type))
	CityBuilder._cap(st, c[0], c[1], c[2], c[3], y1, col, Color(1.0, y1, 0.0, type))


## Thin spires with a red aircraft light on some of the tallest towers.
static func _spires(root: Node3D, roofs: Array) -> void:
	var mat := MeshKit.mech_material(Color(0.6, 0.62, 0.65), 0.8, 0.3, Color.BLACK, false)
	var red := MeshKit.fx_material(Color(1.0, 0.15, 0.1), 3.0)
	var n := 0
	for r: Array in roofs:
		if float(r[1]) >= 0.0 or n >= 14:
			continue
		n += 1
		var at: Vector3 = r[0]
		var hgt := 4.0 + 6.0 * WorldRand.f("spire", n)
		var sp := MeshKit.part(root, MeshKit.cylinder(0.25, hgt, 6, 0.04), mat, at + Vector3.UP * hgt * 0.5)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lamp := MeshKit.part(root, MeshKit.sphere(0.35, 6), red, at + Vector3.UP * hgt)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Cars driving the city's streets beyond the board (the gaps between the skyline's blocks).
static func _ground_traffic(root: Node3D, b: Rect2, x0: float, z0: float, nx: int, nz: int, block: float, street: float, arch: Dictionary) -> void:
	var kinds: Array = (arch.get("street", {}) as Dictionary).get("vehicles", ["car"])
	kinds = kinds.filter(func(k: String) -> bool: return k != "wreck")
	if kinds.is_empty():
		return
	var lanes: Array = []
	for i in range(nx + 1):
		var x := x0 + i * (block + street) - street * 0.5
		if x > b.position.x - 2.0 and x < b.end.x + 2.0:
			continue
		lanes.append([Vector3(x, 0.0, z0), Vector3(0, 0, 1), nz * (block + street)])
	for j in range(nz + 1):
		var z := z0 + j * (block + street) - street * 0.5
		if z > b.position.y - 2.0 and z < b.end.y + 2.0:
			continue
		lanes.append([Vector3(x0, 0.0, z), Vector3(1, 0, 0), nx * (block + street)])
	if lanes.is_empty():
		return
	var traffic := GroundTraffic.new()
	traffic.name = "GroundTraffic"
	traffic.setup(lanes.slice(0, WorldQuality.scenery(16)), kinds)
	root.add_child(traffic)
