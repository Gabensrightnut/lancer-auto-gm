class_name ExploreInput
extends RefCounted
## Walking around out of combat (hubs, towns, inside buildings): the explore actions in
## data/game/keybinds.json ("context": "explore", rebindable in Settings), kept apart from the
## battle camera keys so the same letters can mean different things in each. First person
## plays like a normal first-person game: W/S forward and back, A/D strafe relative to where
## you look, the mouse turns and aims, Shift runs, Space jumps, E (or left click) uses what's
## under the crosshair. Third person: WASD relative to the camera, Z/X (or right-drag) turn it.

const MOVE := ["move_forward", "move_back", "move_left", "move_right"]
const WALK := 4.2
const RUN := 1.8  # times walking speed
const SNEAK := 0.5
const JUMP_SPEED := 4.2
const GRAVITY := 14.0
## Mouse look: radians per pixel at sensitivity 1.
const LOOK := 0.003
const PITCH_MIN := -1.05
const PITCH_MAX := 1.05


## Movement keys as (strafe right, forward), each -1..1.
static func axes() -> Vector2:
	if not InputMap.has_action("move_forward"):
		return Vector2.ZERO
	return Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))


## A ground direction from the view's yaw: forward goes where you look, strafe goes right of it.
## Diagonals aren't faster.
static func direction(yaw: float, forward: float, strafe: float) -> Vector3:
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	var d := f * forward + r * strafe
	return d.normalized() if d.length() > 1.0 else d


static func speed(running: bool, sneaking: bool) -> float:
	if sneaking:
		return WALK * SNEAK
	return WALK * (RUN if running else 1.0)


## Mouse motion -> new (yaw, pitch). Moving the mouse right turns right; up looks up (unless
## inverted).
static func look(yaw: float, pitch: float, rel: Vector2, sensitivity: float, invert_y: bool) -> Vector2:
	var k := LOOK * sensitivity
	var dy := rel.y * k * (-1.0 if invert_y else 1.0)
	return Vector2(yaw - rel.x * k, clampf(pitch - dy, PITCH_MIN, PITCH_MAX))


## One step of a jump: (height, vertical speed) after `delta` seconds. Lands at 0.
static func jump_step(height: float, vel: float, delta: float) -> Vector2:
	vel -= GRAVITY * delta
	height += vel * delta
	if height <= 0.0:
		return Vector2.ZERO
	return Vector2(height, vel)
