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
	for e: Dictionary in events:
		match e.get("type", ""):
			"round_started":
				if int(e["round"]) > 1:
					_end_of_round(state, int(e["round"]) - 1)
			"mission_ended":
				ended = true
		if outcome != "":
			return
	var alive := {PLAYERS: 0, ENEMIES: 0}
	for u: Unit in state.units.values():
		if _counts(u) and alive.has(u.side):
			alive[u.side] += 1
	if alive[PLAYERS] == 0:
		_decide(ENEMIES, "The squad has been defeated.")
	elif alive[ENEMIES] == 0:
		_decide(PLAYERS, "All enemy forces have been defeated.")


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
			if r >= rounds:
				var inside := _count_in(state, "zone", ENEMIES)
				scores[PLAYERS] = 4 - int(inside)
				if scores[PLAYERS] >= 1:
					_decide(PLAYERS, "The squad held: score %d (%d enemies in the zone)." % [scores[PLAYERS], inside])
				else:
					_decide(ENEMIES, "The zone fell: score %d (%d enemies in the zone)." % [scores[PLAYERS], inside])
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
	return not u.destroyed and u.kind != Unit.KIND_DEPLOYABLE


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
