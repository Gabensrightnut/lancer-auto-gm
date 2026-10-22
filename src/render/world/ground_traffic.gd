class_name GroundTraffic
extends Node3D
## Vehicles driving along straight streets beyond the board, in both directions (scenery).

const PER_LANE := 5
const SPEED := Vector2(2.0, 4.5)

var _cars: Array = []  # [node, start, dir, length, speed, offset, side]
var _t := 0.0


## lanes: [[start: Vector3, dir: Vector3, length: float]]; kinds: vehicle kinds.
func setup(lanes: Array, kinds: Array) -> void:
	var mat := WorldDressing.foliage_material(0.0, 1.0, 0.0)
	var i := 0
	for lane: Array in lanes:
		for k in range(PER_LANE):
			i += 1
			var kind: String = kinds[int(WorldRand.f("gt", i) * kinds.size()) % kinds.size()]
			var mi := MeshInstance3D.new()
			mi.mesh = Vehicles.mesh(kind, Vehicles.paint_for(kind, WorldRand.f("gtp", i)))
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.scale = Vector3.ONE * 1.6  # streets out there are seen from afar
			add_child(mi)
			var side := 1.0 if k % 2 == 0 else -1.0
			_cars.append([mi, lane[0], lane[1], float(lane[2]), lerpf(SPEED.x, SPEED.y, WorldRand.f("gts", i)),
				WorldRand.f("gto", i) * float(lane[2]), side])
	_update()


func _process(delta: float) -> void:
	_t += delta
	_update()


func _update() -> void:
	for c: Array in _cars:
		var mi: MeshInstance3D = c[0]
		var dir: Vector3 = c[2]
		var length: float = c[3]
		var side: float = c[6]
		var s := fposmod(float(c[5]) + _t * float(c[4]) * side, length)
		var lateral := Vector3(-dir.z, 0, dir.x) * 0.45 * side
		mi.position = (c[1] as Vector3) + dir * s + lateral
		mi.rotation.y = atan2(-dir.z * side, dir.x * side)
