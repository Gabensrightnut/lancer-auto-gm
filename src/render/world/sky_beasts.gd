class_name SkyBeasts
extends Node3D
## Things moving in the distance: a few colossal translucent creatures drifting slowly high
## over the far horizon, glowing faintly, trailing long tendrils. Scenery only.

const COUNT := 4

var _beasts: Array = []  # [node, center, radius, speed, phase, height]
var _t := 0.0


func setup(b: Rect2, glow: Color) -> void:
	var c := Vector3(b.get_center().x, 0, b.get_center().y)
	var r0 := maxf(b.size.x, b.size.y) * 0.5
	var body_mat := StandardMaterial3D.new()
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.albedo_color = Color(glow.r * 0.3, glow.g * 0.3, glow.b * 0.35, 0.35)
	body_mat.emission_enabled = true
	body_mat.emission = glow * 0.6
	body_mat.rim_enabled = true
	body_mat.rim = 1.0
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tendril_mat := MeshKit.fx_material(glow * 0.6, 0.8)
	for i in range(COUNT):
		var node := Node3D.new()
		add_child(node)
		var size := 10.0 + 9.0 * WorldRand.f("beast", i)
		var bell := MeshKit.part(node, SmoothKit.blob(Vector3(size, size * 0.55, size), 0.8, 1.0, 0.0, 20), body_mat)
		bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in range(9):
			var a := TAU * k / 9.0
			var start := Vector3(cos(a), 0, sin(a)) * size * 0.35
			var pts := []
			for j in range(6):
				pts.append(start + Vector3(sin(j * 0.9 + a) * size * 0.08, -j * size * 0.45, cos(j * 0.7 + a) * size * 0.08))
			var radii := []
			for j in range(6):
				radii.append(size * lerpf(0.03, 0.005, j / 5.0))
			var tendril := MeshKit.part(node, SmoothKit.tube(pts, radii, 5), tendril_mat)
			tendril.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beasts.append([node, c, r0 + 110.0 + 60.0 * WorldRand.f("beast_r", i), 0.004 + 0.004 * WorldRand.f("beast_s", i),
			-PI * 0.5 + (WorldRand.f("beast_a", i) - 0.5) * 2.2, 22.0 + 25.0 * WorldRand.f("beast_h", i)])
	_update()


func _process(delta: float) -> void:
	_t += delta
	_update()


func _update() -> void:
	for e: Array in _beasts:
		var node: Node3D = e[0]
		var a: float = e[4] + _t * e[3]
		node.position = (e[1] as Vector3) + Vector3(cos(a), 0, sin(a)) * float(e[2]) + Vector3.UP * (float(e[5]) + sin(_t * 0.3 + a * 5.0) * 2.0)
		node.rotation.y = -a
		var pulse := 1.0 + 0.04 * sin(_t * 0.8 + a * 7.0)
		node.scale = Vector3(pulse, 1.0 / pulse, pulse)
