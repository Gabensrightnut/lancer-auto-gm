class_name SquareGrid
extends GridLayout
## Square grid, Vector2i(x, y).
##
## PROVISIONAL (to confirm against the book, see docs/RULES_TODO.md): diagonal steps
## count as 1 space, so distance is Chebyshev and all 8 surrounding squares are adjacent.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


func _init() -> void:
	shape = GridLayout.Shape.SQUARE


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(cell + d)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	var start := Vector2(a.x + 1e-6, a.y + 1e-6)
	var end := Vector2(b)
	for i in range(n + 1):
		var p := start.lerp(end, float(i) / n)
		out.append(Vector2i(roundi(p.x), roundi(p.y)))
	return out


func to_world(cell: Vector2i, level: int = 0) -> Vector3:
	return Vector3(cell.x * GridLayout.SPACE, level * GridLayout.LEVEL_HEIGHT, cell.y * GridLayout.SPACE)


func from_world(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / GridLayout.SPACE), roundi(pos.z / GridLayout.SPACE))


## Size N occupies an N x N block with `anchor` as its top-left (min x, min y) square.
func footprint(anchor: Vector2i, size: float) -> Array[Vector2i]:
	var n := GridLayout.spaces_per_side(size)
	var out: Array[Vector2i] = []
	for y in range(n):
		for x in range(n):
			out.append(anchor + Vector2i(x, y))
	return out
