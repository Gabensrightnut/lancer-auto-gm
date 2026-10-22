class_name AiDirector
extends RefCounted
## Runs every AI-played seat on the host: the procedural GM's enemies and AI squadmates.
## Which seats the AI plays is NetHost.is_ai_seat() (switchable mid-mission). Everything goes
## through NetHost.submit(), so the AI follows the same rules and seat checks as players.
##
## Call step() regularly (Net does it every frame); each call does at most one thing:
## starts combat, ends a decided mission, brings reinforcements, picks the next AI unit to
## activate, or plays one whole AI turn. run() loops until a human is needed.
##
## The AI only ever acts for seats set to AI. Human seats are waited on with no time limit,
## and nothing of theirs is auto-resolved. Picking who acts next: on a side with any human
## seat the humans choose ("I'll go", including when an AI squadmate goes); the AI picks only
## for a side with no human seat at all (usually the GM's).

## One line per AI decision, for the battle log ("Moving to hard cover, heat is high").
signal ai_log(unit_id: String, text: String)
## The mission's outcome was decided and the mission ended.
signal mission_over(outcome: String, reason: String)

var host: NetHost
var ai: TacticsAi
var settings: GmSettings
var mission: Mission
## unit id -> orders for AI squadmates: {"stance", "focus", "follow"} (see TacticsAi).
var orders: Dictionary = {}
## Every refused AI action ({unit, action, reason}): should stay empty; kept for debugging.
var refusals: Array = []
var log_lines: PackedStringArray = PackedStringArray()

var _reinforced_round := 0


func _init(net_host: NetHost, gm: GmSettings = null, the_mission: Mission = null) -> void:
	host = net_host
	settings = gm if gm != null else GmSettings.from_preset("Standard")
	mission = the_mission
	ai = TacticsAi.new(settings)
	ai.seed_salt = host.state.game_seed
	GmActions.register(host.engine)
	host.action_resolved.connect(_on_action_resolved)


func set_orders(unit_id: String, unit_orders: Dictionary) -> void:
	orders[unit_id] = unit_orders.duplicate()


## Plays AI work until a human must act or the mission ends. Returns steps taken.
func run(max_steps: int = 100000) -> int:
	var n := 0
	while n < max_steps and step():
		n += 1
	return n


## Does one piece of AI work. Returns false when there's nothing for the AI to do.
func step() -> bool:
	var state := host.state
	if state.phase == GameState.PHASE_ENDED:
		return false
	if mission != null and mission.outcome != "" and not mission.ended:
		var out := host.submit(NetHost.GM_SEAT, mission.end_action())
		mission.ended = true
		mission_over.emit(mission.outcome, mission.outcome_reason)
		_log("", "Mission over: %s" % mission.outcome_reason)
		return (out["result"] as RuleResult).ok
	if state.phase == GameState.PHASE_SETUP:
		if not host.is_ai_seat(NetHost.GM_SEAT):
			return false  # A human GM starts the fight.
		var first := mission.first_side if mission != null else Mission.PLAYERS
		return (host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": first}})["result"] as RuleResult).ok
	if _maybe_reinforce():
		return true
	if state.active_unit != "":
		var u := state.unit(state.active_unit)
		if u != null and host.is_ai_seat(u.controller):
			play_turn(u)
			return true
		return false
	if not host.waiting_on()["ai"]:
		return false  # Humans on this side choose who goes next.
	var mine: Array[Unit] = []
	for u in TurnRules.waiting(state, state.turn_side):
		if host.is_ai_seat(u.controller):
			mine.append(u)
	if mine.is_empty():
		return false
	var pick := _choose_activation(mine)
	var out := host.submit(pick.controller, {"type": "start_turn", "actor": pick.id})
	if not (out["result"] as RuleResult).ok:
		_refused(pick, {"type": "start_turn"}, out["result"])
		return false
	play_turn(pick)
	return true


## Plans and plays the active AI unit's whole turn, then ends it.
func play_turn(u: Unit) -> void:
	var know := AiKnowledge.for_side(host.state, host.view_filter, u.side)
	var plan := ai.plan_turn(know, u.id, _orders_for(u))
	if settings.explain:
		_log(u.id, plan["log"])
	for action: Dictionary in plan["steps"]:
		if u.destroyed or host.state.active_unit != u.id:
			break
		var out := host.submit(u.controller, action)
		if not (out["result"] as RuleResult).ok:
			# The real battlefield differed from what this side knew (a Hidden enemy in the way...).
			_refused(u, action, out["result"])
	if host.state.active_unit == u.id:
		host.submit(u.controller, {"type": "end_turn", "actor": u.id})


## Which AI unit acts next: the one with the most to do right now (enemies in reach, damage
## to escape), with seeded noise so the order isn't predictable.
func _choose_activation(units: Array[Unit]) -> Unit:
	var state := host.state
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.game_seed, state.round_number, state.acted.size(), "pick"])
	var best: Unit = units[0]
	var best_score := -INF
	for u in units:
		var score := rng.randf() * (0.5 + settings.randomness * 2.0)
		var near := INF
		for o: Unit in state.units.values():
			if o.side != u.side and not o.destroyed and not o.has_status("Hidden"):
				near = minf(near, state.map.grid.distance(u.cell, o.cell))
		score += 2.0 / maxf(near, 1.0) * (0.5 + settings.aggression)
		if u.has_status("Engaged"):
			score += 1.0
		score += TacticsAi._hurt(u) * settings.caution
		if score > best_score:
			best_score = score
			best = u
	return best


func _orders_for(u: Unit) -> Dictionary:
	var o: Dictionary = orders.get(u.id, {}).duplicate()
	if mission != null and not o.has("zones"):
		o.merge(mission.objective_for(u.side))
	return o


## Reinforcements (dial: reinforcements): once per round from round 3, in missions that
## allow them, a seeded roll may bring one NPC in at the enemy deployment edge.
func _maybe_reinforce() -> bool:
	var state := host.state
	if mission == null or not mission.allow_reinforcements or settings.reinforcements <= 0.0:
		return false
	if state.round_number < 3 or _reinforced_round == state.round_number or state.active_unit != "":
		return false
	_reinforced_round = state.round_number
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.game_seed, state.round_number, "reinforce"])
	if rng.randf() >= settings.reinforcements or mission.reinforcement_pool.is_empty():
		return false
	var pick: Dictionary = mission.reinforcement_pool[rng.randi_range(0, mission.reinforcement_pool.size() - 1)]
	var n := state.units.size() + 1
	while state.units.has("e%d" % n):
		n += 1
	var u := MissionGenerator.build_enemy(pick, UnitFactory.npc_templates(), "e%d" % n, n)
	var free := MissionGenerator._free_cells(mission.deployment.get(Mission.ENEMIES, []), rng)
	var probe := GameState.new(0, state.map.grid.shape)
	probe.map = state.map
	for o: Unit in state.units.values():
		if not o.destroyed:
			probe.units[o.id] = o
	if not MissionGenerator._place(probe, u, free):
		return false
	var out := host.submit(NetHost.GM_SEAT, {"type": "gm_spawn", "params": {"units": [u.to_dict()], "reason": "reinforcements"}})
	if (out["result"] as RuleResult).ok:
		_log(u.id, "Reinforcements: %s arrives." % u.name)
	return (out["result"] as RuleResult).ok


func _on_action_resolved(_seat: String, _action: Dictionary, _result: RuleResult, events: Array) -> void:
	if mission != null:
		mission.observe(host.state, events)


func _refused(u: Unit, action: Dictionary, result: RuleResult) -> void:
	refusals.append({"unit": u.id, "action": action, "reason": result.reason})
	_log(u.id, "%s couldn't %s: %s" % [TacticsAi._name(u), str(action.get("type", "")).replace("_", " "), result.reason])


func _log(unit_id: String, text: String) -> void:
	log_lines.append(text)
	ai_log.emit(unit_id, text)
