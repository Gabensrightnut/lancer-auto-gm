class_name WorldParticles
extends RefCounted
## Air over the board: pollen, dust, snow, spores, embers, ash or rain (style "particles",
## a name or a list of names). Tiny and see-through: never thick enough to look like smoke.


static func build(t: TerrainRenderer, root: Node3D) -> void:
	var kinds: Variant = t.style.get("particles", "")
	var list: Array = kinds if kinds is Array else [kinds]
	var b := t.bounds(2.0)
	for k: String in list:
		var p := _make(k, b)
		if p:
			root.add_child(p)


static func _make(kind: String, b: Rect2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Air_" + kind
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.gravity = Vector3.ZERO
	var area := b.size.x * b.size.y
	var color := Color(1, 1, 1, 0.6)
	var size := 0.035
	var additive := false
	var height := 3.0
	match kind:
		"pollen":
			p.amount = int(area * 0.15)
			p.lifetime = 12.0
			p.direction = Vector3(1, 0.1, 0.3)
			p.spread = 30.0
			p.initial_velocity_min = 0.1
			p.initial_velocity_max = 0.3
			color = Color(1.0, 0.96, 0.78, 0.65)
		"dust":
			p.amount = int(area * 0.12)
			p.lifetime = 10.0
			p.direction = Vector3(1, 0.05, 0.2)
			p.spread = 20.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.7
			color = Color(0.95, 0.85, 0.7, 0.35)
			size = 0.05
		"snow":
			p.amount = int(area * 0.8)
			p.lifetime = 9.0
			p.direction = Vector3(0.3, -1, 0.1)
			p.spread = 15.0
			p.gravity = Vector3(0.1, -0.3, 0)
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 0.8
			color = Color(1, 1, 1, 0.85)
			size = 0.04
			height = 7.0
		"spores":
			p.amount = int(area * 0.18)
			p.lifetime = 14.0
			p.direction = Vector3(0.2, 1, 0.1)
			p.spread = 25.0
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.2
			color = Color(0.4, 1.0, 0.85, 1.0)
			size = 0.05
			additive = true
		"embers":
			p.amount = int(area * 0.2)
			p.lifetime = 6.0
			p.direction = Vector3(0.3, 1, 0.1)
			p.spread = 30.0
			p.gravity = Vector3(0.1, 0.15, 0)
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.6
			color = Color(1.0, 0.5, 0.15, 1.0)
			size = 0.03
			additive = true
		"ash":
			p.amount = int(area * 0.5)
			p.lifetime = 10.0
			p.direction = Vector3(0.4, -1, 0.2)
			p.spread = 25.0
			p.gravity = Vector3(0.1, -0.15, 0)
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.5
			color = Color(0.55, 0.53, 0.5, 0.7)
			size = 0.035
			height = 7.0
		"rain":
			p.amount = int(area * 2.5)
			p.lifetime = 0.9
			p.direction = Vector3(0.15, -1, 0.05)
			p.spread = 3.0
			p.gravity = Vector3(0, -9.0, 0)
			p.initial_velocity_min = 9.0
			p.initial_velocity_max = 11.0
			color = Color(0.7, 0.78, 0.95, 0.12)
			height = 9.0
		_:
			return null
	p.amount = WorldQuality.particles(clampi(p.amount, 40, 6000))
	p.preprocess = p.lifetime
	p.emission_box_extents = Vector3(b.size.x * 0.5, height * 0.5, b.size.y * 0.5)
	p.position = Vector3(b.get_center().x, height * 0.5 + 0.5, b.get_center().y)
	p.visibility_aabb = AABB(Vector3(-b.size.x, -height * 2.0, -b.size.y), Vector3(b.size.x * 2.0, height * 4.0, b.size.y * 2.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = color
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	if kind == "rain":
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		q.size = Vector2(0.006, 0.3)
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = Fx.soft_texture()
		q.size = Vector2(size, size)
	q.material = m
	p.mesh = q
	if kind in ["spores", "embers"]:
		p.color_ramp = WorldHazards._ramp([[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
		m.vertex_color_use_as_albedo = true
	return p
