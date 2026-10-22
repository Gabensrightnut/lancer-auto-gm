class_name FreeWalker
extends Node
## Real-time movement for a mech outside combat (exploring): smooth position and facing, the
## gait animation driven by the actual distance covered (feet land in step), the mech riding
## the terrain height, and an ease-in/ease-out so it doesn't slide. Grid-free: positions are
## points in the BattleView's space (the MechView's position); the terrain height comes from
## the board's map through GridLayout.
##
##   var w := FreeWalker.attach(mech_view)        # or FreeWalker.new() as a child of a MechView
##   w.walk_to(point)                              # click-to-move: walks there and stops
##   w.move_input = Vector2(x, y)                  # or steer it (WASD/stick): -1..1 each axis
##   w.arrived.connect(...)
## `speed` is meters per second at a full stride; big frames are slower (set from Size).

signal arrived

var mv: MechView
## Meters per second at full stride.
var speed := 3.2
## Degrees per second the body can turn.
var turn_rate := 240.0
## Steering input (x right, y forward, camera-relative if `camera_yaw` is set).
var move_input := Vector2.ZERO
## Camera yaw in degrees, so "forward" on the stick is away from the camera.
var camera_yaw := 0.0
var _target: Variant = null
var _vel := Vector3.ZERO


static func attach(view: MechView) -> FreeWalker:
	var w := FreeWalker.new()
	view.add_child(w)
	return w


func _ready() -> void:
	mv = get_parent() as MechView
	if mv and mv._ring:
		mv._ring.visible = false  # no grid footprint outside combat
	if mv and mv.model:
		# Heavier frames walk slower: Size 1 ~3.2 m/s, Size 3 ~2.2 m/s.
		speed = 3.6 - 0.45 * clampf(mv.model.size, 0.5, 3.0)


func walk_to(point: Vector3) -> void:
	_target = point


func stop() -> void:
	_target = null
	move_input = Vector2.ZERO


func is_moving() -> bool:
	return _vel.length() > 0.05


func _physics_process(delta: float) -> void:
	if mv == null or mv.model == null:
		return
	var want := Vector3.ZERO
	if move_input.length() > 0.05:
		var f := Vector3(move_input.x, 0, -move_input.y).rotated(Vector3.UP, deg_to_rad(camera_yaw))
		want = f.limit_length(1.0) * speed
		_target = null
	elif _target is Vector3:
		var to: Vector3 = (_target as Vector3) - mv.position
		to.y = 0.0
		var d := to.length()
		if d < 0.08:
			_target = null
			arrived.emit()
		else:
			# Slow down over the last meter.
			want = to.normalized() * speed * clampf(d / 1.0, 0.25, 1.0)
	# Ease the velocity (accelerate ~0.3 s, stop ~0.25 s).
	_vel = _vel.lerp(want, clampf(delta * (6.0 if want.length() > _vel.length() else 8.0), 0.0, 1.0))
	var step := _vel * delta
	if step.length() > 0.0001:
		var p := mv.position + step
		p.y = ground_height(p)
		mv.position = p
		# Turn smoothly toward the direction of travel.
		var face := atan2(-_vel.x, -_vel.z)
		var cur := mv.model.rotation.y
		var diff := wrapf(face - cur, -PI, PI)
		mv.model.rotation.y = cur + clampf(diff, -deg_to_rad(turn_rate) * delta, deg_to_rad(turn_rate) * delta)
		# Gait: advance the walk phase by distance (steps_per_cell strides per meter of grid).
		mv.model.walk_phase += step.length() * mv.model.steps_per_cell() * PI / maxf(0.5, GridLayout.SPACE)
	var amount := clampf(_vel.length() / maxf(0.1, speed), 0.0, 1.0)
	mv.model.walk_amount = amount
	if amount <= 0.01:
		mv.model.set_walk(0.0)
	else:
		mv.model.set_walk(amount)


## Terrain height under a world point (top of the column), smoothed between columns.
func ground_height(p: Vector3) -> float:
	var b: BattleView = mv.battle
	if b == null or b.map == null:
		return p.y
	var c := b.map.grid.from_world(p)
	if not b.map.has_cell(c):
		return p.y
	var target := b.map.ground_height(c) * GridLayout.LEVEL_HEIGHT
	return lerpf(mv.position.y, target, 0.25)
