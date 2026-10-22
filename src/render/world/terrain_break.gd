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
		Fx.dust(fx, Vector3.UP * minf(h, 1.5) * 0.4, 14, Color(0.55, 0.5, 0.45, 0.6), 1.6, 1.0, 3.0)
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
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	p.material_override = m
	p.scale_amount_curve = null
	p.emitting = true
	# Chunks are 1 unit across before scaling.
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	return p
