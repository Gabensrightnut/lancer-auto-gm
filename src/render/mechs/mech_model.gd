class_name MechModel
extends Node3D
## A generated mech: a jointed body (legs, torso, head, arms) plus weapons in their mounts.
## Faces -Z. Built by MechBuilder; animated by MechView and EventPlayer through the joints
## and per-instance shader values (heat, flash, glitch).

var frame_id := ""
var manufacturer := ""
var size := 1.0
## World height of the body after scaling (Size in levels).
var height := 1.0
var root_scale := 1.0

var pelvis: Node3D
var torso: Node3D
var head: Node3D
var eye: Marker3D
## [{"hip": Node3D, "knee": Node3D, "ankle": Node3D, "base": Vector3}] base = rest angles (deg).
var legs: Array = []
## "r"/"l" -> {"shoulder": Node3D, "elbow": Node3D, "hand": Node3D}
var arms: Dictionary = {}
## Attachment points: hand_r, hand_l, forearm_r, forearm_l, shoulder_r, shoulder_l, back_r, back_l.
var slots: Dictionary = {}
## weapon id -> weapon root Node3D (first copy if equipped twice).
var weapons: Dictionary = {}
## Slot name -> weapon id, for arm aiming.
var slot_weapon: Dictionary = {}
var meshes: Array[GeometryInstance3D] = []
## Nodes that spin or bob on their own (nanite clouds, drones, halos): [{node, axis, speed}]
var spinners: Array = []

## Locomotion style from data/game/locomotion.json: biped, digitigrade, quadruped, hexapod,
## tracked, hover, winged. Visual only.
var gait := "biped"
## Gait phase in radians. Each step is PI; the mover advances it by distance travelled so
## feet are planted (phase a multiple of PI) exactly when the model reaches a cell.
var walk_phase := 0.0
## 0 = standing, 1 = full stride (fades in and out).
var walk_amount := 0.0
## Flying with wings/thrusters (gait "winged"/"hover" style motion) instead of walking.
var airborne := false
var _idle_t := 0.0

static var _locomotion: Dictionary = {}


## The gait a frame uses (data/game/locomotion.json).
static func gait_for(frame_id: String) -> String:
	if _locomotion.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/locomotion.json"))
		_locomotion = d if d is Dictionary else {"default": {"gait": "biped"}, "frames": {}}
	var f: Dictionary = (_locomotion.get("frames", {}) as Dictionary).get(frame_id, _locomotion.get("default", {}))
	return String(f.get("gait", "biped"))


## Steps per cell crossed, so the stride scales with Size and a whole number of steps
## covers each space (Size 1/2: 4, Size 1: 2, Size 2 and up: 1).
func steps_per_cell() -> int:
	return maxi(1, roundi(2.0 / maxf(size, 0.5)))


func _process(delta: float) -> void:
	for s: Dictionary in spinners:
		(s["node"] as Node3D).rotate(s["axis"], s["speed"] * delta)
	if walk_amount > 0.001 or airborne or gait == "hover":
		_idle_t += delta
		_apply_walk()


## Sets a per-instance shader value (heat 0..1, flash 0..1, glitch 0..1) on every part.
func set_fx(param: String, value: float) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter(param, value)


func collect_meshes() -> void:
	meshes.clear()
	_collect(self)


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			meshes.append(c)
		_collect(c)


## Where a weapon's shots leave from, in world space.
func muzzle_position(weapon_id: String) -> Vector3:
	var w: Node3D = weapons.get(weapon_id)
	if w == null:
		return eye.global_position if eye else global_position + Vector3.UP * height * 0.7
	var m := w.get_node_or_null("Muzzle") as Node3D
	return m.global_position if m else w.global_position


## The arm holding a weapon ("r", "l" or "" if it's not hand-held).
func arm_for(weapon_id: String) -> String:
	for slot: String in slot_weapon:
		if slot_weapon[slot] == weapon_id and (slot.begins_with("hand_") or slot.begins_with("forearm_")):
			return slot.substr(slot.length() - 1)
	return ""


## Walking: 0 = standing, 1 = full stride (kept for callers that don't drive the phase).
func set_walk(amount: float) -> void:
	walk_amount = amount
	if amount <= 0.001:
		walk_phase = roundf(walk_phase / PI) * PI
		_apply_walk()


func _apply_walk() -> void:
	var a := walk_amount
	var rest_y: float = pelvis.get_meta("rest_y", pelvis.position.y) if pelvis else 0.0
	var g := gait
	if airborne and g != "tracked":
		g = "winged" if g == "winged" else "hover"
	match g:
		"hover", "winged":
			# Legs tucked, body bobbing on thrusters/wings and leaning into the move.
			for leg: Dictionary in legs:
				var base: Vector3 = leg["base"]
				(leg["hip"] as Node3D).rotation_degrees.x = base.x - 20.0 * (a if airborne else 0.3)
				(leg["knee"] as Node3D).rotation_degrees.x = base.y + (25.0 if base.y >= 0.0 else -25.0) * (a if airborne else 0.3)
			if pelvis:
				pelvis.position.y = rest_y + (0.04 + 0.025 * sin(_idle_t * 3.0)) * (1.0 if airborne or g == "hover" else 0.0)
				pelvis.rotation_degrees.x = -10.0 * a
			return
		"tracked":
			if pelvis:
				pelvis.position.y = rest_y + 0.006 * sin(walk_phase * 4.0) * a
			return
	# Legged gaits: which legs move together.
	var n := legs.size()
	for i in range(n):
		var leg: Dictionary = legs[i]
		var offset := 0.0
		match g:
			"quadruped":
				offset = PI if i in [1, 2] else 0.0  # diagonal pairs
			"hexapod":
				offset = PI if i % 2 == 1 else 0.0  # alternating tripods
			_:
				offset = PI if i % 2 == 1 else 0.0
		var phase := walk_phase + offset
		var base: Vector3 = leg["base"]
		var swing := sin(phase)
		var lift := maxf(0.0, sin(phase))
		var hip_amp := 24.0 if g != "digitigrade" else 18.0
		(leg["hip"] as Node3D).rotation_degrees.x = base.x + swing * hip_amp * a
		var bend := 1.0 if base.y <= 0.0 else -1.0
		(leg["knee"] as Node3D).rotation_degrees.x = base.y - lift * 38.0 * a * bend
		(leg["ankle"] as Node3D).rotation_degrees.x = base.z + lift * 12.0 * a * bend
	if pelvis:
		pelvis.position.y = rest_y + absf(sin(walk_phase)) * 0.018 * a
		pelvis.rotation_degrees.z = sin(walk_phase) * 2.0 * a


## Raises an arm to point its weapon at a world position (or lowers it with `on = false`).
func aim_arm(side: String, target: Vector3, on: bool = true) -> void:
	var arm: Dictionary = arms.get(side, {})
	if arm.is_empty():
		return
	var shoulder: Node3D = arm["shoulder"]
	var elbow: Node3D = arm["elbow"]
	if not on:
		shoulder.rotation_degrees = arm.get("rest_shoulder", Vector3.ZERO)
		elbow.rotation_degrees = arm.get("rest_elbow", Vector3.ZERO)
		return
	# Swing the whole arm forward so the forearm points at the target.
	var local := shoulder.get_parent_node_3d().to_local(target) - shoulder.position
	var pitch := rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length()))
	shoulder.rotation_degrees = Vector3(90.0 + pitch, 0, 0)
	elbow.rotation_degrees = Vector3.ZERO
