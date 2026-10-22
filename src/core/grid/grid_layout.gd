class_name GridLayout
extends RefCounted
## Grid geometry shared by rules, AI, rendering and networking.
## Nothing outside src/core/grid/ may assume hex or square: always go through this API.
##
## Cells are Vector2i on the ground plane. Height is a separate integer "level"
## (1 level = 1 space tall, the same size as 1 grid space).

enum Shape { HEX, SQUARE }

## World units per grid space (center to center).
const SPACE := 1.0
## World units per height level. Same as SPACE so 1 space up = 1 space across.
const LEVEL_HEIGHT := 1.0

var shape: Shape


static func create(grid_shape: Shape) -> GridLayout:
	match grid_shape:
		Shape.HEX:
			return HexGrid.new()
		_:
			return SquareGrid.new()


## Cells sharing an edge (or corner, where the rules count it as adjacent).
func neighbors(_cell: Vector2i) -> Array[Vector2i]:
	push_error("GridLayout.neighbors not implemented")
	return []


## Distance in spaces, as the rules measure it on the ground plane.
func distance(_a: Vector2i, _b: Vector2i) -> int:
	push_error("GridLayout.distance not implemented")
	return 0


## Cells on the straight line from a to b, both ends included, in order.
func line(_a: Vector2i, _b: Vector2i) -> Array[Vector2i]:
	push_error("GridLayout.line not implemented")
	return []


## Center of a cell's floor at the given height level, in world space.
func to_world(_cell: Vector2i, _level: int = 0) -> Vector3:
	push_error("GridLayout.to_world not implemented")
	return Vector3.ZERO


## Cell under a world position (height ignored).
func from_world(_pos: Vector3) -> Vector2i:
	push_error("GridLayout.from_world not implemented")
	return Vector2i.ZERO


## Cells a character of `size` occupies when anchored at `anchor`.
## Size 1/2 and 1 both occupy one space (rules glossary: SIZE).
func footprint(_anchor: Vector2i, _size: float) -> Array[Vector2i]:
	push_error("GridLayout.footprint not implemented")
	return []


## All cells within `radius` spaces of `center`, including the center.
func cells_within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-radius * 2, radius * 2 + 1):
		for dx in range(-radius * 2, radius * 2 + 1):
			var c := center + Vector2i(dx, dy)
			if distance(center, c) <= radius:
				out.append(c)
	return out


## Shortest distance between two footprints (0 if they overlap).
func footprint_distance(a: Array[Vector2i], b: Array[Vector2i]) -> int:
	var best := 1 << 30
	for ca in a:
		for cb in b:
			best = mini(best, distance(ca, cb))
	return best


## Number of whole spaces a character occupies along each side.
static func spaces_per_side(size: float) -> int:
	return maxi(1, ceili(size))
