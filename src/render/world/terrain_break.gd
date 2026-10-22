class_name TerrainBreak
extends RefCounted
## Destroyed terrain visibly breaks: chunks of the old column burst out and tumble down, and
## a dust cloud rolls over the spot while the board is rebuilt with the new map.


## `cells`: Array of Vector2i; `old_heights`: cell -> ground before it broke.
static func play(t: TerrainRenderer, cells: Array, old_heights: Dictionary = {}) -> void:
	if not t.is_inside_tree():
		return  # nothing on screen to animate (e.g. headless checks)
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
		_collapse(t, fx, c, h)
		Fx.dust(fx, Vector3.UP * minf(h, 1.5) * 0.4, 14, Color(0.55, 0.5, 0.45, 0.6), 1.6, 1.0, 3.0)
		var timer := fx.get_tree().create_timer(6.0) if fx.is_inside_tree() else null
		if timer:
			timer.timeout.connect(fx.queue_free)


## A copy of the lost part of the column that shudders, leans and sinks into the ground.
static func _collapse(t: TerrainRenderer, fx: Node3D, cell: Vector2i, h: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Drawn as a wall in the terrain shader (vertex color = surface kind; UV2.y = its top).
	st.set_color(Color(TerrainRenderer.KIND_WALL / 16.0, 0.5, 0.0, 1.0))
	st.set_uv2(Vector2(1.0, h))
	var center := t.map.grid.to_world(cell)
	var pts := t.cell_corners(cell, 0.0, 0.03)
	for i in range(pts.size()):
		var a := pts[i] - Vector3(center.x, 0, center.z)
		var b := pts[(i + 1) % pts.size()] - Vector3(center.x, 0, center.z)
		MeshKit.add_quad(st, a, b, b + Vector3.UP * h, a + Vector3.UP * h, ((a + b) * 0.5).normalized())
		MeshKit.add_tri(st, Vector3.UP * h, a + Vector3.UP * h, b + Vector3.UP * h, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Collapse"
	mi.mesh = st.commit()
	mi.material_override = t.material
	fx.add_child(mi)
	if not mi.is_inside_tree():
		return
	var lean := Vector3(WorldRand.f(str(cell), 1) - 0.5, 0, WorldRand.f(str(cell), 2) - 0.5).normalized() * deg_to_rad(14.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "position", Vector3(0.03, 0, 0), 0.05)
	tw.tween_property(mi, "position", Vector3(-0.03, 0, 0.02), 0.05)
	tw.tween_property(mi, "position", Vector3(0.02, -0.02, -0.02), 0.05)
	tw.tween_property(mi, "rotation", lean, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "position", Vector3(0, -h - 0.2, 0), 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mi.queue_free)


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
