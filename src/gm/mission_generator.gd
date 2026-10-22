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
##   "size": 20-40 (default: random), "shape": "hex"/"square" (default hex),
##   "landscape": TerrainGen.LANDSCAPES key, "culture": culture id (default: seeded pick),
##   "settings": GmSettings, "db": ContentDB, "npc_templates": Dictionary,
##   "squad": Campaign.squad() entries [{seat, pilot, mech}] to field the campaign's pilots}
## Returns {"state": GameState (setup phase, seats p1..pN + gm), "mission": Mission}.

static func generate(mission_seed: int, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([mission_seed, "mission"])
	var cfg := GmSettings.load_json(GmSettings.MISSIONS_FILE)
	var settings: GmSettings = opts.get("settings", GmSettings.from_preset("Standard"))
	var shape := GridLayout.Shape.SQUARE if str(opts.get("shape", "hex")) == "square" else GridLayout.Shape.HEX
	var sizes: Dictionary = cfg.get("map_sizes", {"min": 20, "max": 40})
	var size := clampi(int(opts.get("size", rng.randi_range(int(sizes["min"]), int(sizes["max"])))), 20, 40)
	var w := size
	var h := clampi(int(size * rng.randf_range(0.75, 1.0)), 20, 40)

	var m := Mission.new()
	m.mission_seed = mission_seed
	m.max_rounds = int(cfg.get("max_rounds", 12))
	_pick_sitrep(m, rng, cfg, str(opts.get("sitrep", "")))

	var state := GameState.new(mission_seed, shape)
	var blocked := {}  # cells kept clear of rocks and woods (deployment, zones)
	_layout_zones(m, rng, w, h, shape, blocked)
	# The world uses its own RNG so terrain changes never shift the rest of the mission.
	var world_rng := RandomNumberGenerator.new()
	world_rng.seed = hash([mission_seed, "world"])
	var world := TerrainGen.pick(world_rng, str(opts.get("landscape", "")), str(opts.get("culture", "")))
	state.map = TerrainGen.generate(world_rng, w, h, shape, blocked, world[0], world[1])
	if m.sitrep_id in ["sitrep_holdout", "sitrep_gauntlet"]:
		_fortify(state.map, rng, m.zones["zone"], shape)

	# Names use their own RNG so changing name lists never changes the battlefield.
	var names_rng := RandomNumberGenerator.new()
	names_rng.seed = hash([mission_seed, "names"])
	var names := NameGen.new(names_rng)
	m.flavor = {"operation": names.operation(), "planet": names.planet(), "faction": names.faction(),
		"team": names.team_name(), "cargo": names.cargo(), "kit": TerrainGen.kit(world[0], world[1]),
		"terrain": TerrainGen.describe(world[0], world[1])}
	var players := clampi(int(opts.get("players", 4)), 1, 4)
	state.seats["gm"] = {"name": "GM", "side": Mission.ENEMIES, "gm": true}
	if opts.get("squad", []) is Array and not (opts.get("squad", []) as Array).is_empty():
		_add_campaign_squad(state, m, rng, opts["squad"], opts.get("db"))
	else:
		_add_squad(state, m, rng, players, opts.get("db"), names)
	_add_enemies(state, m, rng, cfg, players, settings, opts.get("npc_templates", UnitFactory.npc_templates()))
	m.briefing = _briefing(m, w, h, players, state)
	return {"state": state, "mission": m}


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


static func _layout_zones(m: Mission, rng: RandomNumberGenerator, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary) -> void:
	var depth := 4
	m.deployment = {
		Mission.PLAYERS: _rect(2, h - depth, w - 4, depth, w, h, shape),
		Mission.ENEMIES: _rect(2, 0, w - 4, depth, w, h, shape),
	}
	match m.sitrep_id:
		"sitrep_control":
			# Four 4x4 zones, one per quadrant, mirrored so neither side is favored.
			var dx := rng.randi_range(2, maxi(2, w / 4 - 2))
			var dy := rng.randi_range(depth + 1, maxi(depth + 1, h / 2 - 5))
			var spots := [[dx, dy], [w - dx - 4, dy], [dx, h - dy - 4], [w - dx - 4, h - dy - 4]]
			for i in range(4):
				m.zones["zone_%d" % (i + 1)] = _rect(spots[i][0], spots[i][1], 4, 4, w, h, shape)
		"sitrep_holdout":
			var zone := _rect(w / 2 - 5, h / 2 - 2, 10, 5, w, h, shape)
			m.zones["zone"] = zone
			m.deployment[Mission.PLAYERS] = zone  # PCs deploy in the Control Zone.
		"sitrep_gauntlet":
			var zone := _rect(w / 2 - 5, 0, 10, 5, w, h, shape)
			m.zones["zone"] = zone
			m.deployment[Mission.ENEMIES] = zone  # The Control Zone is the EDZ.
			m.first_side = Mission.PLAYERS
	for list: Array in m.deployment.values():
		for c: Array in list:
			blocked[Vector2i(c[0], c[1])] = true
	for list: Array in m.zones.values():
		for c: Array in list:
			blocked[Vector2i(c[0], c[1])] = true


# --- Terrain (TerrainGen) -------------------------------------------------------------

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


static func _briefing(m: Mission, w: int, h: int, players: int, state: GameState) -> String:
	var enemies := state.units_on_side(Mission.ENEMIES).size()
	var goal := ""
	for s: Dictionary in _sitreps():
		if s.get("id", "") == m.sitrep_id:
			goal = str(s.get("pcVictory", ""))
	var f := m.flavor
	return "%s: %s on %s, %s (%d x %d). %s, %d lancers, against %d %s units. Win: %s." % [
		f.get("operation", "OPERATION"), m.sitrep_name, f.get("planet", "a frontier world"), f.get("terrain", "grassy hills"), w, h,
		f.get("team", "The squad"), players, enemies, f.get("faction", "hostile"), goal.trim_suffix(".")]
