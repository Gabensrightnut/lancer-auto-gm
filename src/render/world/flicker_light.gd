class_name FlickerLight
extends OmniLight3D
## A fire-lit light that flickers (flames, burning windows, torches, neon buzz).

var base_energy := 1.5
var speed := 1.0
var depth := 0.35
var _t := 0.0


func _ready() -> void:
	_t = fposmod(position.x * 1.7 + position.z * 3.1, 10.0)
	light_energy = base_energy


func _process(delta: float) -> void:
	_t += delta * speed
	var f := sin(_t * 9.0) * 0.5 + sin(_t * 23.0 + 1.3) * 0.3 + sin(_t * 41.0 + 0.7) * 0.2
	light_energy = base_energy * (1.0 + depth * f)
