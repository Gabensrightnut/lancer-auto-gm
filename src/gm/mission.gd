class_name Mission
extends RefCounted
## One generated mission: its sitrep, zones, deployment areas and how it's won. It watches
## the rules engine's events (observe()) and decides the outcome by the sitrep's text in
## data/lancer-data/sitreps.json; the director then sends gm_end_mission.
##
## Supported sitreps: Basic Combat, Control, Holdout, Gauntlet.
## Wiping out a side ends any mission: the side left standing wins (PCs "defeat all enemy
## forces" / "are defeated").

const PLAYERS := "players"
const ENEMIES := "enemies"

var mission_seed := 0
var sitrep_id := ""
var sitrep_name := ""
## Last round of the mission (0 = no limit).
var rounds := 0
## GM safety stop for Basic Combat nobody can finish (a draw). Not a book rule.
var max_rounds := 12
## name -> Array of [x, y]
var zones: Dictionary = {}
## side -> Array of [x, y] where that side deploys.
var deployment: Dictionary = {}
var first_side := PLAYERS
var scores := {PLAYERS: 0, ENEMIES: 0}
## Templates the GM may bring in as reinforcements.
var reinforcement_pool: Array = []
var allow_reinforcements := false
var briefing := ""
## Rules environments in play (lancer-data environments.json ids, e.g. env_particulatestorms).
## Also in GameState.environments, where the rules engine reads them.
var environments: Array = []
## Names for the briefing and UI: {operation, planet, faction, team, cargo} (NameGen).
var flavor: Dictionary = {}
## "" while the mission runs; then "players", "enemies" or "none".
var outcome := ""
var outcome_reason := ""
var ended := false


## Looks at a batch of events from the rules engine; sets `outcome` when the mission is decided.
func observe(state: GameState, events: Array) -> void:
	if outcome != "":
		return
	var obj_id := str(state.objectives.get("objective", ""))
	for e: Dictionary in events:
		match e.get("type", ""):
			"round_started":
				if int(e["round"]) > 1:
					_end_of_round(state, int(e["round"]) - 1)
			"mission_ended":
				ended = true
			"objective_extracted":
				_decide(PLAYERS, "The Objective is safely extracted.")
			"unit_destroyed":
				if obj_id != "" and str(e.get("unit", "")) == obj_id:
					_decide("none", "The Objective was destroyed: there's nothing left to fight over, and both sides withdraw.")
			"turn_started":
				_carry_start(state, str(e.get("unit", "")))
			"moved":
				if str(e.get("mode", "")) in ["walk", "fly"]:  # a standard move (a Boost is "boost")
					_carry_move(state, str(e.get("unit", "")))
			"turn_ended":
				if str(flavor.get("carrier", "")) == str(e.get("unit", "")):
					flavor.erase("carrier")
		if outcome != "":
			return
	var alive := {PLAYERS: 0, ENEMIES: 0}
	var extracted := 0
	for u: Unit in state.units.values():
		if _counts(u) and alive.has(u.side):
			alive[u.side] += 1
		if u.counters.has("extracted") and u.side == PLAYERS and u.id != obj_id:
			extracted += 1
	if alive[PLAYERS] == 0 and extracted > 0:
		# Everyone got out, but not with the Objective: nobody is left to bring it (the enemy
		# wins when time runs out, so the GM calls it now).
		_decide(ENEMIES, "The squad extracted without the Objective.")
	elif alive[PLAYERS] == 0:
		_decide(ENEMIES, "The squad has been defeated.")
	elif alive[ENEMIES] == 0:
		_decide(PLAYERS, "All enemy forces have been defeated.")


# --- The Objective (Escort, Extraction) ---------------------------------------------------

## "When a character starts their turn adjacent to the Objective, it moves with them when they
## make their regular move" (sitreps: Extraction; Escort's Objective moves the same way,
## PROVISIONAL). Not while it's next to characters of both sides.
func _carry_start(state: GameState, unit_id: String) -> void:
	var obj := SitrepActions.objective(state)
	var u := state.unit(unit_id)
	if obj == null or u == null or not Combat.is_present(obj) or u.kind == Unit.KIND_DEPLOYABLE:
		return
	if Sight.unit_distance(state, u, obj) <= 1 and not SitrepActions.contested(state, obj, u.side):
		flavor["carrier"] = u.id
		flavor["carry_offset"] = [obj.cell.x - u.cell.x, obj.cell.y - u.cell.y]


## The carrier made their regular move: the Objective follows to the free space next to them
## closest to where it was relative to them (AiDirector submits gm_carry_objective).
func _carry_move(state: GameState, unit_id: String) -> void:
	if str(flavor.get("carrier", "")) != unit_id:
		return
	var obj := SitrepActions.objective(state)
	var u := state.unit(unit_id)
	if obj == null or u == null or not Combat.is_present(obj) or not Combat.is_present(u):
		return
	if SitrepActions.contested(state, obj, u.side) and Sight.unit_distance(state, u, obj) <= 1:
		return  # next to characters of both sides: it stops moving
	var off: Array = flavor.get("carry_offset", [0, 1])
	var want := Vector2i(u.cell.x + int(off[0]), u.cell.y + int(off[1]))
	var taken := {}
	for o: Unit in state.units.values():
		if o != obj and Combat.is_present(o):
			for c in state.map.grid.footprint(o.cell, o.size):
				taken[c] = true
	var best := Vector2i(-9999, -9999)
	var best_d := 99999
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := u.cell + Vector2i(dx, dy)
			if taken.has(c) or not state.map.has_cell(c) or c == u.cell:
				continue
			if state.map.grid.distance(c, u.cell) > int(ceil(u.size)):
				continue
			var d := state.map.grid.distance(c, want)
			if d < best_d:
				best_d = d
				best = c
	if best_d < 99999:
		flavor["carry_to"] = [best.x, best.y, u.id]


## A pending Objective move for the director to submit: {"type": "gm_carry_objective"...} or {}.
func carry_action() -> Dictionary:
	if not flavor.has("carry_to"):
		return {}
	var to: Array = flavor["carry_to"]
	flavor.erase("carry_to")
	return {"type": "gm_carry_objective", "params": {"to": [to[0], to[1]], "by": to[2]}}


func _end_of_round(state: GameState, r: int) -> void:
	match sitrep_id:
		"sitrep_control":
			var held := {PLAYERS: 0, ENEMIES: 0}
			for name: String in zones:
				var side := _controller(state, name)
				if held.has(side):
					held[side] += 1
					scores[side] += 1
			for side: String in held:
				if held[side] == zones.size():
					scores[side] += 1  # Controlling all four zones: +1 point.
			if r >= rounds:
				if scores[PLAYERS] == scores[ENEMIES]:
					_decide("none", "Scores are tied %d-%d after round %d: both sides withdraw." % [scores[PLAYERS], scores[ENEMIES], r])
				else:
					var winner := PLAYERS if scores[PLAYERS] > scores[ENEMIES] else ENEMIES
					_decide(winner, "Final score %d-%d (squad-enemy) after round %d." % [scores[PLAYERS], scores[ENEMIES], r])
		"sitrep_holdout":
			if _protected_lost(state):
				_decide(ENEMIES, "The %s was destroyed: there's nothing left to hold." % str(flavor["protect"]["kind"]))
				return
			if r >= rounds:
				var inside := _count_in(state, "zone", ENEMIES)
				scores[PLAYERS] = 4 - int(inside)
				if scores[PLAYERS] >= 1:
					_decide(PLAYERS, "The squad held: score %d (%d enemies in the zone)." % [scores[PLAYERS], inside])
				else:
					_decide(ENEMIES, "The zone fell: score %d (%d enemies in the zone)." % [scores[PLAYERS], inside])
		"sitrep_escort", "sitrep_extraction":
			if r >= rounds and not state.objectives.get("objective_extracted", false):
				_decide(ENEMIES, "The Objective wasn't extracted by the end of round %d. Anyone still on the field is captured or overrun." % r)
		"sitrep_recon":
			if r >= rounds:
				var true_zone := str(state.objectives.get("true_zone", ""))
				var held := _controller(state, true_zone) if true_zone != "" else ""
				if held == PLAYERS:
					_decide(PLAYERS, "The squad holds the True Control Zone at the end of round %d." % r)
				else:
					_decide(ENEMIES, "The squad doesn't control the True Control Zone at the end of round %d%s." % [r, " (it's contested)" if held == "contested" else ""])
		"sitrep_gauntlet":
			if r >= rounds:
				var pcs := _count_in(state, "zone", PLAYERS)
				var foes := _count_in(state, "zone", ENEMIES)
				if pcs > foes:
					_decide(PLAYERS, "The squad took the position (%d vs %d in the zone)." % [pcs, foes])
				else:
					_decide(ENEMIES, "The enemy kept the position (%d vs %d in the zone)." % [foes, pcs])
		_:
			if max_rounds > 0 and r >= max_rounds:
				_decide("none", "Neither side could finish the fight after %d rounds; both pull back." % r)


## Which side controls a zone: "players", "enemies", "contested" or "".
func _controller(state: GameState, zone: String) -> String:
	var p := _count_in(state, zone, PLAYERS)
	var e := _count_in(state, zone, ENEMIES)
	if p > 0 and e > 0:
		return "contested"
	if p > 0:
		return PLAYERS
	if e > 0:
		return ENEMIES
	return ""


## Characters of `side` with any part of their footprint inside the zone.
## PROVISIONAL: Gauntlet counts Ultras 4, Elites 2, Grunts 1/4; our placeholder NPCs have no
## tier, so each counts 1 (template "tier" read when present).
func _count_in(state: GameState, zone: String, side: String) -> float:
	var cells := {}
	for c: Array in zones.get(zone, []):
		cells[Vector2i(int(c[0]), int(c[1]))] = true
	var n := 0.0
	for u: Unit in state.units.values():
		if u.side != side or not _counts(u):
			continue
		for c in state.map.grid.footprint(u.cell, u.size):
			if cells.has(c):
				n += _weight(u)
				break
	return n


static func _weight(u: Unit) -> float:
	match str(u.loadout.get("tier", "")):
		"ultra":
			return 4.0
		"elite":
			return 2.0
		"grunt":
			return 0.25
	return 1.0


static func _counts(u: Unit) -> bool:
	return not u.destroyed and u.kind != Unit.KIND_DEPLOYABLE and not u.counters.has("extracted")


## The Holdout's protected object (flavor.protect) is gone: its column lost its section.
func _protected_lost(state: GameState) -> bool:
	if not flavor.has("protect"):
		return false
	var p: Dictionary = flavor["protect"]
	var cell := Vector2i(p["cell"][0], p["cell"][1])
	return state.map.has_cell(cell) and state.map.ground_height(cell) < int(p.get("ground", 1))


func _decide(winner: String, why: String) -> void:
	outcome = winner
	outcome_reason = why


## The gm_end_mission action for the decided outcome.
func end_action() -> Dictionary:
	return {"type": "gm_end_mission", "params": {"outcome": outcome, "reason": outcome_reason, "scores": scores.duplicate()}}


## Cells the AI of `side` should try to stand on, and how much it cares (0 = no objective).
func objective_for(side: String) -> Dictionary:
	var cells: Array = []
	var weight := 0.0
	match sitrep_id:
		"sitrep_control":
			for name: String in zones:
				cells.append_array(zones[name])
			weight = 2.0
		"sitrep_holdout":
			cells = zones.get("zone", [])
			weight = 2.5 if side == ENEMIES else 1.5
		"sitrep_gauntlet":
			cells = zones.get("zone", [])
			weight = 2.5 if side == PLAYERS else 1.5
		"sitrep_recon":
			# The GM's side knows the True Control Zone; the squad heads for the zones.
			if side == ENEMIES and flavor.has("true_zone"):
				cells = zones.get(str(flavor["true_zone"]), [])
				weight = 2.0
			else:
				for name: String in zones:
					cells.append_array(zones[name])
				weight = 1.5
		"sitrep_escort", "sitrep_extraction":
			# Both sides go for the Objective; the squad then heads for extraction (the player
			# moves it: AI squadmates don't carry it yet).
			cells = zones.get("objective", zones.get("extraction", []))
			weight = 1.2
	return {"zones": cells, "zone_weight": weight}


func to_dict() -> Dictionary:
	return {"seed": str(mission_seed), "sitrep": sitrep_id, "sitrep_name": sitrep_name, "rounds": rounds,
		"max_rounds": max_rounds, "zones": zones.duplicate(true), "deployment": deployment.duplicate(true),
		"first_side": first_side, "scores": scores.duplicate(), "reinforcement_pool": reinforcement_pool.duplicate(true),
		"allow_reinforcements": allow_reinforcements, "briefing": briefing, "environments": environments.duplicate(), "flavor": flavor.duplicate(), "outcome": outcome,
		"outcome_reason": outcome_reason, "ended": ended}


static func from_dict(d: Dictionary) -> Mission:
	var m := Mission.new()
	m.mission_seed = str(d.get("seed", "0")).to_int()
	m.sitrep_id = str(d.get("sitrep", ""))
	m.sitrep_name = str(d.get("sitrep_name", ""))
	m.rounds = int(d.get("rounds", 0))
	m.max_rounds = int(d.get("max_rounds", 12))
	m.zones = (d.get("zones", {}) as Dictionary).duplicate(true)
	m.deployment = (d.get("deployment", {}) as Dictionary).duplicate(true)
	m.first_side = str(d.get("first_side", PLAYERS))
	for side: String in d.get("scores", {}):
		m.scores[side] = int(d["scores"][side])
	m.reinforcement_pool = (d.get("reinforcement_pool", []) as Array).duplicate(true)
	m.allow_reinforcements = bool(d.get("allow_reinforcements", false))
	m.briefing = str(d.get("briefing", ""))
	m.environments = (d.get("environments", []) as Array).duplicate()
	m.flavor = (d.get("flavor", {}) as Dictionary).duplicate()
	m.outcome = str(d.get("outcome", ""))
	m.outcome_reason = str(d.get("outcome_reason", ""))
	m.ended = bool(d.get("ended", false))
	return m
