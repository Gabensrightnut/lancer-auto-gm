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

var _walk_t := 0.0
var _walk_amount := 0.0


func _process(delta: float) -> void:
	for s: Dictionary in spinners:
		(s["node"] as Node3D).rotate(s["axis"], s["speed"] * delta)
	if _walk_amount > 0.001:
		_walk_t += delta * 7.0
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


## Walking: 0 = standing, 1 = full stride.
func set_walk(amount: float) -> void:
	_walk_amount = amount
	if amount <= 0.001:
		_walk_t = 0.0
		_apply_walk()


func _apply_walk() -> void:
	for i in range(legs.size()):
		var leg: Dictionary = legs[i]
		var phase := _walk_t + (PI if i == 1 else 0.0)
		var base: Vector3 = leg["base"]
		var a := _walk_amount
		(leg["hip"] as Node3D).rotation_degrees.x = base.x + sin(phase) * 28.0 * a
		(leg["knee"] as Node3D).rotation_degrees.x = base.y - maxf(0.0, cos(phase)) * 35.0 * a * (1.0 if base.y <= 0.0 else -1.0)
		(leg["ankle"] as Node3D).rotation_degrees.x = base.z
	if pelvis:
		pelvis.position.y = pelvis.get_meta("rest_y", pelvis.position.y) + absf(sin(_walk_t)) * 0.02 * _walk_amount


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
