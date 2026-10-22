class_name SkyTraffic
extends Node3D
## Flying traffic over a megacity: streams of small craft with glowing running lights moving
## along straight sky lanes high above and around the board (never low over it).

const LANES := 10
const PER_LANE := 9

var _lanes: Array = []  # [start, dir, length, speed]
var _mm: MultiMesh
var _glow: MultiMesh
var _t := 0.0


func setup(b: Rect2, colors: Array) -> void:
	var c := Vector3(b.get_center().x, 0, b.get_center().y)
	var r := maxf(b.size.x, b.size.y) * 0.5
	for i in range(LANES):
		var a := WorldRand.f("lane", i) * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var off := (WorldRand.f("lane_off", i) - 0.5) * 2.0 * (r + 40.0)
		var h := 16.0 + 26.0 * WorldRand.f("lane_h", i)
		var length := 2.0 * (r + 120.0)
		_lanes.append([c + side * off - dir * length * 0.5 + Vector3.UP * h, dir, length, (2.5 + 3.0 * WorldRand.f("lane_s", i)) * (1.0 if i % 2 == 0 else 1.3)])
	var body := MeshKit.chamfer_box(Vector3(0.35, 0.1, 0.16), 0.03)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = body
	_mm.instance_count = LANES * PER_LANE
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = MeshKit.mech_material(Color(0.1, 0.1, 0.12), 0.7, 0.3, Color.BLACK, false)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_glow = MultiMesh.new()
	_glow.transform_format = MultiMesh.TRANSFORM_3D
	_glow.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = Fx.soft_texture()
	m.vertex_color_use_as_albedo = true
	q.material = m
	_glow.mesh = q
	_glow.instance_count = LANES * PER_LANE
	for i in range(_glow.instance_count):
		var col := WorldStyle.color(colors[i % colors.size()]) * 2.5
		_glow.set_instance_color(i, col)
	var gi := MultiMeshInstance3D.new()
	gi.multimesh = _glow
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	_update()


func _process(delta: float) -> void:
	_t += delta
	_update()


func _update() -> void:
	var k := 0
	for i in range(_lanes.size()):
		var lane: Array = _lanes[i]
		var start: Vector3 = lane[0]
		var dir: Vector3 = lane[1]
		var length: float = lane[2]
		var speed: float = lane[3]
		var basis := Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, PI * 0.5)
		for j in range(PER_LANE):
			var s := fposmod(_t * speed + length * float(j) / PER_LANE + WorldRand.f("car", i * 100 + j) * 6.0, length)
			var p := start + dir * s + Vector3.UP * sin(s * 0.05 + j) * 0.4
			_mm.set_instance_transform(k, Transform3D(basis, p))
			_glow.set_instance_transform(k, Transform3D(Basis(), p))
			k += 1
