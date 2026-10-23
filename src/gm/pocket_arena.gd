class_name PocketArena
extends RefCounted
## A small sealed-off arena for split-vote fights (net's PvpBattle): about 10x10 (12x12 for four
## or more mechs) in the local look, a little cover, mirrored so both sides get the same ground.
## Not part of any area.
##
##   PocketArena.build(seed, {landscape, culture, size, shape, mechs}) ->
##     {map, kit, deployment: {players: [[x, y]], enemies: [[x, y]]}, w, h}


static func build(seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var shape := GridLayout.Shape.SQUARE if str(opts.get("shape", "hex")) == "square" else GridLayout.Shape.HEX
	var size := int(opts.get("size", 12 if int(opts.get("mechs", 2)) >= 4 else 10))
	size = clampi(size, 8, 16)
	var landscape := str(opts.get("landscape", "grassy_hills"))
	var culture := WorldKits.culture_id(str(opts.get("culture", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "arena"])
	var map := BattleMap.flat(shape, size, size)
	var cover: Array = TerrainGen.cover_tags(landscape)
	var woods := landscape in ["grassy_hills", "autumn_forest", "jungle", "toxic_swamp", "alien_wilds"]
	# Cover in the middle rows only (the ends are where each side deploys), mirrored through the
	# centre: a few hard blocks (one level) and, where the land has them, a stand of trees.
	var placed := 0
	var guard := 0
	while placed < 3 and guard < 60:
		guard += 1
		var c := rng.randi_range(1, size - 2)
		var r := rng.randi_range(3, size / 2 - 1)
		var a := SitrepLayout.cell_of(c, r, shape)
		var b := SitrepLayout.cell_of(size - 1 - c, size - 1 - r, shape)
		if not map.has_cell(a) or not map.has_cell(b) or map.ground_height(a) > 0 or map.ground_height(b) > 0:
			continue
		var tags: Array = cover if placed < 2 or not woods else [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"]
		for cell: Vector2i in [a, b]:
			var col := map.column(cell)
			if tags.has("woods"):
				col.tags = PackedStringArray(tags)
			else:
				col.ground = 1
				col.tags = PackedStringArray(tags + [BattleMap.TAG_DESTRUCTIBLE])
		placed += 1
	var players: Array = []
	var enemies: Array = []
	for c in range(1, size - 1):
		for r: int in [size - 2, size - 1]:
			var cell := SitrepLayout.cell_of(c, r, shape)
			if map.has_cell(cell):
				players.append([cell.x, cell.y])
		for r: int in [0, 1]:
			var cell := SitrepLayout.cell_of(c, r, shape)
			if map.has_cell(cell):
				enemies.append([cell.x, cell.y])
	var kit := TerrainGen.kit(landscape, culture) + "#%d" % seed_value
	return {"map": map, "kit": kit, "deployment": {Mission.PLAYERS: players, Mission.ENEMIES: enemies}, "w": size, "h": size}
