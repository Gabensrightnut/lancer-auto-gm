class_name TrafficLight
extends Node3D
## A three-lamp traffic light head that cycles green, amber, red (scenery).

const CYCLE := [["green", 5.0], ["amber", 1.5], ["red", 5.0]]
const COLORS := {"red": Color(1.0, 0.15, 0.1), "amber": Color(1.0, 0.7, 0.1), "green": Color(0.2, 1.0, 0.4)}

var phase := 0.0
var _lamps := {}
var _t := 0.0


func _ready() -> void:
	var y := 0.04
	for name: String in ["red", "amber", "green"]:
		var m := MeshKit.part(self, MeshKit.sphere(0.017, 6), MeshKit.fx_material(COLORS[name], 0.2), Vector3(0, y, 0.027))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lamps[name] = m
		y -= 0.04
	_t = phase
	_apply()


func _process(delta: float) -> void:
	_t += delta
	_apply()


func _apply() -> void:
	var total := 0.0
	for c: Array in CYCLE:
		total += float(c[1])
	var at := fmod(_t, total)
	var on := "red"
	for c: Array in CYCLE:
		if at < float(c[1]):
			on = c[0]
			break
		at -= float(c[1])
	for name: String in _lamps:
		(_lamps[name] as MeshInstance3D).material_override = MeshKit.fx_material(COLORS[name], 3.0 if name == on else 0.15)
