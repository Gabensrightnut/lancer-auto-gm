class_name Spinner
extends Node3D
## Simple scenery motion: spin around an axis (windmills, monorail ring) or climb up and
## down a range (space elevator pods).

var axis := Vector3.UP
var speed := 1.0
## "spin" or "climb".
var mode := "spin"
var climb_range := Vector2(0.0, 100.0)
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if mode == "climb":
		var span := climb_range.y - climb_range.x
		position.y = climb_range.x + pingpong(_t * speed, span)
	else:
		rotate(axis.normalized(), speed * delta)
