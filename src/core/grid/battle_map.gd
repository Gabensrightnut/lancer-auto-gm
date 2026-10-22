class_name BattleMap
extends RefCounted
## The battlefield: which cells exist, how tall the ground is in each, and terrain tags.
## Terrain is stacked levels (like blocks): `ground` is how many levels of solid
## terrain the column has; a character standing there has its base at that level.
##
## Cover, line of sight and movement cost are rules questions and live in the rules
## engine; this class only stores the terrain and answers geometry questions.

## Terrain tags used in `Column.tags`. Rules meanings come from the book.
const TAG_DIFFICULT := "difficult"
const TAG_DANGEROUS := "dangerous"
const TAG_IMPASSABLE := "impassable"
const TAG_DESTRUCTIBLE := "destructible"


class Column:
	## Solid levels in this cell (0 = flat ground).
	var ground: int = 0
	## Optional open space under an overhang/bridge: levels [gap_bottom, gap_top) are empty
	## even though `ground` is higher. gap_top == 0 means no gap.
	var gap_bottom: int = 0
	var gap_top: int = 0
	var tags: PackedStringArray = PackedStringArray()

	func has_tag(tag: String) -> bool:
		return tags.has(tag)

	func to_dict() -> Dictionary:
		var d := {"ground": ground}
		if gap_top > 0:
			d["gap"] = [gap_bottom, gap_top]
		if not tags.is_empty():
			d["tags"] = Array(tags)
		return d

	static func from_dict(d: Dictionary) -> Column:
		var c := Column.new()
		c.ground = int(d.get("ground", 0))
		if d.has("gap"):
			c.gap_bottom = int(d["gap"][0])
			c.gap_top = int(d["gap"][1])
		c.tags = PackedStringArray(d.get("tags", []))
		return c


var grid: GridLayout
var _columns: Dictionary = {}  # Vector2i -> Column


func _init(grid_shape: GridLayout.Shape = GridLayout.Shape.HEX) -> void:
	grid = GridLayout.create(grid_shape)


func set_column(cell: Vector2i, ground: int, tags: PackedStringArray = PackedStringArray()) -> Column:
	var c := Column.new()
	c.ground = ground
	c.tags = tags
	_columns[cell] = c
	return c


func has_cell(cell: Vector2i) -> bool:
	return _columns.has(cell)


func column(cell: Vector2i) -> Column:
	return _columns.get(cell)


func ground_height(cell: Vector2i) -> int:
	var c: Column = _columns.get(cell)
	return c.ground if c else 0


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_columns.keys())
	return out


## Ground heights under every cell of a footprint, or an empty array if any cell is
## off the map. Whether uneven ground is standable is a rules decision.
func footprint_ground(anchor: Vector2i, size: float) -> Array[int]:
	var out: Array[int] = []
	for cell in grid.footprint(anchor, size):
		if not has_cell(cell):
			return []
		out.append(ground_height(cell))
	return out


func to_dict() -> Dictionary:
	var cols := {}
	for cell: Vector2i in _columns:
		cols["%d,%d" % [cell.x, cell.y]] = (_columns[cell] as Column).to_dict()
	return {"shape": GridLayout.Shape.keys()[grid.shape], "columns": cols}


static func from_dict(d: Dictionary) -> BattleMap:
	var m := BattleMap.new(GridLayout.Shape[d.get("shape", "HEX")])
	var cols: Dictionary = d.get("columns", {})
	for key: String in cols:
		var parts := key.split(",")
		m._columns[Vector2i(int(parts[0]), int(parts[1]))] = Column.from_dict(cols[key])
	return m


## A flat map filling a rough rectangle, for tests and quick setups.
static func flat(grid_shape: GridLayout.Shape, width: int, height: int) -> BattleMap:
	var m := BattleMap.new(grid_shape)
	for row in range(height):
		for col in range(width):
			var cell := Vector2i(col, row)
			if grid_shape == GridLayout.Shape.HEX:
				# Offset rows so the hex map is a rectangle, not a rhombus.
				cell = Vector2i(col - (row >> 1), row)
			m.set_column(cell, 0)
	return m
