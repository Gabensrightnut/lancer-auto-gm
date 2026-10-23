class_name WorldMapGen
extends RefCounted
## The region data net's WorldMapSession walks on, in net's shape (built from RegionMap):
##
##   WorldMapGen.region(seed, world) -> {
##     id, size [w, h],
##     tiles: {"x,y": {terrain, cost (hours per space at Speed 1), mech: bool, foot: bool}},
##     sites: [{id, kind "town" | "outpost" | "job" | "safe" | "landmark", at [x, y], name,
##              area: {place, at, region} (feed it to MissionGenerator.area(seed, area)),
##              safe_point, repair?}],
##     war: {factions: [...]} or null, ambush_spots: [{id, at, cover, faction, force}] }
##
## world: a Sector world {id?, name, culture (story kit), map_culture?, landscape, weather?,
## start? (the campaign's first region), war? {factions}}. Same seed and world, same region.

## Our terrain classes (travel) to the names visuals' WorldMapView draws, by landscape.
const LOOK := {"mountains": "mountain", "city": "urban", "water": "water", "road": "road", "swamp": "swamp", "hills": "hills", "forest": "forest", "plains": "plains"}
const PLAINS_BY_LAND := {"desert_mesas": "desert", "salt_flats": "salt", "tundra": "snow", "volcanic": "ash", "molten_world": "ash",
	"moon": "rock", "asteroid": "rock", "crystal_fields": "rock", "grassy_hills": "grass", "autumn_forest": "grass", "jungle": "jungle"}
const SITE_KIND := {"town": "town", "outpost": "outpost", "pad": "outpost", "port": "outpost", "farm": "job", "wreck": "job",
	"job_site": "job", "safe_point": "safe", "landmark": "landmark", "mine": "job", "ruins": "landmark", "relay": "outpost"}


static func region(seed_value: int, world: Dictionary) -> Dictionary:
	var culture := WorldKits.culture_id(str(world.get("map_culture", world.get("culture", ""))))
	var profile := {"seed": seed_value, "landscape": str(world.get("landscape", "grassy_hills")), "culture": culture,
		"weather": str(world.get("weather", "")), "name": str(world.get("name", "the town"))}
	var rm := RegionMap.build(profile, {"start": bool(world.get("start", false))})
	var tiles := {}
	var size: Array = rm["size"]
	for y in range(int(size[1])):
		for x in range(int(size[0])):
			var t := str(rm["tiles"][y][x])
			tiles["%d,%d" % [x, y]] = {"terrain": _look(t, profile), "class": t, "cost": float(rm["travel"].get(t, 1.0)),
				"mech": not (rm["mech_blocked"] as Array).has(t), "foot": t != "water"}
	var sites: Array = []
	for p: Dictionary in rm["places"]:
		var area := RegionMap.area_opts(rm, int(p["at"][0]), int(p["at"][1]))
		var s := {"id": str(p["id"]), "kind": str(SITE_KIND.get(str(p["kind"]), "job")), "detail": str(p["kind"]), "at": p["at"],
			"name": str(p["name"]), "area": area, "safe_point": bool(p.get("safe_point", false))}
		if p.has("repair"):
			s["repair"] = p["repair"]
		sites.append(s)
	var war: Variant = world.get("war") if world.get("war") is Dictionary else null
	var ambush: Array = _ambush_spots(rm, war, seed_value, profile) if war != null else []
	return {"id": str(world.get("id", "region_%d" % seed_value)), "size": size, "tiles": tiles, "sites": sites,
		"war": war, "ambush_spots": ambush, "start": rm["start"], "region": profile}


## Ambushes along the routes of a region at war (story sets which regions and who's fighting;
## canon factions only): a tile of real cover (woods, hills, ruins, rock) beside a road, with
## the faction lying in wait and how big a force the GM fields there ("patrol" a few units,
## "lance" a full encounter, "strike" a hard one). The fight is built from the spot:
## MissionGenerator.generate(seed, {"ambush": spot, ...}) puts the squad on the road and the
## ambushers in the cover.
static func _ambush_spots(rm: Dictionary, war: Dictionary, seed_value: int, profile: Dictionary) -> Array:
	var factions: Array = war.get("factions", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "ambush"])
	var out: Array = []
	var size: Array = rm["size"]
	var places := {}
	for p: Dictionary in rm["places"]:
		places[Vector2i(p["at"][0], p["at"][1])] = true
	for r: Array in rm["roads"]:
		var road := Vector2i(r[0], r[1])
		if places.has(road):
			continue
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c := road + d
			if c.x < 0 or c.y < 0 or c.x >= int(size[0]) or c.y >= int(size[1]) or places.has(c):
				continue
			var t := str(rm["tiles"][c.y][c.x])
			if t in ["forest", "hills", "city", "mountains"] and rng.randf() < 0.25:
				out.append({"id": "ambush_%d" % out.size(), "at": [c.x, c.y], "road": [road.x, road.y], "cover": _look(t, profile),
					"faction": str(factions[rng.randi_range(0, factions.size() - 1)]) if not factions.is_empty() else "",
					"force": ["patrol", "patrol", "lance", "strike"][rng.randi_range(0, 3)],
					"area": {"place": "road", "at": [road.x, road.y], "region": rm["region"]}})
				break
		if out.size() >= 6:
			break
	return out


## The tile's look for visuals: the landscape's own ground for open country, jungle in a jungle,
## ruins in a ruined city, ocean worlds' water as sea.
static func _look(t: String, profile: Dictionary) -> String:
	var land := str(profile["landscape"])
	if t == "plains":
		return str(PLAINS_BY_LAND.get(land, "plains"))
	if t == "forest" and land == "jungle":
		return "jungle"
	if t == "city" and str(profile.get("culture", "")) in ["ruins", "burning"]:
		return "ruins"
	if t == "water" and land == "ocean":
		return "sea"
	return str(LOOK.get(t, "plains"))

