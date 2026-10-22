class_name TacticalCamera
extends Node3D
## Angled overhead camera that orbits a focus point. Right-drag or Q/E rotates, wheel zooms,
## WASD or middle-drag pans. Smoothly follows `focus` when it moves.

var camera: Camera3D
var focus := Vector3.ZERO
var yaw := -25.0
var pitch := -52.0
var distance := 16.0
var min_distance := 4.0
var max_distance := 40.0

var _cur_focus := Vector3.ZERO
var _cur_yaw := yaw
var _cur_pitch := pitch
var _cur_dist := distance
var _dragging_rotate := false
var _dragging_pan := false


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 400.0
	add_child(camera)


func snap() -> void:
	_cur_focus = focus
	_cur_yaw = yaw
	_cur_pitch = pitch
	_cur_dist = distance
	_apply()


func look_at_point(p: Vector3, dist: float = -1.0) -> void:
	focus = p
	if dist > 0.0:
		distance = dist


## Frames two points side-on (e.g. attacker and target) so the action between them reads.
## `blocked`, if given, is called with a camera position and returns how much terrain hides
## the pair from there (0 = clear); the least blocked of several angles is used.
func frame_pair(a: Vector3, b: Vector3, min_dist: float = 5.0, blocked: Callable = Callable()) -> void:
	var d := b - a
	d.y = 0.0
	focus = (a + b) * 0.5 + Vector3.UP * 0.5
	distance = maxf(min_dist, d.length() * 1.15 + 2.0)
	var side := d.cross(Vector3.UP).normalized() if d.length() > 0.01 else Vector3.FORWARD
	var lean := d.normalized() * 0.35 if d.length() > 0.01 else Vector3.ZERO
	# Candidates: both sides of the line between them, at a normal and a steep angle.
	var best := INF
	for p: float in [-36.0, -52.0]:
		for s: float in [1.0, -1.0]:
			var fwd := (side * s + lean).normalized()
			var y := rad_to_deg(atan2(-fwd.x, -fwd.z))
			var cost := 0.0
			if blocked.is_valid():
				var basis := Basis.from_euler(Vector3(deg_to_rad(p), deg_to_rad(y), 0))
				cost = float(blocked.call(focus + basis.z * distance))
			# Prefer the side facing the default view, and shallower angles.
			cost += (0.0 if fwd.z <= 0.0 else 0.3) + (0.0 if p == -36.0 else 1.5)
			if cost < best:
				best = cost
				yaw = y
				pitch = p


func _process(delta: float) -> void:
	if not camera.current:
		return
	var pan := Vector3.ZERO
	if Input.is_action_pressed("cam_pan_left"):
		pan.x -= 1
	if Input.is_action_pressed("cam_pan_right"):
		pan.x += 1
	if Input.is_action_pressed("cam_pan_up"):
		pan.z -= 1
	if Input.is_action_pressed("cam_pan_down"):
		pan.z += 1
	if Input.is_action_pressed("cam_rotate_left"):
		yaw += 90.0 * delta
	if Input.is_action_pressed("cam_rotate_right"):
		yaw -= 90.0 * delta
	if pan != Vector3.ZERO:
		focus += pan.normalized().rotated(Vector3.UP, deg_to_rad(yaw)) * distance * 0.8 * delta
	var k := 1.0 - exp(-8.0 * delta)
	_cur_focus = _cur_focus.lerp(focus, k)
	_cur_yaw = lerpf(_cur_yaw, yaw, k)
	_cur_pitch = lerpf(_cur_pitch, pitch, k)
	_cur_dist = lerpf(_cur_dist, distance, k)
	_apply()


func _apply() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(_cur_pitch), deg_to_rad(_cur_yaw), 0))
	camera.global_transform = Transform3D(basis, _cur_focus + basis.z * _cur_dist)


func _unhandled_input(event: InputEvent) -> void:
	if not camera.current:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(min_distance, distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(max_distance, distance * 1.1)
			MOUSE_BUTTON_RIGHT:
				_dragging_rotate = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_dragging_pan = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_rotate:
			yaw -= mm.relative.x * 0.3
			pitch = clampf(pitch - mm.relative.y * 0.2, -85.0, -15.0)
		elif _dragging_pan:
			var right := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw))
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw))
			focus += (-right * mm.relative.x + fwd * mm.relative.y) * distance * 0.0015
