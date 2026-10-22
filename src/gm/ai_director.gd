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
## side -> unit id -> {"damage", "structure_lost"}: harm each side saw enemies take (AiKnowledge).
var seen_harm: Dictionary = {}
## unit id -> round its Hide was refused (someone it can't see has eyes on it).
var _no_hide: Dictionary = {}


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
	if state.phase == GameState.PHASE_ENDED or not host.paused_for.is_empty():
		return false
	if not state.pending.is_empty():
		# The engine is paused on a reaction question; answer it if an AI seat is being asked.
		return _answer_reaction()
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
		if mission != null and bool(mission.flavor.get("explore_first", false)):
			return _explore_step(first)
		return (host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": first}})["result"] as RuleResult).ok
	if mission != null:
		var carry := mission.carry_action()
		if not carry.is_empty():
			host.submit(NetHost.GM_SEAT, carry)
			return true
	if state.phase == GameState.PHASE_COMBAT and state.turn_mode == "explore" and state.active_unit == "" and _contact() != Vector2i(-99999, -99999):
		# Careful mode met the enemy: the turn-based exploring ends and the fight begins there.
		var at := _contact()
		host.submit(NetHost.GM_SEAT, {"type": "end_combat"})
		var first := mission.first_side if mission != null else Mission.PLAYERS
		_log("", "Contact: the fight starts.")
		return (host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": first, "center": [at.x, at.y], "radius": FIGHT_RADIUS}})["result"] as RuleResult).ok
	if _maybe_join():
		return true
	if _maybe_narrate():
		return true
	if _maybe_reinforce():
		return true
	if state.active_unit != "":
		var u := state.unit(state.active_unit)
		if u != null and NhpAi.auto(u):
			# An AI drives this mech by its own rules; its pilot answers first (NhpAi.question).
			var q := host.nhp_question()
			if not q.is_empty():
				if host.seat_present(q["seat"]):
					return false  # the pilot decides, no time limit
				var answer: Dictionary = q["default"]
				_log(u.id, "%s's AI pilot: %s." % [TacticsAi._name(u), "Shut Down" if answer.get("type", "") == "shut_down" else "let it act"])
				if answer.get("type", "") == "nhp_answer":
					host.nhp_answered[u.id] = host.state.round_number
					var order: Variant = answer.get("params", {}).get("order")
					if order is Dictionary:
						host.nhp_orders[u.id] = (order as Dictionary).duplicate()
				else:
					host.submit_ai(answer)
					host.nhp_answered[u.id] = host.state.round_number
				return true
			play_turn(u)
			return true
		if u != null and host.is_ai_seat(u.controller):
			play_turn(u)
			return true
		return false
	var mine: Array[Unit] = []
	var humans_waiting := false
	for u in TurnRules.waiting(state, state.turn_side):
		if host.is_ai_seat(u.controller):
			mine.append(u)
		else:
			humans_waiting = true
	if mine.is_empty():
		return false
	if not host.waiting_on()["ai"]:
		# Humans on this side choose who goes next, unless the AI squadmates go on their own
		# (only they are left, or the people pressed "Let the AI go").
		if not (host.ai_go_now or (host.ai_squad_auto and not humans_waiting)):
			return false
	host.ai_go_now = false
	var pick := _choose_activation(mine)
	var out := host.submit(pick.controller, {"type": "start_turn", "actor": pick.id})
	if not (out["result"] as RuleResult).ok:
		_refused(pick, {"type": "start_turn"}, out["result"])
		return false
	play_turn(pick)
	return true


## Plans and plays the active AI unit's whole turn, then ends it.
func play_turn(u: Unit) -> void:
	if host.state.turn_mode == "explore":
		# Turn-based exploring (careful mode): nobody's fighting yet; the AI's units hold
		# their ground until there's contact.
		host.submit_ai({"type": "end_turn", "actor": u.id})
		return
	var know := AiKnowledge.for_side(host.state, host.view_filter, u.side)
	know.seen_harm = seen_harm.get(u.side, {})
	var plan: Dictionary
	match NhpAi.kind(u):
		"sekhmet":
			plan = NhpAi.plan_sekhmet(know, u.id)
		"compcon":
			var o: Dictionary = host.nhp_orders.get(u.id, {"stance": "defensive"}).duplicate()
			if mission != null and not o.has("zones"):
				o.merge(mission.objective_for(u.side))
			plan = ai.plan_turn(know, u.id, o)
		_:
			plan = ai.plan_turn(know, u.id, _orders_for(u))
	if settings.explain:
		_log(u.id, plan["log"])
	var steps: Array = plan["steps"]
	if u.turn.get("braced", false):
		steps = _braced_steps(steps)
	for action: Dictionary in steps:
		if u.destroyed or host.state.active_unit != u.id:
			break
		var out := _submit(u, action)
		var asked := String((out["result"] as RuleResult).grey_area)
		if asked != "" and not Rulings.decided(host.state, asked) and _make_ruling(asked):
			out = _submit(u, action)  # the AI GM decided the open question; try again
		while _answer_reaction():
			pass
		if not host.state.pending.is_empty():
			return  # A human is deciding on a reaction; step() replans this turn afterwards.
		if not (out["result"] as RuleResult).ok:
			# The real battlefield differed from what this side knew (a Hidden enemy in the way...).
			_refused(u, action, out["result"])
	if host.state.active_unit == u.id and host.state.pending.is_empty():
		_submit(u, {"type": "end_turn", "actor": u.id})


## Units an AI drives by its own rules (NhpAi) act through the host's AI path; the rest
## through their seat like anyone.
func _submit(u: Unit, action: Dictionary) -> Dictionary:
	return host.submit_ai(action) if NhpAi.auto(u) else host.submit(u.controller, action)


## After Bracing, a unit's next turn is one quick action only: no normal move, no full or
## free actions (Core p.73). Keeps the first quick action of the plan.
static func _braced_steps(steps: Array) -> Array:
	for a: Dictionary in steps:
		var h: Variant = RulesEngine.registry.get(String(a.get("type", "")))
		if h is TurnAction and (h as TurnAction).cost_for(a.get("params", {})) == TurnRules.QUICK and not a.has("free_via"):
			return [a]
	return []


## Answers the engine's pending reaction question when an AI-played unit is being asked.
## Brace only when the hit would cost structure (same test as the GM's auto policy);
## Overwatch and prepared actions are always taken, Overwatch with the first weapon offered.
## Returns false if nothing was answered (no question, or a human is being asked).
## When the AI plays the GM seat, it makes the table's call on an open rules question with the
## suggested canon reading (Rulings), and logs it. A human GM decides for themselves.
func _make_ruling(id: String) -> bool:
	if not host.is_ai_seat(NetHost.GM_SEAT) or not Rulings.CATALOG.has(id):
		return false
	var out := host.submit(NetHost.GM_SEAT, {"type": "set_ruling", "params": {"id": id, "choice": Rulings.suggested(id)}})
	if (out["result"] as RuleResult).ok:
		_log("", "GM ruling: %s %s" % [Rulings.CATALOG[id]["question"], Rulings.CATALOG[id]["options"][Rulings.suggested(id)]])
	return (out["result"] as RuleResult).ok


func _answer_reaction() -> bool:
	var p: Dictionary = host.state.pending
	if p.is_empty():
		return false
	if p.has("ruling"):
		return _make_ruling(String(p["ruling"]))
	var u := host.state.unit(p.get("unit", ""))
	if u == null or not host.is_ai_seat(u.controller):
		return false
	var ctx: Dictionary = p.get("context", {})
	var params := {"take": true}
	match p.get("reaction", ""):
		"brace":
			params["take"] = Attacks._wants_brace(u, ctx.get("damage", []), ctx.get("ap", false))
		"overwatch":
			var weapons: Array = ctx.get("weapons", [])
			params["take"] = not weapons.is_empty()
			if not weapons.is_empty():
				params["weapon"] = weapons[0]
	var out := host.submit(u.controller, {"type": "react", "actor": u.id, "params": params})
	if not (out["result"] as RuleResult).ok:
		_refused(u, {"type": "react", "params": params}, out["result"])
		return false
	return true


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


# --- Exploring before the fight (DESIGN.md "Exploring vs. fighting") ------------------------

## Spaces between the squad and the enemy at which the fight starts (our pacing: about where
## they'd see each other across open ground).
const CONTACT := 10
## Units within this many spaces of the first contact take part; the rest keep exploring and
## can join later (join_combat).
const FIGHT_RADIUS := 16


## While the squad explores in real time: AI squadmates follow the nearest person on their
## side; once the squad and the enemy are within CONTACT, the fight starts around them.
func _explore_step(first: String) -> bool:
	var at := _contact()
	if at != Vector2i(-99999, -99999):
		_log("", "Contact: the squad sees the enemy. The fight starts.")
		return (host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": first, "center": [at.x, at.y], "radius": FIGHT_RADIUS}})["result"] as RuleResult).ok
	return _follow_step()


## Where the squad first meets the enemy (between the two), or (-99999, -99999).
func _contact() -> Vector2i:
	var state := host.state
	for p: Unit in state.units_on_side(Mission.PLAYERS):
		if p.destroyed:
			continue
		for e: Unit in state.units_on_side(Mission.ENEMIES):
			if not e.destroyed and state.map.grid.distance(p.cell, e.cell) <= CONTACT:
				return Vector2i((p.cell.x + e.cell.x) / 2, (p.cell.y + e.cell.y) / 2)
	return Vector2i(-99999, -99999)


## A unit still exploring (outside the fight) that comes within CONTACT of a fighting enemy
## joins the fight where it is (join_combat: it takes turns from the next round, Core p.60).
func _maybe_join() -> bool:
	var state := host.state
	if state.phase != GameState.PHASE_COMBAT or not state.pending.is_empty():
		return false
	for u: Unit in state.units.values():
		if u.destroyed or not bool(u.counters.get("exploring", false)):
			continue
		for o: Unit in state.units.values():
			if o.destroyed or o.side == u.side or bool(o.counters.get("exploring", false)):
				continue
			if state.map.grid.distance(u.cell, o.cell) <= CONTACT:
				var out := host.submit_ai({"type": "join_combat", "actor": u.id, "params": {"to": [u.cell.x, u.cell.y]}})
				if (out["result"] as RuleResult).ok:
					_log(u.id, "%s arrives and joins the fight (from the next round)." % u.name)
					return true
				break
	return false


## AI squadmates exploring follow the nearest person on their side (the user: AI players follow
## whatever you do), one step per call, keeping a couple of spaces back.
func _follow_step() -> bool:
	var state := host.state
	var people: Array[Unit] = []
	for u: Unit in state.units_on_side(Mission.PLAYERS):
		if not u.destroyed and not host.is_ai_seat(u.controller):
			people.append(u)
	if people.is_empty():
		return false
	for u: Unit in state.units_on_side(Mission.PLAYERS):
		if u.destroyed or not host.is_ai_seat(u.controller) or str(orders.get(u.id, {}).get("explore", "follow")) == "stay":
			continue
		var lead := people[0]
		for p: Unit in people:
			if state.map.grid.distance(u.cell, p.cell) < state.map.grid.distance(u.cell, lead.cell):
				lead = p
		var d := state.map.grid.distance(u.cell, lead.cell)
		if d <= 3:
			continue
		var line := state.map.grid.line(u.cell, lead.cell)
		for i in range(mini(u.speed, line.size() - 3), 0, -1):
			if (host.submit_ai({"type": "explore_move", "actor": u.id, "params": {"to": [line[i].x, line[i].y]}})["result"] as RuleResult).ok:
				return true
	return false


func _orders_for(u: Unit) -> Dictionary:
	var o: Dictionary = orders.get(u.id, {}).duplicate()
	if mission != null and not o.has("zones"):
		o.merge(mission.objective_for(u.side))
	if _no_hide.has(u.id) and host.state.round_number - int(_no_hide[u.id]) <= 2:
		o["no_hide"] = true  # an enemy it can't see has eyes on it: stop trying for a while
	return o


## The GM's narration (GmTwist): how the squad arrived, once combat starts, and the
## mission's hidden twist when its moment comes. Only an AI GM narrates on its own; a human
## GM reveals the twist themselves (GM tools, BattleSession.gm_reveal_twist).
func _maybe_narrate() -> bool:
	if mission == null or not host.is_ai_seat(NetHost.GM_SEAT):
		return false
	var a := GmTwist.next_action(mission, host.state)
	if a.is_empty() or (host.human_gm and str(a["params"].get("kind", "")) == "twist"):
		return false
	var out := host.submit(NetHost.GM_SEAT, a)
	GmTwist.done(mission, a)
	if (out["result"] as RuleResult).ok:
		_log("", "%s: %s" % [a["params"]["title"], a["params"]["text"]])
	return true


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
	_note_harm(events)
	if mission != null:
		mission.observe(host.state, events)
		GmTwist.observe(mission, host.state, events)


## Damage amounts and structure losses are public (every side sees them: ViewFilter keeps them);
## each side remembers them for enemies it can't read.
func _note_harm(events: Array) -> void:
	for e: Dictionary in events:
		var type := str(e.get("type", ""))
		if not type in ["damage_dealt", "structure_lost"]:
			continue
		var t := host.state.unit(str(e.get("target", e.get("unit", ""))))
		if t == null:
			continue
		for side: String in [Mission.PLAYERS, Mission.ENEMIES]:
			if side == t.side:
				continue
			if not seen_harm.has(side):
				seen_harm[side] = {}
			var h: Dictionary = seen_harm[side].get(t.id, {"damage": 0, "structure_lost": 0})
			if type == "damage_dealt":
				h["damage"] = int(h["damage"]) + int(e.get("amount", 0))
			else:
				h["structure_lost"] = int(h["structure_lost"]) + 1
			seen_harm[side][t.id] = h


func _refused(u: Unit, action: Dictionary, result: RuleResult) -> void:
	if str(action.get("type", "")) == "hide":
		_no_hide[u.id] = host.state.round_number
	refusals.append({"unit": u.id, "action": action, "reason": result.reason})
	_log(u.id, "%s couldn't %s: %s" % [TacticsAi._name(u), str(action.get("type", "")).replace("_", " "), result.reason])


func _log(unit_id: String, text: String) -> void:
	log_lines.append(text)
	ai_log.emit(unit_id, text)
