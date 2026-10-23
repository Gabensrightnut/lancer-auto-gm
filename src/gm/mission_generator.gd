class_name MissionGenerator
extends RefCounted
## Builds a whole mission from a seed: sitrep, battlefield, zones, deployment, both forces.
## Same seed + options = same mission. Generation uses its own seeded RNG (setup, not play);
## the battle's dice are the GameState's, seeded with the same number.
##
## Terrain: TerrainGen builds a landscape (grassy hills, desert mesas, tundra, volcanic,
## alien wilds, city) and, for some, a settlement in a culture's style (medieval, Old West,
## retro, East Asian, Union; cities also ruins, cyberpunk, burning). The renderer's kit name
## goes in mission.flavor["kit"] and the landscape's name in flavor["terrain"].
##
## opts: {"players": 1-4 (default 4), "sitrep": id (default: weighted pick),
##   "size": map width 20-60 (default: picked by squad size and sitrep, see map_size()),
##   "height": map height (default: from the width and the sitrep's shape), "shape": "hex"/"square" (default hex),
##   "landscape": TerrainGen.LANDSCAPES key, "culture": culture id (default: seeded pick),
##   "settings": GmSettings, "db": ContentDB, "npc_templates": Dictionary,
##   "town": MissionHooks.town_for(...) or "hub": story.hub (a fight in a hub's town: built
##     from its spots and culture; "at" = the spot id where the fight starts, which is put
##     in the middle of the battle band; "landscape" / "map_culture" when given),
##   "time": the story clock's period ("dawn", "day", "evening", "night"): the fight's light,
##   "region": a previous mission's flavor.region ({seed, landscape, culture, weather}): the
##     next fight in the same stretch of world keeps its look, with new terrain,
##   "boarding": {kind, map}: a boarding fight; map "docked" (two ships side by side, landscape
##     boarding), "enemy_ship" (boarding_assault) or "own_ship" (boarding_defend),
##   "map_doc": MapDoc (a saved/edited map: its terrain, kit and zones; sitrep defaults to its own),
##   "weather": a weather.json id ("clear" for none), "environments": [ids] (overrides the pick),
##   "squad": Campaign.squad() entries [{seat, pilot, mech}] to field the campaign's pilots}
## Returns {"state": GameState (setup phase, seats p1..pN + gm), "mission": Mission,
##   "fairness": MapFairness.check() after repairs, "layout": SitrepLayout output}.

static func generate(mission_seed: int, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([mission_seed, "mission"])
	var cfg := GmSettings.load_json(GmSettings.MISSIONS_FILE)
	var settings: GmSettings = opts.get("settings", GmSettings.from_preset("Standard"))
	var shape := GridLayout.Shape.SQUARE if str(opts.get("shape", "hex")) == "square" else GridLayout.Shape.HEX
	var w := 0
	var h := 0

	# A saved or edited map (MapDoc) replaces the generated battlefield.
	var doc: MapDoc = opts.get("map_doc") if opts.get("map_doc") is MapDoc else null
	if doc:
		shape = doc.map.grid.shape
		w = doc.w
		h = doc.h

	var m := Mission.new()
	m.mission_seed = mission_seed
	m.max_rounds = int(cfg.get("max_rounds", 12))
	_pick_sitrep(m, rng, cfg, str(opts.get("sitrep", doc.sitrep if doc else "")))
	if doc == null:
		var squad_size: int = (opts["squad"] as Array).size() if opts.get("squad") is Array and not (opts["squad"] as Array).is_empty() else int(opts.get("players", 4))
		var wh := map_size(rng, cfg, clampi(squad_size, 1, 4), m.sitrep_id, opts)
		w = wh.x
		h = wh.y

	var state := GameState.new(mission_seed, shape)
	# The world uses its own RNG so terrain changes never shift the rest of the mission.
	var world_rng := RandomNumberGenerator.new()
	world_rng.seed = hash([mission_seed, "world"])
	# A fight in a hub's town happens in that town: its culture, its streets and buildings.
	# opts.town (story's MissionHooks.town_for) or opts.hub (a story.hub): same fields.
	var hub: Dictionary = {}
	for key: String in ["town", "hub"]:
		if opts.get(key) is Dictionary and not (opts[key] as Dictionary).get("spots", []).is_empty():
			hub = opts[key]
			break
	var landscape := str(opts.get("landscape", ""))
	var culture := str(opts.get("culture", ""))
	# A region (the last fight's flavor.region): the same stretch of world, so its landscape,
	# culture, weather and look carry over; the terrain is new.
	var region: Dictionary = opts["region"] if opts.get("region") is Dictionary else {}
	# A boarding fight (story: opts.boarding {kind, map}): the map kind picks the ship map.
	var boarding: Dictionary = opts["boarding"] if opts.get("boarding") is Dictionary else {}
	if not boarding.is_empty():
		landscape = str(BOARDING_MAPS.get(str(boarding.get("map", "docked")), "boarding"))
		culture = ""
	# Ships and stations are cramped: their maps are smaller, by the fight-length dial.
	if doc == null and not opts.has("size") and landscape in SHIP_MAPS:
		var k := float({"short": 0.7, "standard": 0.85, "long": 1.0}.get(settings.fight_length, 0.85))
		w = maxi(24, int(round(w * k)))
		h = maxi(24, int(round(h * k)))
	if not region.is_empty():
		if landscape == "":
			landscape = str(region.get("landscape", ""))
		if culture == "":
			culture = str(region.get("culture", ""))
	if not hub.is_empty():
		culture = WorldKits.culture_id(str(hub.get("map_culture", hub.get("culture", culture))))
		if landscape == "":
			landscape = str(hub.get("landscape", ""))
		if landscape == "":
			landscape = "station" if str(hub.get("kind", "")) == "station" else str(WorldKits.HUB_LANDSCAPE.get(culture, "grassy_hills"))
	var bf: Dictionary
	var inside := _interior_kind(hub)
	if doc == null and inside != "":
		# On foot inside a hub building: the fight map is that building's own interior.
		var ib := InteriorBattle.build(inside, culture, int(hub.get("seed", 0)), shape, m.sitrep_id)
		bf = {"map": ib["map"], "layout": ib["layout"], "fairness": {"ok": true, "interior": inside},
			"world": [landscape if landscape != "" else str(WorldKits.HUB_LANDSCAPE.get(culture, "grassy_hills")), culture]}
	elif doc == null:
		bf = battlefield(rng, world_rng, m.sitrep_id, w, h, shape, landscape, culture, maxi(0, int(settings.approach) + int(settings.fight("approach", 0))), hub,
			_secondary_kind(mission_seed, m.sitrep_id, str(opts.get("secondary", "?"))))
	else:
		bf = _doc_battlefield(doc, m.sitrep_id, rng)
	state.map = bf["map"]
	var layout: Dictionary = bf["layout"]
	var fairness: Dictionary = bf["fairness"]
	var world: Array = bf["world"]
	m.deployment = layout["deployment"]
	# An ambush on the road (WorldMapGen ambush spot): the squad caught on the road through the
	# middle, the ambushers already in the cover along one flank.
	if opts.get("ambush") is Dictionary:
		m.deployment = _ambush_deployment(state.map, shape, w, h, int(opts["ambush"].get("at", [0, 0])[0]) % 2 == 0)
		m.flavor["ambush"] = (opts["ambush"] as Dictionary).duplicate(true)
		m.first_side = Mission.ENEMIES  # they sprang it
	m.zones = layout["zones"]
	if layout["first_side"] != "":
		m.first_side = layout["first_side"]

	# Names use their own RNG so changing name lists never changes the battlefield.
	var names_rng := RandomNumberGenerator.new()
	names_rng.seed = hash([mission_seed, "names"])
	var names := NameGen.new(names_rng)
	var wanted_weather := str(opts.get("weather", doc.weather if doc and doc.weather != "" else ("clear" if doc else str(region.get("weather", "?")) if region.has("weather") else "?")))
	if wanted_weather == "":
		wanted_weather = "clear"
	var weather := _pick_weather(world_rng, world[0], world[1], wanted_weather, str(opts.get("season", region.get("season", ""))))
	# The place's own look (WorldStyle.vary): the region's seed, the hub's for a town fight,
	# else one of its own.
	var place_seed := int(region.get("seed", -1))
	if place_seed < 0 and not hub.is_empty():
		place_seed = int(hub.get("seed", -1))
	if place_seed < 0:
		place_seed = hash([mission_seed, "place"]) & 0x7fffffff
	var kit := TerrainGen.kit(world[0], world[1]) + ("+" + weather if weather != "" else "")
	# The time of day (story clock: opts.time, else the region's): look only.
	var time := str(opts.get("time", region.get("time", "day")))
	if time in ["dawn", "evening", "night"]:
		kit += "~" + time
	if doc == null:
		kit += "#%d" % place_seed
	m.flavor = {"operation": names.operation(), "planet": names.planet(), "faction": names.faction(),
		"team": names.team_name(), "cargo": names.cargo(), "kit": kit,
		"terrain": TerrainGen.describe(world[0], world[1]), "weather": weather,
		"region": {"seed": place_seed, "landscape": world[0], "culture": world[1], "weather": weather}, "time": time}
	if not boarding.is_empty():
		m.flavor["boarding"] = boarding.duplicate()
	# Defend objectives (Holdout's protected object): for the mission, the AI and the HUD.
	if layout.has("protect"):
		m.flavor["protect"] = (layout["protect"] as Dictionary).duplicate()
	if layout.has("objectives"):
		m.flavor["objectives"] = (layout["objectives"] as Array).duplicate(true)
	_pick_environments(m, state, mission_seed, world[0], weather, settings, opts)
	var players := clampi(int(opts.get("players", 4)), 1, 4)
	state.seats["gm"] = {"name": "GM", "side": Mission.ENEMIES, "gm": true}
	if opts.get("squad", []) is Array and not (opts.get("squad", []) as Array).is_empty():
		_add_campaign_squad(state, m, rng, opts["squad"], opts.get("db"))
	else:
		_add_squad(state, m, rng, players, opts.get("db"), names)
	_add_enemies(state, m, rng, cfg, players, settings, opts.get("npc_templates", UnitFactory.npc_templates()))
	_setup_objectives(m, state, rng, cfg)
	m.briefing = _briefing(m, w, h, players, state)
	for o: Dictionary in m.flavor.get("objectives", []):
		if bool(o.get("secondary", false)):
			m.briefing += " Secondary (a GM objective, not the sitrep's): %s. Reward: %s. It never decides the mission." % [o["text"], o["reward_name"]]
	return {"state": state, "mission": m, "fairness": fairness, "layout": layout}


## Map width x height (columns x rows) for a mission: bigger squads get bigger maps, and
## some sitreps want more room (data/game/gm/missions.json "map_sizes"). Not always square:
## usually a little longer than wide. opts.size sets the width (opts.height the height).
## The extra room is flanking space and terrain; the approach dial keeps the deployment
## zones close (SitrepLayout).
static func map_size(rng: RandomNumberGenerator, cfg: Dictionary, players: int, sitrep_id: String, opts: Dictionary = {}) -> Vector2i:
	var sz: Dictionary = cfg.get("map_sizes", {})
	var lo := int(sz.get("min", 30))
	var hi := int(sz.get("max", 60))
	var base := float(sz.get("base", 30)) + float(sz.get("per_player", 6)) * players
	var shape: Array = (sz.get("sitreps", {}) as Dictionary).get(sitrep_id, [1.0, 1.1])
	var jitter := float(sz.get("jitter", 4))
	var w := int(round(base * float(shape[0]) + rng.randf_range(-jitter, jitter)))
	var h := int(round(base * float(shape[1]) + rng.randf_range(-jitter, jitter)))
	if opts.has("size"):
		w = int(opts["size"])
		h = int(opts.get("height", round(w * float(shape[1]) / float(shape[0]))))
	elif opts.has("height"):
		h = int(opts["height"])
	# Explicit sizes may go down to 20 (tests, skirmishes); picked sizes stay in [min, max].
	var floor_size := 20 if opts.has("size") or opts.has("height") else lo
	return Vector2i(clampi(w, floor_size, 60), clampi(h, floor_size, 60))


static func _pick_sitrep(m: Mission, rng: RandomNumberGenerator, cfg: Dictionary, wanted: String) -> void:
	var table: Dictionary = cfg.get("sitreps", {})
	var id := wanted
	if not table.has(id):
		var total := 0.0
		for k: String in table:
			total += float(table[k].get("weight", 1))
		var roll := rng.randf() * total
		for k: String in table:
			roll -= float(table[k].get("weight", 1))
			if roll <= 0.0:
				id = k
				break
		if id == "":
			id = table.keys()[0]
	m.sitrep_id = id
	m.rounds = int(table[id].get("rounds", 0))
	for s: Dictionary in _sitreps():
		if s.get("id", "") == id:
			m.sitrep_name = str(s.get("name", id))
	# Reinforcements fit fights that run until one side breaks (PROVISIONAL GM choice).
	m.allow_reinforcements = id in ["sitrep_standardcombat", "sitrep_holdout"]


static func _sitreps() -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://data/lancer-data/sitreps.json")) != OK:
		return []
	return json.data if json.data is Array else []


# --- Zones and deployment ---------------------------------------------------------------

## Map coordinates are (col, row) on a rectangle; hex maps shear rows like BattleMap.flat().
static func _cell(col: int, row: int, shape: GridLayout.Shape) -> Vector2i:
	return Vector2i(col - (row >> 1), row) if shape == GridLayout.Shape.HEX else Vector2i(col, row)


static func _rect(c0: int, r0: int, cw: int, rh: int, w: int, h: int, shape: GridLayout.Shape) -> Array:
	var out: Array = []
	for r in range(maxi(r0, 0), mini(r0 + rh, h)):
		for c in range(maxi(c0, 0), mini(c0 + cw, w)):
			var cell := _cell(c, r, shape)
			out.append([cell.x, cell.y])
	return out


## The battlefield for a sitrep: its zones (SitrepLayout), the terrain (TerrainGen), the
## sitrep's fortifications, then fairness repairs (MapFairness). `rng` lays out the zones;
## `world_rng` builds the terrain. Returns {map, layout, fairness, world: [landscape, culture]}.
static func battlefield(rng: RandomNumberGenerator, world_rng: RandomNumberGenerator, sitrep_id: String, w: int, h: int,
		shape: GridLayout.Shape, landscape: String = "", culture: String = "", approach: int = 0, hub: Dictionary = {}, secondary: String = "") -> Dictionary:
	var layout := SitrepLayout.layout(sitrep_id, w, h, shape, rng, approach)
	if secondary != "":
		_add_secondary(layout, secondary, w, h, shape, hash([w, h, sitrep_id, secondary]))
	var blocked := {}  # cells kept clear of rocks and woods (deployment, zones, routes)
	for list: Array in (layout["deployment"] as Dictionary).values() + (layout["zones"] as Dictionary).values() + [layout["clear"]]:
		for c: Array in list:
			blocked[Vector2i(c[0], c[1])] = true
	var world := TerrainGen.pick(world_rng, landscape, culture)
	var map := TerrainGen.generate(world_rng, w, h, shape, blocked, world[0], world[1], hub)
	if sitrep_id in ["sitrep_holdout", "sitrep_gauntlet"]:
		_fortify(map, rng, layout["zones"]["zone"], shape)
	if layout.has("protect"):
		_place_protected(map, layout["protect"])
	var fairness := MapFairness.repair(map, layout, w, h, shape, blocked, world_rng, TerrainGen.cover_tags(world[0]))
	return {"map": map, "layout": layout, "fairness": fairness, "world": world}


## The battlefield from a MapDoc: its own terrain and zones. If the mission's sitrep differs
## from the one the map was laid out for, the zones are laid out afresh for it.
static func _doc_battlefield(doc: MapDoc, sitrep_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var layout := doc.layout()
	if sitrep_id != doc.sitrep:
		layout = SitrepLayout.layout(sitrep_id, doc.w, doc.h, doc.map.grid.shape, rng)
	var map := BattleMap.from_dict(doc.map.to_dict())
	return {"map": map, "layout": layout, "fairness": MapFairness.check(map, layout, doc.h), "world": [doc.landscape, doc.culture]}


# --- Terrain (TerrainGen) -------------------------------------------------------------

## A map to explore in real time at mech scale (WorldSession / NetRoom areas: exploring, and
## fights that start right there on the same ground). opts: "hub" (story.hub: its town at mech
## scale in the middle), "region" (a flavor.region: landscape, culture, weather and look),
## "landscape", "culture", "weather", "size" (default 60), "shape" ("hex"/"square"),
## "place" (where on the region the area lies: "town" (the hub's town, or a settlement),
## "outskirts" (a village and its fields), "road" or "wilds" (open country on the road)),
## "at" ([x, y]: the area's place on the region's grid of areas).
## Neighbouring areas share their edge: the band along it is built from the region's seed and
## that edge's place, so the ground (heights, woods, the road crossing it) continues across.
## Every area has roads along its middle row and column out to all four edges and a level band
## along the edges, so the areas of a region join up: walk off the east edge and come in on the
## next area's west edge on the same road. Returns {map, kit, region, name, center, entries:
## {west, east, north, south: cell}}.
static func area(area_seed: int, opts: Dictionary = {}) -> Dictionary:
	var shape := GridLayout.Shape.SQUARE if str(opts.get("shape", "hex")) == "square" else GridLayout.Shape.HEX
	var size := clampi(int(opts.get("size", 60)), 30, 80)
	var region: Dictionary = opts["region"] if opts.get("region") is Dictionary else {}
	var hub: Dictionary = opts["hub"] if opts.get("hub") is Dictionary and not (opts["hub"] as Dictionary).get("spots", []).is_empty() else {}
	var landscape := str(opts.get("landscape", region.get("landscape", "")))
	var culture := str(opts.get("culture", region.get("culture", "")))
	if not hub.is_empty():
		culture = WorldKits.culture_id(str(hub.get("map_culture", hub.get("culture", culture))))
		if landscape == "":
			landscape = str(hub.get("landscape", ""))
		if landscape == "":
			landscape = str(WorldKits.HUB_LANDSCAPE.get(culture, "grassy_hills"))
		hub = hub.duplicate()
		hub.erase("at")  # the town stands in the middle of its area
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([area_seed, "area"])
	var world := TerrainGen.pick(rng, landscape, culture)
	var place_kind := str(opts.get("place", "town" if not hub.is_empty() else "outskirts"))
	var at: Array = opts.get("at", [0, 0])
	var ax := int(at[0])
	var ay := int(at[1])
	var region_seed := int(region.get("seed", hub.get("seed", area_seed)))
	var edges := {
		"west": _edge_profile(region_seed, "v|%d|%d" % [ax, ay], size, world[0]),
		"east": _edge_profile(region_seed, "v|%d|%d" % [ax + 1, ay], size, world[0]),
		"north": _edge_profile(region_seed, "h|%d|%d" % [ax, ay], size, world[0]),
		"south": _edge_profile(region_seed, "h|%d|%d" % [ax, ay + 1], size, world[0]),
	}
	# What the area holds by where it is: the town, a village at the outskirts, open country.
	var gen_culture: String = world[1]
	var gen_hub := hub if place_kind == "town" else {}
	if place_kind in ["road", "wilds"]:
		gen_culture = ""
	# A place on the world map (farm, wreck, outpost, landmark, port, pad, camp, mine, ruins,
	# relay): its own feature instead of a village, in the region's materials.
	var feature := place_kind if place_kind in TerrainGen.FEATURES else ""
	# The biggest printer here (Core p.377): the region passes its place's; otherwise a town or
	# hub has a schedule 3 printworks, a village a schedule 1 unit, outposts and ports 2, pads 1.
	var printer := int(opts.get("printer_schedule", PLACE_PRINTER.get(place_kind, 0)))
	# Where a ride stops here (RegionMap stations): drawn beside the road.
	var stops: Array = opts.get("stations", [])
	var map := TerrainGen.generate(rng, size, size, shape, {}, world[0], gen_culture, gen_hub, true, edges, feature, printer, stops)
	var weather := str(opts.get("weather", region.get("weather", "?")))
	weather = _pick_weather(rng, world[0], world[1], weather if weather != "" else "clear", str(opts.get("season", region.get("season", ""))))
	var place := int(region.get("seed", hub.get("seed", hash([area_seed, "place"]) & 0x7fffffff)))
	var time := str(opts.get("time", region.get("time", "day")))
	var kit := TerrainGen.kit(world[0], world[1]) + ("+" + weather if weather != "" else "") + ("~" + time if time in ["dawn", "evening", "night"] else "") + "#%d" % place
	var cell := func(c: int, r: int) -> Array:
		return [c - (r >> 1), r] if shape == GridLayout.Shape.HEX else [c, r]
	var safe := _safe_points(map, place_kind, gen_hub, region_seed, ax, ay, size, shape)
	var sched := 0
	for c in map.cells():
		for t in map.column(c).tags:
			if t.begins_with("printer_schedule_"):
				sched = maxi(sched, int(t.trim_prefix("printer_schedule_")))
	for sp: Dictionary in safe:
		sp["printer_schedule"] = sched
	# Story's contract: safe_point (a secure place for Full Repairs, Core p.82), repair "bay" or
	# "rig", repair_bay = where it stands (world x, z).
	var flat := {"safe_point": not safe.is_empty()}
	if not safe.is_empty():
		var first: Dictionary = safe[0]
		flat["repair"] = "rig" if str(first["kind"]) in ["field_rig", "camp"] else "bay"
		var wp := map.grid.to_world(Vector2i(first["cell"][0], first["cell"][1]))
		flat["repair_bay"] = [wp.x, wp.z]
	var result := {"map": map, "kit": kit, "name": TerrainGen.describe(world[0], world[1]), "place": place_kind, "at": [ax, ay], "safe_points": safe,
		"printer_schedule": sched, "stations": _stations(map),
		"region": {"seed": place, "landscape": world[0], "culture": world[1], "weather": weather},
		"center": cell.call(size / 2, size / 2),
		"entries": {"west": cell.call(0, size / 2), "east": cell.call(size - 1, size / 2), "north": cell.call(size / 2, 0), "south": cell.call(size / 2, size - 1)}}
	result.merge(flat)
	return result


## Where to board each ride in the area: [{kind, cell [x, y]}].
static func _stations(map: BattleMap) -> Array:
	var out: Array = []
	for c in map.cells():
		var col := map.column(c)
		if not col.has_tag("station_stop"):
			continue
		for t in col.tags:
			if t.begins_with("station_") and t != "station_stop":
				out.append({"kind": t.trim_prefix("station_"), "cell": [c.x, c.y]})
	return out


## The biggest printer each kind of place has when the region doesn't say (Core p.377).
const PLACE_PRINTER := {"town": 3, "outskirts": 1, "outpost": 2, "port": 2, "pad": 1}


## Where the squad can make Full Repairs (Core p.82: ten hours in a secure location): the
## town's repair bay or printer (by its door), a place's own printer, or, out in the country, a
## field repair rig by the road in about one area in three (spaced by the region's seed so most
## jobs have one within an area or two). [{cell [x, y], kind "repair_bay" | "printer" |
## "field_rig", spot?, printer_schedule}]: printer_schedule is the biggest printer at the place
## (0 none; 1 prints up to Size 1, 2 up to Size 2, 3 up to Size 3: Core p.377).
static func _safe_points(map: BattleMap, place: String, hub: Dictionary, region_seed: int, ax: int, ay: int, size: int, shape: GridLayout.Shape) -> Array:
	var out: Array = []
	if not hub.is_empty():
		for spot: Dictionary in hub.get("spots", []):
			var kind := str(spot.get("kind", ""))
			if not kind in ["workshop", "printer"]:
				continue
			for c in map.cells():
				if map.column(c).has_tag("door_" + str(spot.get("id", kind))):
					map.column(c).tags.append("safe_point")
					out.append({"cell": [c.x, c.y], "kind": "repair_bay" if kind == "workshop" else "printer", "spot": str(spot.get("id", kind))})
					break
		if not out.is_empty():
			return out
	# A place's own printer: the open space beside it.
	for c in map.cells():
		if not map.column(c).has_tag("printer"):
			continue
		for n in map.grid.neighbors(c):
			if map.has_cell(n) and map.ground_height(n) <= map.ground_height(c) and not map.column(n).has_tag("printer") \
					and not map.column(n).has_tag("building") and not map.column(n).has_tag("machinery") and not map.column(n).has_tag("water"):
				map.column(n).tags.append("safe_point")
				return [{"cell": [n.x, n.y], "kind": "printer"}]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([region_seed, "safe", ax, ay])
	# Every third area along each row of the region, offset by row: never more than a step or
	# two from the nearest rig.
	if place == "town" or posmod(ax + ay * 2, 3) == 0:
		var mid := size / 2
		for k in range(2, 10):
			for sgn: int in [1, -1]:
				var c := mid + sgn * k
				var r := mid + 2
				var cell := SitrepLayout.cell_of(c, r, shape)
				if map.has_cell(cell) and map.ground_height(cell) <= 1 and map.column(cell).tags.is_empty() or (map.has_cell(cell) and map.column(cell).has_tag("lot")):
					var col := map.column(cell)
					col.ground = map.ground_height(cell) + 1
					col.tags = PackedStringArray(["machinery", "repair_rig", BattleMap.TAG_DESTRUCTIBLE])
					var stand := SitrepLayout.cell_of(c, r - 1, shape)
					if map.has_cell(stand):
						map.column(stand).tags.append("safe_point")
					out.append({"cell": [stand.x, stand.y], "kind": "field_rig"})
					return out
	return out


## A camp the squad has secured (story, after clearing an area): that spot becomes a safe point
## for Full Repairs (Core p.82). Marks the map cell and returns the safe point.
static func secure_camp(area_result: Dictionary, cell: Vector2i) -> Dictionary:
	var map: BattleMap = area_result["map"]
	if map.has_cell(cell):
		map.column(cell).tags.append("safe_point")
	var sp := {"cell": [cell.x, cell.y], "kind": "camp"}
	(area_result.get("safe_points", []) as Array).append(sp)
	area_result["safe_point"] = true
	if not area_result.has("repair"):
		area_result["repair"] = "rig"
		var wp := map.grid.to_world(cell)
		area_result["repair_bay"] = [wp.x, wp.z]
	return sp


## One edge between two areas of a region: [[ground, tags], ...] along it, the same for both
## areas that share it (seeded by the region and the edge's place). Low rolls of ground, a few
## stands of woods, and the road crossing it in the middle.
static func _edge_profile(region_seed: int, key: String, n: int, landscape: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([region_seed, "edge", key])
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	var woods := 0.0 if landscape in ["desert_mesas", "salt_flats", "moon", "asteroid", "volcanic", "molten_world", "city"] else 0.12
	var out: Array = []
	for i in range(n):
		if absi(i - n / 2) <= 1:
			out.append([0, ["road", "road_x" if key.begins_with("v") else "road_z"] if i == n / 2 else []])
			continue
		var g := 1 if noise.get_noise_1d(i) > 0.3 else 0
		var tags: Array = []
		if absi(i - n / 2) > 3 and rng.randf() < woods:
			tags = [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"]
		out.append([g, tags])
	return out


## The interior kind a fight inside a building happens in: the hub spot the fight starts at
## (opts.town "at" with "inside": true), when it has an interior (Interiors); "" otherwise.
## ("on_foot" alone only means the pilots start dismounted beside their mechs.)
static func _interior_kind(hub: Dictionary) -> String:
	if hub.is_empty() or not bool(hub.get("inside", false)):
		return ""
	for spot: Dictionary in hub.get("spots", []):
		if str(spot.get("id", "")) == str(hub.get("at", "")) and str(spot.get("kind", "")) in Interiors.kinds():
			return str(spot["kind"])
	return ""


## Deployment for an ambush: the squad on a band across the middle (the road), the
## ambushers on the open ground nearest the woods, rocks or ruins along one flank.
static func _ambush_deployment(map: BattleMap, shape: GridLayout.Shape, w: int, h: int, west: bool) -> Dictionary:
	var squad: Array = []
	var foes: Array = []
	for r in range(h):
		for c in range(w):
			var cell := SitrepLayout.cell_of(c, r, shape)
			if not map.has_cell(cell) or map.ground_height(cell) > 2 or map.column(cell).has_tag(BattleMap.TAG_IMPASSABLE):
				continue
			if absi(r - h / 2) <= 1 and absi(c - w / 2) <= w / 4:
				squad.append([cell.x, cell.y])
			var flank := c < w / 4 if west else c >= w - w / 4
			if flank and absi(r - h / 2) <= h / 3:
				var covered := false
				for n in map.grid.neighbors(cell):
					if map.has_cell(n) and (map.column(n).has_tag(Sight.TAG_SOFT_COVER) or map.ground_height(n) > map.ground_height(cell)):
						covered = true
				if covered and map.ground_height(cell) <= 1:
					foes.append([cell.x, cell.y])
	if foes.size() < 6:
		# Little cover on that flank: they wait out on it anyway.
		for r in range(h / 3, h - h / 3):
			for c in (range(0, w / 4) if west else range(w - w / 4, w)):
				var cell := SitrepLayout.cell_of(c, r, shape)
				if map.has_cell(cell) and map.ground_height(cell) <= 1 and not map.column(cell).has_tag(BattleMap.TAG_IMPASSABLE):
					foes.append([cell.x, cell.y])
	return {Mission.PLAYERS: squad, Mission.ENEMIES: foes}


## A secondary objective for this fight: opts.secondary "capture" / "defend" / "none", or "?"
## for the GM's pick (about one fight in three, on sitreps with room for it).
static func _secondary_kind(mission_seed: int, sitrep_id: String, wanted: String) -> String:
	if wanted in ["capture", "defend"]:
		return wanted
	if wanted != "?" or not sitrep_id in ["sitrep_standardcombat", "sitrep_control", "sitrep_holdout", "sitrep_gauntlet"]:
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = hash([mission_seed, "secondary"])
	if r.randf() > 0.33:
		return ""
	return "defend" if sitrep_id == "sitrep_standardcombat" and r.randf() < 0.5 else "capture"


const SECONDARY := {
	"capture": ["the comms tower", "a supply cache", "the relay mast", "the fuel depot"],
	"defend": ["the landing zone", "the field hospital", "the supply dump"],
}
const SECONDARY_REWARDS := ["reserve_supplies", "reserve_ammo", "reserve_extra_repairs", "reserve_access", "reserve_knowledge"]


## A secondary objective (main's rule: the book's sitrep is the primary and alone decides the
## mission; this one is the GM's, marked as such, and only earns a reserve or has a story cost):
## a 3x3 zone out on a flank, toward the enemy for a capture, on the squad's side for a defence.
static func _add_secondary(layout: Dictionary, kind: String, w: int, h: int, shape: GridLayout.Shape, seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var band: Array = layout.get("band", [0, h])
	var top := int(band[0])
	var bottom := int(band[1])
	var c0 := int(w * 0.12) if r.randf() < 0.5 else int(w * 0.88) - 3
	var r0 := (top + SitrepLayout.DEPTH + 1) if kind == "capture" else (bottom - SitrepLayout.DEPTH - 4)
	r0 = clampi(r0, 0, h - 3)
	layout["zones"]["secondary"] = SitrepLayout.rect(c0, r0, 3, 3, w, h, shape)
	var what: String = SECONDARY[kind][r.randi_range(0, SECONDARY[kind].size() - 1)]
	var reward: String = SECONDARY_REWARDS[r.randi_range(0, SECONDARY_REWARDS.size() - 1)]
	var reward_name := reward
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lancer-data/reserves.json"))
	if data is Array:
		for e: Dictionary in data:
			if str(e.get("id", "")) == reward:
				reward_name = str(e.get("name", reward))
	var verb := "take and hold" if kind == "capture" else "keep the enemy out of"
	var objectives: Array = layout.get("objectives", [])
	objectives.append({"id": "secondary", "type": kind, "side": Mission.PLAYERS, "zone": "secondary", "secondary": true,
		"what": what, "text": "%s %s" % [verb, what], "reward": reward, "reward_name": reward_name,
		"failure": "%s is lost: the region pays for it later." % what.capitalize(), "state": "open"})
	layout["objectives"] = objectives


## The weather for the kit ("" = clear), from opts.weather or a pick that suits the landscape.
static func _pick_weather(rng: RandomNumberGenerator, landscape: String, culture: String, wanted: String, season: String = "") -> String:
	var w := wanted if wanted != "?" else TerrainGen.pick_weather(rng, landscape, culture, season)
	return "" if w == "clear" else w


const WEATHER_FILE := "res://data/game/biomes/weather.json"
## Boarding map kinds (story's opts.boarding.map) to landscapes: two ships docked side by side,
## an enemy ship's interior (the squad boards it), the squad's own ship (pirates board it).
const SHIP_MAPS := ["boarding", "boarding_assault", "boarding_defend", "station", "starship"]
const BOARDING_MAPS := {"docked": "boarding", "enemy_ship": "boarding_assault", "own_ship": "boarding_defend"}
## Worlds whose own nature suggests a rules environment (weather suggests others: weather.json).
const LANDSCAPE_ENVIRONMENTS := {"moon": "env_lowgravity", "asteroid": "env_lowgravity", "ocean": "env_oceanworld", "volcanic": "env_moltenworld"}


## Rules environments (lancer-data environments.json) the world suggests: the weather's
## (weather.json "environment") and the landscape's. Each comes into play with the GM dial
## `environments` as its chance (its own seeded roll, so the rest of the mission doesn't change),
## so not every storm has rules effects. opts.environments (an Array of ids) sets them outright.
## Goes in mission.environments, state.environments and flavor.environments ({id, name, text}).
static func _pick_environments(m: Mission, state: GameState, mission_seed: int, landscape: String, weather: String, settings: GmSettings, opts: Dictionary) -> void:
	var list: Array = []
	if opts.get("environments") is Array:
		list = (opts["environments"] as Array).duplicate()
	else:
		var suggested: Array = []
		var wdata: Dictionary = GmSettings.load_json(WEATHER_FILE).get(weather, {}) if weather != "" else {}
		if str(wdata.get("environment", "")) != "":
			suggested.append(str(wdata["environment"]))
		if LANDSCAPE_ENVIRONMENTS.has(landscape) and not suggested.has(LANDSCAPE_ENVIRONMENTS[landscape]):
			suggested.append(LANDSCAPE_ENVIRONMENTS[landscape])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([mission_seed, "environment"])
		for env: String in suggested:
			if rng.randf() < settings.environments:
				list.append(env)
	m.environments = list
	state.environments = list.duplicate()
	var db: ContentDB = opts.get("db")
	var shown: Array = []
	for env: String in list:
		var e: Dictionary = db.get_entry("environments", env) if db != null else {}
		shown.append({"id": env, "name": str(e.get("name", env)), "text": RegEx.create_from_string("<[^>]+>").sub(str(e.get("description", "")), "", true).strip_edges()})
	m.flavor["environments"] = shown

static func _tag(col: BattleMap.Column, tags: Array) -> void:
	var have := col.tags  # Packed arrays are values: change a copy and put it back.
	for t: String in tags:
		if not have.has(t):
			have.append(t)
	col.tags = have


## Sitreps: "The area around the Control Zone is fortified with Size 1-2 hard cover."
## Short walls (1 level above the ground) just outside the zone, with gaps to walk through.
## A defended zone: a low wall ring round it (sandbags and barriers, one level: cover to fight
## from) broken by a two-space gap on each side, so attackers have to come through chokepoints,
## and a few barricades further out on the approaches to break their lines of fire.
static func _fortify(map: BattleMap, rng: RandomNumberGenerator, zone: Array, _shape: GridLayout.Shape) -> void:
	var inside := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Array in zone:
		var cell := Vector2i(c[0], c[1])
		inside[cell] = true
		var p := map.grid.to_world(cell)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var centre := (lo + hi) * 0.5
	var ring := {}
	for cell: Vector2i in inside:
		for n in map.grid.neighbors(cell):
			if map.has_cell(n) and not inside.has(n):
				ring[n] = true
	for cell: Vector2i in ring:
		var p := map.grid.to_world(cell)
		var d := Vector2(p.x, p.z) - centre
		# The gaps: straight out from the middle of each side (north, west, east, south).
		var gap := absf(d.x) < 1.1 or absf(d.y) < 0.9
		var col := map.column(cell)
		if gap or col.has_tag(BattleMap.TAG_IMPASSABLE) or col.gap_top > 0:
			continue
		col.ground += 1
		col.tags = PackedStringArray(["wall"])
	# Barricades out on the approaches, staggered so there's no clean line to the zone.
	var outer := {}
	for cell: Vector2i in ring:
		for n in map.grid.cells_within(cell, 4):
			if map.has_cell(n) and not inside.has(n) and not ring.has(n) and map.grid.distance(n, cell) >= 3:
				outer[n] = true
	var cells := outer.keys()
	cells.sort()
	for cell: Vector2i in cells:
		if rng.randf() < 0.06:
			var col := map.column(cell)
			if col.ground <= 1 and col.gap_top == 0 and not col.has_tag(BattleMap.TAG_IMPASSABLE) and not col.has_tag("building"):
				col.ground += 1
				col.tags = PackedStringArray(["wall"])


## The thing a Holdout's defenders protect stands in the zone: a Size 1 object (Core p.68:
## Evasion 5, 10 HP) the enemy can target. Lose it and the mission is lost (Mission).
static func _place_protected(map: BattleMap, protect: Dictionary) -> void:
	var cell := Vector2i(protect["cell"][0], protect["cell"][1])
	if not map.has_cell(cell):
		return
	var col := map.column(cell)
	var look: String = {"generator": "machinery", "relay": "machinery", "convoy truck": "container", "civilian shelter": "container"}.get(str(protect["kind"]), "container")
	col.ground = map.ground_height(cell) + 1
	col.gap_bottom = 0
	col.gap_top = 0
	col.tags = PackedStringArray([look, "objective", BattleMap.TAG_DESTRUCTIBLE, "hp_%d" % int(protect.get("hp", 10)), "armor_0"])
	protect["ground"] = col.ground


# --- Forces ------------------------------------------------------------------------------

static func _add_squad(state: GameState, m: Mission, rng: RandomNumberGenerator, players: int, db_opt: Variant, names: NameGen) -> void:
	var db: ContentDB = db_opt if db_opt is ContentDB else null
	if db == null:
		db = ContentDB.new()
		db.load_all()
	var builds: Array = GmSettings.load_json("res://data/game/gm/squads.json").get("lancers", [])
	var pilot := {"ll": 0}
	var free := _free_cells(m.deployment[Mission.PLAYERS], rng)
	for i in range(players):
		var b: Dictionary = builds[i % builds.size()]
		var loadout: Dictionary = b["loadout"]
		var check := UnitFactory.check_loadout(db, b["frame"], loadout, pilot)
		if not check.ok:
			push_warning("Squad build '%s' isn't legal (%s); using the basic Everest." % [b["name"], check.reason])
			loadout = builds[0]["loadout"]
		var seat := "p%d" % (i + 1)
		var u := UnitFactory.build_mech(db, seat, b["frame"], loadout, pilot)
		var callsign := names.callsign()
		var frame_name := u.name
		u.name = callsign
		u.side = Mission.PLAYERS
		u.controller = seat
		u.loadout["ai_role"] = str(b.get("role", ""))
		state.seats[seat] = {"name": callsign, "side": Mission.PLAYERS, "callsign": callsign,
			"pilot": names.pilot_name(), "mech": "%s (%s)" % [names.mech_name(), frame_name]}
		_place(state, u, free)


## The campaign's own pilots and their active mechs.
static func _add_campaign_squad(state: GameState, m: Mission, rng: RandomNumberGenerator, squad: Array, db_opt: Variant) -> void:
	var db: ContentDB = db_opt if db_opt is ContentDB else null
	if db == null:
		db = ContentDB.new()
		db.load_all()
	var free := _free_cells(m.deployment[Mission.PLAYERS], rng)
	for entry: Dictionary in squad:
		var p: Dictionary = entry["pilot"]
		var mech: Dictionary = entry["mech"]
		var seat := str(entry["seat"])
		var u := UnitFactory.build_mech(db, seat, str(mech["frame"]), mech.get("loadout", {}), p)
		u.name = str(p.get("callsign", u.name))
		u.side = Mission.PLAYERS
		u.controller = seat
		state.seats[seat] = {"name": u.name, "side": Mission.PLAYERS, "callsign": u.name,
			"pilot": str(p.get("name", "")), "mech": "%s (%s)" % [mech.get("name", ""), db.frame(str(mech["frame"])).get("name", "")],
			"pilot_id": str(p.get("id", ""))}
		_place(state, u, free)


static func _add_enemies(state: GameState, m: Mission, rng: RandomNumberGenerator, cfg: Dictionary, players: int, settings: GmSettings, templates: Dictionary) -> void:
	var pool := _enemy_pool(cfg, templates)
	m.reinforcement_pool = pool.duplicate(true)
	var budget := players * float(cfg.get("per_player", 1.5)) * settings.difficulty * float(settings.fight("encounter", 1.0))
	var free := _free_cells(m.deployment[Mission.ENEMIES], rng)
	var n := 0
	var guard := 0
	while budget > 0.4 and guard < 40:
		guard += 1
		var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if float(pick["cost"]) > budget + 0.5:
			continue
		budget -= float(pick["cost"])
		n += 1
		var u := build_enemy(pick, templates, "e%d" % n, n)
		if not _place(state, u, free):
			break


## NPC types the GM can field: data/game/npc_templates.json entries with their role and
## cost (template fields "role" / "cost" when present, else the stub list in missions.json).
static func _enemy_pool(cfg: Dictionary, templates: Dictionary) -> Array:
	var stub := {}
	for s: Dictionary in cfg.get("npc_stub", []):
		stub[s["template"]] = s
	var pool: Array = []
	for id: String in templates:
		var t: Variant = templates[id]
		if id.begins_with("_") or not t is Dictionary:
			continue
		var s: Dictionary = stub.get(id, {})
		pool.append({"template": id, "role": str(t.get("role", s.get("role", ""))),
			"cost": float(t.get("cost", s.get("cost", 1.0))), "tier": str(t.get("tier", ""))})
	return pool


static func build_enemy(pick: Dictionary, templates: Dictionary, id: String, number: int) -> Unit:
	var u := UnitFactory.build_npc(id, templates[pick["template"]])
	u.name = "%s %d" % [u.name, number]
	u.side = Mission.ENEMIES
	u.controller = "gm"
	if str(pick.get("role", "")) != "":
		u.loadout["ai_role"] = pick["role"]
	if str(pick.get("tier", "")) != "":
		u.loadout["tier"] = pick["tier"]
	return u


static func _free_cells(cells: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for c: Array in cells:
		out.append(Vector2i(c[0], c[1]))
	# Seeded shuffle (Array.shuffle would use the global RNG).
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Puts `u` on the first cell in `free` where it fits standing on level ground.
static func _place(state: GameState, u: Unit, free: Array) -> bool:
	var taken := {}
	for o: Unit in state.units.values():
		for c in state.map.grid.footprint(o.cell, o.size):
			taken[c] = true
	for cell: Vector2i in free:
		var level := 0
		var ok := true
		for c in state.map.grid.footprint(cell, u.size):
			if taken.has(c) or not state.map.has_cell(c):
				ok = false
				break
			level = maxi(level, state.map.ground_height(c))
		if not ok:
			continue
		var p := Movement.placement(state, u.size, cell, level)
		if p["ok"] and p["standing"] and not p["uneven"]:
			u.cell = cell
			u.level = level
			state.add_unit(u)
			free.erase(cell)
			return true
	push_warning("No room to deploy %s." % u.id)
	return false


## What the sitrep puts on the field, into state.objectives (SitrepActions, ViewFilter):
## the zones; Escort and Extraction's Objective (a Size 1 object: 10 HP per Size, Evasion 10,
## E-Defense 10, no Armor; Escort's in the Allied Deployment Zone, Extraction's placed by the
## GM in the Objective Zone) and Extraction Zone; Recon's True Control Zone, picked secretly.
static func _setup_objectives(m: Mission, state: GameState, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var o := {"sitrep": m.sitrep_id, "zones": m.zones.duplicate(true), "deployment": m.deployment.duplicate(true)}
	# Deployment zones per side for the setup phase (rules check placement, visuals colour them:
	# your own green, the enemy's red, the rest neutral): "deploy_<side>" cell sets, and who holds
	# ground here ("defender": the squad in a Holdout, the enemy in a Gauntlet, "" otherwise; their
	# side gets the fortifications, an advantage the sitrep intends).
	for side: String in m.deployment:
		o["deploy_" + side] = (m.deployment[side] as Array).duplicate(true)
	o["defender"] = {"sitrep_holdout": Mission.PLAYERS, "sitrep_gauntlet": Mission.ENEMIES}.get(m.sitrep_id, "")
	if m.flavor.has("ambush"):
		o["defender"] = Mission.ENEMIES  # dug in along the road
	match m.sitrep_id:
		"sitrep_escort", "sitrep_extraction":
			o["extraction"] = (m.zones.get("extraction", m.deployment.get(Mission.PLAYERS, [])) as Array).duplicate(true)
			var size := float(cfg.get("sitreps", {}).get(m.sitrep_id, {}).get("objective_size", 1))
			var obj := objective_unit(size)
			var where: Array = m.deployment.get(Mission.PLAYERS, []) if m.sitrep_id == "sitrep_escort" else m.zones.get("objective", [])
			if _place(state, obj, _free_cells(where, rng)):
				o["objective"] = obj.id
		"sitrep_recon":
			var names: Array = m.zones.keys().filter(func(z: String) -> bool: return z.begins_with("zone"))
			names.sort()
			if not names.is_empty():
				o["true_zone"] = names[rng.randi_range(0, names.size() - 1)]
				m.flavor["true_zone"] = o["true_zone"]  # host-only, for the GM's own forces
	state.objectives = o


## The Objective of Escort and Extraction (sitreps: Extraction): an object or person of Size
## 1/2-2 with 10 HP per level of Size, Evasion 10, E-Defense 10 and no Armor. It doesn't take
## turns or move on its own; enemy forces want it and won't willingly damage it (the AI never
## targets objects).
static func objective_unit(size: float = 1.0) -> Unit:
	var u := Unit.new()
	u.id = "objective"
	u.name = "Objective"
	u.kind = Unit.KIND_DEPLOYABLE
	u.content_id = "objective"
	u.side = Mission.PLAYERS
	u.controller = NetHost.GM_SEAT
	u.size = size
	u.max_hp = int(10 * maxf(size, 1.0))
	u.hp = u.max_hp
	u.evasion = 10
	u.edef = 10
	u.armor = 0
	u.structure = 1
	u.max_structure = 1
	u.stress = 1
	u.max_stress = 1
	u.speed = 0
	u.counters["objective"] = true
	u.counters["deploy_type"] = "Object"
	return u


static func _briefing(m: Mission, w: int, h: int, players: int, state: GameState) -> String:
	var enemies := state.units_on_side(Mission.ENEMIES).size()
	var goal := ""
	for s: Dictionary in _sitreps():
		if s.get("id", "") == m.sitrep_id:
			goal = str(s.get("pcVictory", ""))
	var f := m.flavor
	var text := "%s: %s on %s, %s (%d x %d). %s, %d lancers, against %d %s units. Win: %s." % [
		f.get("operation", "OPERATION"), m.sitrep_name, f.get("planet", "a frontier world"), f.get("terrain", "grassy hills"), w, h,
		f.get("team", "The squad"), players, enemies, f.get("faction", "hostile"), goal.trim_suffix(".")]
	for e: Dictionary in f.get("environments", []):
		text += "\nEnvironment: %s. %s" % [e["name"], e["text"]]
	return text
