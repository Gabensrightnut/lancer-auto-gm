class_name DemoMap
extends RefCounted
## A hand-laid urban ruins board for the visual demo. The layout is written in world
## coordinates, so the same streets and buildings come out on a hex or a square grid.

const WIDTH := 18
const HEIGHT := 14

## Rectangles in world space: [x0, z0, x1, z1, ground, tags, gap_bottom, gap_top].
const BLOCKS := [
	# Tall ruined buildings.
	[0.0, 0.0, 3.6, 3.2, 4, [], 0, 0],
	[13.0, 8.5, 17.5, 12.0, 3, [], 0, 0],
	[14.5, 0.0, 17.5, 3.0, 5, [], 0, 0],
	# Terraced block stepping up to a rooftop.
	[5.5, 0.0, 9.0, 1.8, 2, [], 0, 0],
	[5.5, 1.8, 9.0, 2.8, 1, [], 0, 0],
	# Overpass: a bridge deck with open space underneath (2 levels clear).
	[9.0, 0.0, 10.6, 9.0, 3, [], 0, 2],
	[9.0, 0.0, 10.6, 1.6, 3, [], 0, 0],
	# Low walls and slabs (hard cover for small mechs).
	[4.0, 6.5, 6.5, 7.2, 1, [], 0, 0],
	[11.5, 4.5, 12.4, 6.5, 1, [], 0, 0],
	[1.0, 9.5, 2.0, 11.8, 1, [], 0, 0],
	[6.5, 10.0, 8.5, 10.8, 1, [], 0, 0],
	# Rubble field (difficult terrain).
	[2.5, 5.0, 4.5, 7.5, 0, ["difficult"], 0, 0],
	[12.5, 6.8, 14.0, 8.2, 0, ["difficult"], 0, 0],
	# Burning fuel spill (dangerous terrain).
	[5.0, 4.0, 6.6, 5.2, 0, ["dangerous"], 0, 0],
]


static func build(shape: GridLayout.Shape) -> BattleMap:
	var map := BattleMap.flat(shape, WIDTH, HEIGHT)
	for cell in map.cells():
		var p := map.grid.to_world(cell)
		for b: Array in BLOCKS:
			if p.x >= b[0] and p.x < b[2] and p.z >= b[1] and p.z < b[3]:
				var col := map.set_column(cell, int(b[4]), PackedStringArray(b[5]))
				col.gap_bottom = int(b[6])
				col.gap_top = int(b[7])
	return map


## The cell nearest a world-space point (for placing demo units).
static func cell_at(map: BattleMap, x: float, z: float) -> Vector2i:
	return map.grid.from_world(Vector3(x, 0, z))
