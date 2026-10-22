class_name MissionGenerator
extends RefCounted
## Builds a whole mission from a seed: sitrep, battlefield, zones, deployment, both forces.
## Same seed + options = same mission. Generation uses its own seeded RNG (setup, not play);
## the battle's dice are the GameState's, seeded with the same number.
##
## Terrain kit so far: grassy hills (rolling heights 0-3, rock outcrops for hard cover, woods
## for soft cover and difficult ground, muddy patches).
##
## opts: {"players": 1-4 (default 4), "sitrep": id (default: weighted pick),
##   "size": 20-40 (default: random), "shape": "hex"/"square" (default hex),
##   "settings": GmSettings, "db": ContentDB, "npc_templates": Dictionary}
## Returns {"state": GameState (setup phase, seats p1..pN + gm), "mission": Mission}.

const KIT := "grassy_hills"


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
	state.map = _grassy_hills(rng, w, h, shape, blocked)
	if m.sitrep_id in ["sitrep_holdout", "sitrep_gauntlet"]:
		_fortify(state.map, rng, m.zones["zone"], shape)

	var players := clampi(int(opts.get("players", 4)), 1, 4)
	state.seats["gm"] = {"name": "GM", "side": Mission.ENEMIES, "gm": true}
	_add_squad(state, m, rng, players, opts.get("db"))
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


# --- Terrain: grassy hills -------------------------------------------------------------

static func _grassy_hills(rng: RandomNumberGenerator, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary) -> BattleMap:
	var map := BattleMap.new(shape)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = rng.randf_range(0.035, 0.06)
	noise.fractal_octaves = 3
	var cells: Array[Vector2i] = []
	for r in range(h):
		for c in range(w):
			var cell := _cell(c, r, shape)
			var n := noise.get_noise_2d(c, r)
			var ground := clampi(int(floor((n + 0.4) * 2.4)), 0, 3)
			if blocked.has(cell):
				ground = mini(ground, 1)  # Deployment and objective ground stays gentle.
			map.set_column(cell, ground)
			cells.append(cell)
	var area := w * h
	# Rock outcrops: 1-3 spaces, 2 levels above the ground around them (hard cover).
	for i in range(area / 55):
		var at := cells[rng.randi_range(0, cells.size() - 1)]
		for cell in _blob(map, rng, at, rng.randi_range(1, 3)):
			if not blocked.has(cell):
				var col := map.column(cell)
				col.ground = mini(col.ground + 2, 5)
	# Woods: soft cover, difficult to move through.
	for i in range(area / 110):
		var at := cells[rng.randi_range(0, cells.size() - 1)]
		for cell in _blob(map, rng, at, rng.randi_range(3, 7)):
			if not blocked.has(cell):
				_tag(map.column(cell), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT])
	# Mud and brush: difficult terrain.
	for i in range(area / 140):
		var at := cells[rng.randi_range(0, cells.size() - 1)]
		for cell in _blob(map, rng, at, rng.randi_range(2, 5)):
			_tag(map.column(cell), [BattleMap.TAG_DIFFICULT])
	return map


## A connected patch of up to `n` cells grown from `at`.
static func _blob(map: BattleMap, rng: RandomNumberGenerator, at: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [at]
	while out.size() < n:
		var from := out[rng.randi_range(0, out.size() - 1)]
		var next := map.grid.neighbors(from)
		var cell: Vector2i = next[rng.randi_range(0, next.size() - 1)]
		if map.has_cell(cell) and not out.has(cell):
			out.append(cell)
		elif rng.randf() < 0.2:
			break
	return out


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


# --- Forces ------------------------------------------------------------------------------

static func _add_squad(state: GameState, m: Mission, rng: RandomNumberGenerator, players: int, db_opt: Variant) -> void:
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
		u.name = "%s %d" % [str(b.get("callsign", u.name)), i + 1]
		u.side = Mission.PLAYERS
		u.controller = seat
		u.loadout["ai_role"] = str(b.get("role", ""))
		state.seats[seat] = {"name": "Pilot %d" % (i + 1), "side": Mission.PLAYERS}
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
	return "%s on grassy hills (%d x %d). %d lancers against %d hostiles. Win: %s." % [
		m.sitrep_name, w, h, players, enemies, goal.trim_suffix(".")]
