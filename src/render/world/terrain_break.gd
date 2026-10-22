class_name TerrainBreak
extends RefCounted
## Destroyed terrain visibly breaks: chunks of the old column burst out and tumble down, and
## a dust cloud rolls over the spot while the board is rebuilt with the new map.


## `cells`: Array of Vector2i; `old_heights`: cell -> ground before it broke.
static func play(t: TerrainRenderer, cells: Array, old_heights: Dictionary = {}) -> void:
	var host: Node = t.get_parent() if t.get_parent() else t
	var chunk_color := WorldStyle.col(t.style, "ground.wall", Color(0.5, 0.48, 0.45))
	for c: Vector2i in cells:
		var old := float(old_heights.get(c, t.map.ground_height(c) + 1)) * GridLayout.LEVEL_HEIGHT
		var now := t.top_y(c)
		var base := t.map.grid.to_world(c)
		var h := maxf(old - now, 0.4)
		var fx := Node3D.new()
		fx.name = "Break"
		host.add_child(fx)
		fx.global_position = base + Vector3.UP * now
		fx.add_child(_chunks(h, chunk_color, t.surface(c)))
		fx.add_child(_dust(h))
		var timer := fx.get_tree().create_timer(6.0) if fx.is_inside_tree() else null
		if timer:
			timer.timeout.connect(fx.queue_free)


static func _chunks(h: float, color: Color, _kind: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = int(18 + h * 14.0)
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.4, h * 0.5, 0.4)
	p.position = Vector3.UP * h * 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.mesh = Flora.rock(color, 30)
	var m := ShaderMaterial.new()
	m.shader = WorldDressing.FOLIAGE_SHADER
	m.set_shader_parameter("sway", 0.0)
	m.set_shader_parameter("leafy", 0.0)
	p.material_override = m
	p.scale_amount_curve = null
	p.emitting = true
	# Chunks are 1 unit across before scaling.
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	return p


static func _dust(h: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 40
	p.lifetime = 3.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.position = Vector3.UP * minf(h, 1.5) * 0.4
	p.direction = Vector3.UP
	p.spread = 90.0
	p.gravity = Vector3(0, 0.2, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.damping_min = 0.8
	p.damping_max = 1.2
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Fx.soft_texture()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.5, 0.45, 0.0))
	g.add_point(0.1, Color(0.55, 0.5, 0.45, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.57, 0.53, 0.0))
	p.color_ramp = g
	p.emitting = true
	return p
