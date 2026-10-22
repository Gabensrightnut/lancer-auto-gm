class_name WorldHazards
extends RefCounted
## Dangerous terrain burns, sparks or fumes (color from the style's ground.hazard): low
## flames and embers on every dangerous cell, a faint short smoke wisp, and flickering light.
## The ground itself glows through cracks (terrain shader). Liquid hazards (lava, toxic)
## glow by their liquid shader instead; they get only embers or bubbles of light.


static func build(t: TerrainRenderer, root: Node3D) -> void:
	var points := PackedVector3Array()
	var cells: Array[Vector2i] = []
	for c in t.map.cells():
		var col := t.map.column(c)
		if not col.has_tag(BattleMap.TAG_DANGEROUS) or t.structure_cells.has(c):
			continue
		cells.append(c)
		for i in range(3):
			points.append(t.random_point(c, "hz" + str(c), i, 0.7) + Vector3.UP * (0.25 if t.liquid_of(c) != "" else 0.02))
	if points.is_empty():
		return
	var hot := WorldStyle.col(t.style, "ground.hazard", Color(1.0, 0.4, 0.08))
	root.add_child(_flames(points, hot))
	root.add_child(_embers(points, hot))
	root.add_child(_smoke(points))
	# A few flickering lights, one per cluster of nearby hazard cells.
	var lit: Array[Vector3] = []
	for c in cells:
		var p := t.map.grid.to_world(c) + Vector3.UP * (t.top_y(c) + 0.5)
		var near := false
		for q in lit:
			if q.distance_to(p) < 3.0:
				near = true
				break
		if near or lit.size() >= 8:
			continue
		lit.append(p)
		var l := FlickerLight.new()
		l.light_color = hot.lerp(Color(1, 0.85, 0.6), 0.3)
		l.base_energy = 1.6
		l.omni_range = 3.5
		l.position = p
		l.shadow_enabled = false
		root.add_child(l)


static func _quad_material(color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Fx.soft_texture()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return s[0]))
	g.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1]))
	return g


static func _particles(points: PackedVector3Array, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.local_coords = false
	return p


static func _flames(points: PackedVector3Array, hot: Color) -> CPUParticles3D:
	var p := _particles(points, mini(points.size() * 10, 1500), 0.8)
	p.name = "Flames"
	p.direction = Vector3.UP
	p.spread = 8.0
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = curve
	p.color_ramp = _ramp([[0.0, Color(1, 0.9, 0.6, 0.0)], [0.12, Color(1, 0.75, 0.35, 0.55)], [0.45, Color(hot.r, hot.g, hot.b, 0.4)], [1.0, Color(hot.r * 0.4, hot.g * 0.15, 0.0, 0.0)]])
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.3)
	q.material = _quad_material(Color(1.3, 1.15, 1.0), true)
	p.mesh = q
	return p


static func _embers(points: PackedVector3Array, hot: Color) -> CPUParticles3D:
	var p := _particles(points, mini(points.size() * 2, 300), 2.2)
	p.name = "Embers"
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0.15, 0.25, 0.05)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.color_ramp = _ramp([[0.0, Color(1, 0.9, 0.6, 1)], [0.7, Color(hot.r, hot.g, hot.b, 0.8)], [1.0, Color(hot.r, hot.g * 0.3, 0, 0)]])
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	q.material = _quad_material(Color(3, 2.5, 2), true)
	p.mesh = q
	return p


## Faint wisps that thin out by about mech height, so they never read as a smoke screen.
static func _smoke(points: PackedVector3Array) -> CPUParticles3D:
	var p := _particles(points, mini(points.size(), 200), 2.6)
	p.name = "Smoke"
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0.1, 0.12, 0.0)
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	p.color_ramp = _ramp([[0.0, Color(0.2, 0.18, 0.16, 0.0)], [0.25, Color(0.2, 0.18, 0.16, 0.22)], [1.0, Color(0.3, 0.29, 0.28, 0.0)]])
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = _quad_material(Color(1, 1, 1), false)
	p.mesh = q
	return p
