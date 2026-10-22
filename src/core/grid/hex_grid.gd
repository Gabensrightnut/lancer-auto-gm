class_name HexGrid
extends GridLayout
## Pointy-top hexes in axial coordinates: Vector2i(q, r).

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## Hex circumradius so that adjacent centers are SPACE apart.
var _radius := GridLayout.SPACE / sqrt(3.0)


func _init() -> void:
	shape = GridLayout.Shape.HEX


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(cell + d)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	# Nudge so lines running exactly along hex edges pick a side consistently.
	var ac := Vector3(a.x + 1e-6, a.y + 1e-6, -a.x - a.y - 2e-6)
	var bc := Vector3(b.x, b.y, -b.x - b.y)
	for i in range(n + 1):
		out.append(_cube_round(ac.lerp(bc, float(i) / n)))
	return out


func to_world(cell: Vector2i, level: int = 0) -> Vector3:
	var x := _radius * sqrt(3.0) * (cell.x + cell.y / 2.0)
	var z := _radius * 1.5 * cell.y
	return Vector3(x, level * GridLayout.LEVEL_HEIGHT, z)


func from_world(pos: Vector3) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * pos.x - pos.z / 3.0) / _radius
	var r := (2.0 / 3.0 * pos.z) / _radius
	return _cube_round(Vector3(q, r, -q - r))


## PROVISIONAL (to confirm against the book / Lancer Tactics, see docs/RULES_TODO.md):
## Size 2 = 3-hex triangle, Size 3 = 7-hex flower.
func footprint(anchor: Vector2i, size: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = [anchor]
	match GridLayout.spaces_per_side(size):
		1:
			pass
		2:
			out.append(anchor + DIRECTIONS[0])
			out.append(anchor + DIRECTIONS[5])
		_:
			for d in DIRECTIONS:
				out.append(anchor + d)
	return out


func _cube_round(c: Vector3) -> Vector2i:
	var rq := roundf(c.x)
	var rr := roundf(c.y)
	var rs := roundf(c.z)
	var dq := absf(rq - c.x)
	var dr := absf(rr - c.y)
	var ds := absf(rs - c.z)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))
