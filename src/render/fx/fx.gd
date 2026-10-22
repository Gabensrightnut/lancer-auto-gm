class_name Fx
extends RefCounted
## One-shot and lasting visual effects, all generated in code. Every function adds nodes
## under `root` and cleans them up itself. Durations are divided by `speed` (the playback
## speed setting); functions that take time return after the effect's main beat, so callers
## can `await` them to sequence an animation.

const SMOKE_SHADER := preload("res://src/render/shaders/smoke.gdshader")
const WALL_SHADER := preload("res://src/render/shaders/hard_light.gdshader")
const GLYPHS := ["0", "1", "7", "A", "F", "#", "%", "<", ">", "/", "=", "∆", "Σ", "Ξ", "λ"]

static var speed := 1.0
static var _soft_tex: GradientTexture2D
static var _soft_add_tex: GradientTexture2D


## Soft round puff that fades to black as well as to clear, for additive blending (which
## ignores alpha, so a white-edged texture would draw every puff as a square).
static func soft_add_texture() -> GradientTexture2D:
	if _soft_add_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.5, Color(0.35, 0.35, 0.35, 0.35))
		g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0))
		_soft_add_tex = GradientTexture2D.new()
		_soft_add_tex.gradient = g
		_soft_add_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_add_tex.fill_from = Vector2(0.5, 0.5)
		_soft_add_tex.fill_to = Vector2(1.0, 0.5)
		_soft_add_tex.width = 64
		_soft_add_tex.height = 64
	return _soft_add_tex


static func wait(root: Node, seconds: float) -> void:
	if speed <= 0.0 or seconds <= 0.0:
		return
	await root.get_tree().create_timer(seconds / speed).timeout


static func t(seconds: float) -> float:
	return seconds / maxf(speed, 0.01)


static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex


static func _free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(seconds).timeout.connect(node.queue_free)


## Brief point light, for flashes that light up the scene around them.
static func light_flash(root: Node3D, pos: Vector3, color: Color, energy: float = 4.0, radius: float = 3.0, dur: float = 0.25) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.position = pos
	root.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, t(dur))
	tw.tween_callback(l.queue_free)


static func _glow_sphere(root: Node3D, pos: Vector3, color: Color, radius: float, energy: float = 3.0) -> MeshInstance3D:
	var mi := MeshKit.part(root, MeshKit.sphere(1.0, 16), MeshKit.fx_material(color, energy), pos)
	mi.scale = Vector3.ONE * radius
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func muzzle_flash(root: Node3D, pos: Vector3, color: Color, size: float = 0.12) -> void:
	var s := _glow_sphere(root, pos, color, size, 5.0)
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * size * 1.8, t(0.08))
	tw.parallel().tween_method(func(a: float) -> void: s.set_instance_shader_parameter("alpha", a), 1.0, 0.0, t(0.12))
	tw.tween_callback(s.queue_free)
	light_flash(root, pos, color, 3.0, 2.5, 0.15)


## A glowing streak between two points (tracers, beams). Returns the node.
static func streak(root: Node3D, from: Vector3, to: Vector3, color: Color, width: float, energy: float = 4.0) -> MeshInstance3D:
	var len := from.distance_to(to)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.cylinder(0.5, 1.0, 8)
	mi.material_override = MeshKit.fx_material(color, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_orient_between(mi, from, to, width, len)
	return mi


static func _orient_between(mi: Node3D, from: Vector3, to: Vector3, width: float, len: float) -> void:
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	# Cylinder runs along y: rotate so y follows the shot direction.
	basis = basis * Basis(Vector3.RIGHT, -PI / 2.0)
	mi.global_transform = Transform3D(basis.scaled_local(Vector3(width, len, width)), (from + to) * 0.5)


## Kinetic tracer: a short bright slug flying from muzzle to impact.
static func tracer(root: Node3D, from: Vector3, to: Vector3, color: Color, flight: float = 0.12) -> void:
	var slug := streak(root, from, from.lerp(to, 0.15), color, 0.025, 6.0)
	var len := from.distance_to(to) * 0.15
	var tw := slug.create_tween()
	tw.tween_method(func(k: float) -> void:
		var head := from.lerp(to, k)
		var tail := from.lerp(to, maxf(0.0, k - 0.15))
		_orient_between(slug, tail, head, 0.025, maxf(0.01, tail.distance_to(head))), 0.15, 1.0, t(flight))
	tw.tween_callback(slug.queue_free)
	await slug.get_tree().create_timer(t(flight)).timeout


static func impact_puff(root: Node3D, pos: Vector3, color: Color = Color(1.0, 0.75, 0.4)) -> void:
	sparks(root, pos, color, 14)
	dust(root, pos, 4, Color(0.5, 0.47, 0.44, 0.5))


static func sparks(root: Node3D, pos: Vector3, color: Color, amount: int = 20, velocity: float = 3.0) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.5
	p.speed_scale = speed
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = velocity * 0.4
	p.initial_velocity_max = velocity
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3(0.015, 0.015, 0.06)
	m.material = MeshKit.fx_material(color, 6.0)
	p.mesh = m
	p.particle_flag_align_y = true
	root.add_child(p)
	p.emitting = true
	_free_after(p, 1.5)


static func _soft_material(color: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = soft_texture()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	if emissive > 0.0:
		# Glowing puffs (fire): additive, so overlapping puffs brighten and the soft
		# texture keeps every puff round.
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.albedo_texture = soft_add_texture()
		m.albedo_color = Color(color.r * emissive, color.g * emissive, color.b * emissive, color.a)  # HDR: glows
	return m


static func dust(root: Node3D, pos: Vector3, amount: int, color: Color, size: float = 0.4, rise: float = 0.6, life: float = 1.2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.speed_scale = speed
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector3(0, 0.2, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.2))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.material = _soft_material(Color.WHITE)
	p.mesh = q
	root.add_child(p)
	p.emitting = true
	_free_after(p, life / maxf(speed, 0.01) + 0.5)
	return p


## Energy beam: a charge-up glow at the muzzle, then a thick beam that fades.
static func beam(root: Node3D, from: Vector3, to: Vector3, color: Color, width: float = 0.07) -> void:
	var charge := _glow_sphere(root, from, color, 0.02, 5.0)
	var tw := charge.create_tween()
	tw.tween_property(charge, "scale", Vector3.ONE * 0.12, t(0.35))
	await tw.finished
	charge.queue_free()
	var core := streak(root, from, to, Color(1, 1, 1), width * 0.35, 6.0)
	var outer := streak(root, from, to, color, width, 3.5)
	light_flash(root, to, color, 4.0, 3.0, 0.4)
	light_flash(root, from, color, 3.0, 2.0, 0.3)
	for b: MeshInstance3D in [core, outer]:
		var bt := b.create_tween()
		bt.tween_interval(t(0.12))
		bt.tween_method(func(a: float) -> void: b.set_instance_shader_parameter("alpha", a), 1.0, 0.0, t(0.35))
		bt.tween_callback(b.queue_free)
	await root.get_tree().create_timer(t(0.12)).timeout


## A missile or shell flying on an arc, trailing smoke. Returns when it lands.
static func projectile_arc(root: Node3D, from: Vector3, to: Vector3, height: float, flight: float, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	var shell := Node3D.new()
	root.add_child(shell)
	MeshKit.part(shell, MeshKit.chamfer_box(Vector3(0.04, 0.04, 0.14), 0.01), MeshKit.mech_material(Color(0.3, 0.3, 0.3)))
	MeshKit.part(shell, MeshKit.sphere(0.035, 8), MeshKit.fx_material(color, 6.0), Vector3(0, 0, 0.08))
	var trail := dust(shell, Vector3.ZERO, 30, Color(0.75, 0.72, 0.7, 0.55), 0.18, 0.05, 0.9)
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.local_coords = false
	var prev := from
	var tw := shell.create_tween()
	tw.tween_method(func(k: float) -> void:
		var p := from.lerp(to, k) + Vector3.UP * height * 4.0 * k * (1.0 - k)
		if p.distance_to(prev) > 0.001:
			shell.look_at_from_position(p, p + (p - prev), Vector3.UP)
		prev = p, 0.0, 1.0, t(flight))
	await tw.finished
	trail.emitting = false
	trail.reparent(root)
	_free_after(trail, 1.5)
	shell.queue_free()


## Ground ring showing a blast radius before the explosion lands.
static func warning_ring(root: Node3D, center: Vector3, radius: float, dur: float = 0.6) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.04
	tm.outer_radius = radius
	tm.rings = 48
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = MeshKit.fx_material(Color(1.0, 0.3, 0.1), 3.0)
	ring.position = center + Vector3(0, 0.05, 0)
	ring.scale = Vector3(1, 0.2, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var tw := ring.create_tween().set_loops(3)
	tw.tween_method(func(a: float) -> void: ring.set_instance_shader_parameter("alpha", a), 1.0, 0.3, t(dur / 3.0))
	_free_after(ring, t(dur) + 0.05)


static func explosion(root: Node3D, pos: Vector3, radius: float = 0.8) -> void:
	# A brief white-hot flash, then a churning fireball of puffs (yellow -> orange -> dark
	# red -> smoke), sparks, debris and a dark smoke column rising after it.
	var flash_s := _glow_sphere(root, pos, Color(1.0, 0.85, 0.6), radius * 0.35, 5.0)
	var tw := flash_s.create_tween()
	tw.tween_method(func(a: float) -> void: flash_s.set_instance_shader_parameter("alpha", a), 1.0, 0.0, t(0.12))
	tw.tween_callback(flash_s.queue_free)
	light_flash(root, pos + Vector3.UP * 0.3, Color(1.0, 0.55, 0.2), 7.0, radius * 5.0, 0.6)
	fireball(root, pos, radius)
	sparks(root, pos, Color(1.0, 0.7, 0.3), 30, 5.0)
	debris(root, pos, 10)
	var smoke := dust(root, pos + Vector3.UP * radius * 0.3, 12, Color(0.12, 0.11, 0.1, 0.8), radius * 1.6, 1.0, 3.0)
	smoke.explosiveness = 0.6
	smoke.gravity = Vector3(0, 0.6, 0)


## The fireball itself: emissive soft puffs that bloom out and burn down to smoke.
static func fireball(root: Node3D, pos: Vector3, radius: float) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 22
	p.lifetime = 0.9
	p.speed_scale = speed
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.25
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = radius * 0.8
	p.initial_velocity_max = radius * 2.0
	p.damping_min = radius * 2.0
	p.damping_max = radius * 3.0
	p.gravity = Vector3(0, radius * 0.8, 0)
	p.scale_amount_min = radius * 0.7
	p.scale_amount_max = radius * 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.25))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.add_point(0.18, Color(1.0, 0.6, 0.15, 1.0))
	g.add_point(0.45, Color(0.75, 0.18, 0.04, 0.9))
	g.add_point(0.7, Color(0.15, 0.1, 0.08, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.08, 0.07, 0.06, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.material = _soft_material(Color.WHITE, 2.5)
	p.mesh = q
	root.add_child(p)
	p.emitting = true
	_free_after(p, 2.0)


static func debris(root: Node3D, pos: Vector3, amount: int, color: Color = Color(0.3, 0.29, 0.28)) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 1.0
	p.speed_scale = speed
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.mesh = MeshKit.chamfer_box(Vector3(0.05, 0.03, 0.04), 0.006)
	(p.mesh as ArrayMesh).surface_set_material(0, MeshKit.mech_material(color, 0.3, 0.8))
	root.add_child(p)
	p.emitting = true
	_free_after(p, 2.0)


## Melee swing: a bright arc in front of the attacker.
static func swing_arc(root: Node3D, center: Vector3, facing: Vector3, radius: float, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps := 16
	for i in range(steps + 1):
		var a := lerpf(-1.1, 1.1, float(i) / steps)
		var dir := Vector3(sin(a), 0.25 * (float(i) / steps - 0.5), -cos(a))
		var fade := sin(PI * float(i) / steps)
		st.set_color(Color(1, 1, 1, fade))
		st.add_vertex(dir * radius)
		st.set_color(Color(1, 1, 1, fade * 0.2))
		st.add_vertex(dir * radius * 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshKit.fx_material(color, 6.0, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = center
	mi.look_at(center + Vector3(facing.x, 0, facing.z), Vector3.UP)
	mi.rotate_object_local(Vector3.FORWARD, 0.4)
	var tw := mi.create_tween()
	tw.tween_method(func(a: float) -> void: mi.set_instance_shader_parameter("alpha", a), 1.0, 0.0, t(0.5))
	tw.tween_callback(mi.queue_free)


## Hit flash on a shell around a unit: blue for a deflected (missed) blow.
static func shield_flash(root: Node3D, pos: Vector3, radius: float, color: Color = Color(0.4, 0.75, 1.0)) -> void:
	var s := _glow_sphere(root, pos, color, radius, 1.5)
	var tw := s.create_tween()
	tw.tween_method(func(a: float) -> void: s.set_instance_shader_parameter("alpha", a), 0.8, 0.0, t(0.4))
	tw.tween_callback(s.queue_free)


## Floating text: damage numbers, MISS, +heat. Rises and fades.
static func float_text(root: Node3D, pos: Vector3, text: String, color: Color, size: int = 72) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = color
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = pos
	root.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, t(0.08))
	tw.tween_property(l, "scale", Vector3.ONE, t(0.1))
	tw.tween_property(l, "position", pos + Vector3.UP * 0.6, t(1.1))
	tw.parallel().tween_property(l, "modulate:a", 0.0, t(0.5)).set_delay(t(0.6))
	tw.tween_callback(l.queue_free)


## Tech attack link: a stream of glyphs from hacker to target along a thin beam.
static func data_link(root: Node3D, from: Vector3, to: Vector3, color: Color, dur: float = 1.0) -> void:
	var line := streak(root, from, to, color, 0.012, 3.0)
	var n := int(from.distance_to(to) * 3.0) + 6
	for i in range(n):
		var l := Label3D.new()
		l.text = GLYPHS[i % GLYPHS.size()] + GLYPHS[(i * 7 + 3) % GLYPHS.size()]
		l.font_size = 48
		l.pixel_size = 0.003
		l.modulate = color.lightened(0.3)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.shaded = false
		# Don't fill the screen when the beam passes the camera (cockpit view).
		l.visibility_range_begin = 1.5
		root.add_child(l)
		var offset := Vector3(sin(i * 2.1), cos(i * 1.7), sin(i * 0.9)) * 0.05
		var tw := l.create_tween()
		tw.tween_interval(t(dur * 0.6 * float(i) / n))
		tw.tween_method(func(k: float) -> void: l.position = from.lerp(to, k) + offset, 0.0, 1.0, t(dur * 0.4))
		tw.tween_callback(l.queue_free)
	var lt := line.create_tween()
	lt.tween_interval(t(dur))
	lt.tween_method(func(a: float) -> void: line.set_instance_shader_parameter("alpha", a), 1.0, 0.0, t(0.3))
	lt.tween_callback(line.queue_free)
	await root.get_tree().create_timer(t(dur)).timeout


## Vent steam: white plumes from a unit (Stabilize / venting heat).
static func steam(root: Node3D, pos: Vector3, scale: float = 1.0) -> void:
	var p := dust(root, pos, 24, Color(0.92, 0.94, 0.96, 0.6), 0.35 * scale, 2.0 * scale, 1.6)
	p.explosiveness = 0.3
	p.spread = 35.0
	p.gravity = Vector3(0, 1.0, 0)


## Burning: flames that keep going until the returned node is freed.
static func fire(root: Node3D, pos: Vector3, scale: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	# Tongues of flame: puffs born wide at the base that shrink and cool as they rise,
	# with a thin dark smoke trail above (a child emitter freed with the fire).
	p.amount = 18
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 0.6 * scale
	p.initial_velocity_max = 1.1 * scale
	p.gravity = Vector3(0, 1.2 * scale, 0)
	p.spread = 12.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * scale
	p.scale_amount_min = 0.14 * scale
	p.scale_amount_max = 0.28 * scale
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.35))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.3, 0.6))
	g.add_point(0.3, Color(1.0, 0.4, 0.08, 0.55))
	g.add_point(0.7, Color(0.7, 0.12, 0.02, 0.35))
	g.set_color(g.get_point_count() - 1, Color(0.2, 0.05, 0.02, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.material = _soft_material(Color.WHITE, 1.9)
	p.mesh = q
	root.add_child(p)
	p.emitting = true
	var smoke := CPUParticles3D.new()
	smoke.position = Vector3.UP * 0.35 * scale
	smoke.amount = 14
	smoke.lifetime = 2.2
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.3 * scale
	smoke.initial_velocity_max = 0.5 * scale
	smoke.gravity = Vector3(0.15, 0.2, 0)
	smoke.scale_amount_min = 0.25 * scale
	smoke.scale_amount_max = 0.45 * scale
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = sc
	var sg := Gradient.new()
	sg.set_color(0, Color(0.1, 0.09, 0.08, 0.0))
	sg.add_point(0.15, Color(0.1, 0.09, 0.08, 0.55))
	sg.set_color(sg.get_point_count() - 1, Color(0.15, 0.14, 0.13, 0.0))
	smoke.color_ramp = sg
	var sq := QuadMesh.new()
	sq.material = _soft_material(Color.WHITE)
	smoke.mesh = sq
	p.add_child(smoke)
	smoke.emitting = true
	return p


## A cloud of smoke over some world positions (cell centers). Lasts until freed.
static func smoke_cloud(root: Node3D, points: Array, height: float = 1.2) -> Node3D:
	var cloud := Node3D.new()
	cloud.name = "Smoke"
	root.add_child(cloud)
	var mat := ShaderMaterial.new()
	mat.shader = SMOKE_SHADER
	var i := 0
	for p: Vector3 in points:
		for k in range(5):
			i += 1
			var q := MeshInstance3D.new()
			var quad := QuadMesh.new()
			var s := 0.9 + 0.5 * MeshKit.hash01("smoke", i)
			quad.size = Vector2(s, s)
			q.mesh = quad
			q.material_override = mat
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = p + Vector3(MeshKit.hash01("sx", i) - 0.5, 0.25 + height * MeshKit.hash01("sy", i), MeshKit.hash01("sz", i) - 0.5) * Vector3(0.8, 1, 0.8)
			q.set_instance_shader_parameter("seed", MeshKit.hash01("ss", i) * 10.0)
			q.scale = Vector3.ONE * 0.05
			cloud.add_child(q)
			var tw := q.create_tween()
			tw.tween_property(q, "scale", Vector3.ONE, t(0.6 + 0.4 * MeshKit.hash01("st", i))).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return cloud


## Hard light wall: builds as a wireframe, then fills in. `segments` is an array of
## [from, to] world points along the floor; the wall is `height` tall.
static func hard_light_wall(root: Node3D, segments: Array, height: float = 1.0) -> Node3D:
	var wall := Node3D.new()
	wall.name = "HardLight"
	root.add_child(wall)
	var mat := ShaderMaterial.new()
	mat.shader = WALL_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg: Array in segments:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var outward := (b - a).cross(Vector3.UP)
		for v in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [b + Vector3.UP * height, Vector2(1, 1)], [a, Vector2(0, 0)], [b + Vector3.UP * height, Vector2(1, 1)], [a + Vector3.UP * height, Vector2(0, 1)]]:
			st.set_normal(outward.normalized())
			st.set_uv(v[1])
			st.set_uv2(Vector2(a.distance_to(b), height))
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(mi)
	mi.set_instance_shader_parameter("build", 0.0)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("build", v), 0.0, 1.0, t(0.9))
	return wall


## Glitch a unit's model for a while (tech attack hit).
static func glitch(model: MechModel, dur: float = 1.0) -> void:
	var tw := model.create_tween()
	tw.tween_method(func(v: float) -> void: model.set_fx("glitch", v), 1.0, 0.0, t(dur))


static func hit_flash(model: MechModel) -> void:
	var tw := model.create_tween()
	tw.tween_method(func(v: float) -> void: model.set_fx("flash", v), 1.0, 0.0, t(0.25))
