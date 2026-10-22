class_name HeadLook
extends SkeletonModifier3D
## Turns a person's head toward a point after the animation has posed it (talking to
## someone, watching a target). Limited to a natural range and eased in and out.

var bone := "head"
## World-space point to look at, or null to look ahead.
var target: Variant = null
var max_yaw := deg_to_rad(65.0)
var max_pitch := deg_to_rad(30.0)
var _amount := 0.0
var _yaw := 0.0
var _pitch := 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var i := sk.find_bone(bone)
	if i < 0:
		return
	var want_yaw := 0.0
	var want_pitch := 0.0
	var on := target is Vector3
	if on:
		# The target in skeleton space; the figure faces -Z.
		var local: Vector3 = sk.global_transform.affine_inverse() * (target as Vector3)
		var head := sk.get_bone_global_pose(i).origin
		var d := local - head
		want_yaw = clampf(atan2(-d.x, -d.z), -max_yaw, max_yaw)
		want_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -max_pitch, max_pitch)
	var k := clampf(get_process_delta_time() * 6.0, 0.0, 1.0) if is_inside_tree() else 1.0
	_amount = lerpf(_amount, 1.0 if on else 0.0, k)
	_yaw = lerpf(_yaw, want_yaw, k)
	_pitch = lerpf(_pitch, want_pitch, k)
	if _amount < 0.01:
		return
	var pose := sk.get_bone_global_pose(i)
	var turn := Basis(Vector3.UP, _yaw * _amount) * Basis(Vector3.RIGHT, _pitch * _amount)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(i, pose)
