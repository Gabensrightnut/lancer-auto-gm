class_name Lightning
extends DirectionalLight3D
## Storm lightning: a light that is dark most of the time and flickers bright for a moment at
## random intervals (scenery only).

var strength := 1.0
var _wait := 2.0
var _flash := 0.0


func _ready() -> void:
	light_color = Color(0.8, 0.85, 1.0)
	light_energy = 0.0
	shadow_enabled = false
	rotation_degrees = Vector3(-60, randf() * 360.0, 0)
	_wait = randf_range(2.0, 6.0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		light_energy = strength * (2.5 if fmod(_flash, 0.12) > 0.05 else 0.6) * clampf(_flash / 0.4, 0.0, 1.0)
		if _flash <= 0.0:
			light_energy = 0.0
			_wait = randf_range(3.0, 9.0)
		return
	_wait -= delta
	if _wait <= 0.0:
		_flash = randf_range(0.25, 0.45)
		rotation_degrees.y = randf() * 360.0
