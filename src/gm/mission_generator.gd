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
##   "hub": story.hub (a fight in a hub's town: built from its layout and culture kit),
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
	var hub: Dictionary = opts.get("hub", {}) if opts.get("hub") is Dictionary else {}
	var landscape := str(opts.get("landscape", ""))
	var culture := str(opts.get("culture", ""))
	if not hub.is_empty():
		culture = WorldKits.culture_id(str(hub.get("culture", culture)))
		if landscape == "":
			landscape = "station" if str(hub.get("kind", "")) == "station" else str(WorldKits.HUB_LANDSCAPE.get(culture, "grassy_hills"))
	var bf: Dictionary
	if doc == null:
		bf = battlefield(rng, world_rng, m.sitrep_id, w, h, shape, landscape, culture, int(settings.approach), hub)
	else:
		bf = _doc_battlefield(doc, m.sitrep_id, rng)
	state.map = bf["map"]
	var layout: Dictionary = bf["layout"]
	var fairness: Dictionary = bf["fairness"]
	var world: Array = bf["world"]
	m.deployment = layout["deployment"]
	m.zones = layout["zones"]
	if layout["first_side"] != "":
		m.first_side = layout["first_side"]

	# Names use their own RNG so changing name lists never changes the battlefield.
	var names_rng := RandomNumberGenerator.new()
	names_rng.seed = hash([mission_seed, "names"])
	var names := NameGen.new(names_rng)
	var weather := _pick_weather(world_rng, world[0], world[1], str(opts.get("weather", doc.weather if doc and doc.weather != "" else ("clear" if doc else "?"))))
	m.flavor = {"operation": names.operation(), "planet": names.planet(), "faction": names.faction(),
		"team": names.team_name(), "cargo": names.cargo(), "kit": TerrainGen.kit(world[0], world[1]) + ("+" + weather if weather != "" else ""),
		"terrain": TerrainGen.describe(world[0], world[1]), "weather": weather}
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
		shape: GridLayout.Shape, landscape: String = "", culture: String = "", approach: int = 0, hub: Dictionary = {}) -> Dictionary:
	var layout := SitrepLayout.layout(sitrep_id, w, h, shape, rng, approach)
	var blocked := {}  # cells kept clear of rocks and woods (deployment, zones, routes)
	for list: Array in (layout["deployment"] as Dictionary).values() + (layout["zones"] as Dictionary).values() + [layout["clear"]]:
		for c: Array in list:
			blocked[Vector2i(c[0], c[1])] = true
	var world := TerrainGen.pick(world_rng, landscape, culture)
	var map := TerrainGen.generate(world_rng, w, h, shape, blocked, world[0], world[1], hub)
	if sitrep_id in ["sitrep_holdout", "sitrep_gauntlet"]:
		_fortify(map, rng, layout["zones"]["zone"], shape)
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

## The weather for the kit ("" = clear), from opts.weather or a pick that suits the landscape.
static func _pick_weather(rng: RandomNumberGenerator, landscape: String, culture: String, wanted: String) -> String:
	var w := wanted if wanted != "?" else TerrainGen.pick_weather(rng, landscape, culture)
	return "" if w == "clear" else w


const WEATHER_FILE := "res://data/game/biomes/weather.json"
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
static func _fortify(map: BattleMap, rng: RandomNumberGenerator, zone: Array, _shape: GridLayout.Shape) -> void:
	var inside := {}
	for c: Array in zone:
		inside[Vector2i(c[0], c[1])] = true
	var ring := {}
	for cell: Vector2i in inside:
		for n in map.grid.neighbors(cell):
			if map.has_cell(n) and not inside.has(n):
				ring[n] = true
	for cell: Vector2i in ring:
		if rng.randf() < 0.45:
			var col := map.column(cell)
			col.ground += 1 if rng.randf() < 0.7 else 2
			col.tags = PackedStringArray(["wall"])


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
	var budget := players * float(cfg.get("per_player", 1.5)) * settings.difficulty
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
