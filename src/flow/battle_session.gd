class_name BattleSession
extends RefCounted
## One battle as the player experiences it, without any rendering (so it's testable): which
## seat's view is on screen, whose turn it is, picking who goes next ("I'll go"), hot-seat
## handoffs, pacing the AI (it waits while the screen animates), and the mission's end.
##
## Host (solo, hot-seat, online host): wraps NetHost + HotSeat + AiDirector + MissionAutosave.
## Online client: wraps NetClient. Either way the turn UI talks to `engine` (a SeatEngine) and
## plans on `mirror` (the on-screen seat's own picture of the battle).

## New view (and the events to animate) for the seat on screen.
signal view_updated(seat: String, view: Dictionary, events: Array)
## Hot-seat: hide the board and show "Pass to <name>"; call confirm_handoff() on Ready.
signal handoff(seat: String, display_name: String)
signal waiting_changed(info: Dictionary)
signal mission_over(outcome: String, reason: String)
signal log_line(text: String)
## An action the host refused (online: arrives after the fact).
signal refused(reason: String, rule_ref: String)
## Every batch of events the on-screen seat may see, including its own actions' (which
## view_updated leaves out because the turn UI plays them). For the tutorial and first-time tips.
signal events_seen(seat: String, events: Array)

var is_host := true
var host: NetHost
var hot: HotSeat
var director: AiDirector
var mission: Mission
var autosave: MissionAutosave
var client: NetClient
var engine := SeatEngine.new()
var mirror: GameState
## The seat whose view is on screen.
var seat := ""
var view: Dictionary = {}
## The screen is animating: the AI waits until it's done.
var busy := false
## Seconds between AI steps (the screen sets this from the animation speed setting).
var ai_interval := 0.4
var over := false
var outcome := ""
var outcome_reason := ""
var awaiting_handoff := false
## Every event of this battle (host), for the story's debrief (CampaignLoop.finish_mission).
var battle_events: Array = []
## Host: every batch of events the rules engine produced (all seats'), for the story.
signal host_events(events: Array)

## A human GM plays at this screen (campaign option "Human GM", host).
var gm_here := false
var _ai_wait := 0.0
## Exploring before (or around) a fight: unit id -> the cell it's walking to (WALK_STEP each).
var _walk: Dictionary = {}
var _walk_wait := 0.0
## Seconds per exploring step (a few spaces): walking in real time, not in turns.
const WALK_STEP := 0.35
## Spaces per exploring step (at most the unit's Speed: explore_move's own limit).
const WALK_SPACES := 2
var _local_humans: Array = []


## A battle hosted on this computer. `local_seats`: seats played by people at this screen.
static func for_host(net_host: NetHost, ai: AiDirector, the_mission: Mission, local_seats: Array, save: MissionAutosave = null) -> BattleSession:
	var s := BattleSession.new()
	s.host = net_host
	s.director = ai
	s.mission = the_mission
	s.autosave = save
	s._local_humans = local_seats.filter(func(x: String) -> bool: return not net_host.is_ai_seat(x))
	s.gm_here = net_host.human_gm and NetHost.GM_SEAT in local_seats
	var screen_seats: Array = s._local_humans.duplicate()
	if screen_seats.is_empty() and s.gm_here:
		# A human GM at this screen with no pilot here watches from the GM seat (the whole
		# picture). With pilots played here too the screen is theirs: the GM never takes a turn
		# (the AI flies the enemies) and the GM tools (G) open over it.
		screen_seats.append(NetHost.GM_SEAT)
	if screen_seats.is_empty():
		# Nobody plays here (everything AI or remote): watch from the squad's first seat.
		for id: String in net_host.state.seats:
			if str(net_host.state.seats[id].get("side", "")) == Mission.PLAYERS:
				screen_seats.append(id)
				break
	s.hot = HotSeat.new(net_host, screen_seats)
	s.hot.view_updated.connect(s._on_view)
	s.hot.handoff_requested.connect(s._on_handoff)
	s.engine.host = net_host
	net_host.waiting_changed.connect(s._on_waiting)
	net_host.action_resolved.connect(s._on_resolved)
	net_host.lobby_message.connect(func(from: String, msg: Dictionary) -> void:
		if bool(msg.get("pvp_yield", false)):
			s._yield(from))
	if ai != null:
		ai.mission_over.connect(s._on_mission_over)
		ai.ai_log.connect(s._on_ai_log)
	return s


## A battle hosted by a friend: we only see our seat's view.
static func for_client(net_client: NetClient) -> BattleSession:
	var s := BattleSession.new()
	s.is_host = false
	s.client = net_client
	s.seat = net_client.seat
	s.engine.client = net_client
	s.engine.seat = net_client.seat
	net_client.view_updated.connect(s._on_client_view)
	net_client.waiting_changed.connect(s._on_waiting)
	net_client.action_answered.connect(s._on_answer)
	if not net_client.view.is_empty():
		s._on_client_view(net_client.view, [])
	return s


func start() -> void:
	if is_host:
		hot.start(hot.seats[0])


## Call every frame.
func poll(delta: float) -> void:
	if not _walk.is_empty():
		_walk_wait -= delta
		if _walk_wait <= 0.0:
			_walk_wait = WALK_STEP
			_walk_step()
	if is_host:
		host.poll()
		_follow_waiting()
		if director != null and not busy and not over and not awaiting_handoff:
			_ai_wait -= delta
			if _ai_wait <= 0.0 and director.step():
				_ai_wait = ai_interval
	elif client != null:
		client.poll(delta)


# --- Exploring (DESIGN.md "Exploring vs. fighting") ---------------------------------------

## True while there are no turns for this screen's units: the squad explores the battlefield
## in real time before the fight (mission flavor explore_first), or a unit of ours is outside
## the fight going on (counters.exploring).
func exploring() -> bool:
	if careful():
		return false  # careful mode: moves take turns
	var phase := str(view.get("phase", ""))
	if phase == GameState.PHASE_SETUP:
		return true
	return phase == GameState.PHASE_COMBAT and not exploring_units().is_empty()


## This screen's units that can walk freely right now.
func exploring_units() -> Array:
	var out: Array = []
	var mine := _local_humans if is_host else [seat]
	var setup := str(view.get("phase", "")) == GameState.PHASE_SETUP
	for id: String in view.get("units", {}):
		var u: Dictionary = view["units"][id]
		if str(u.get("controller", "")) in mine and not bool(u.get("destroyed", false)) and (setup or bool((u.get("counters", {}) as Dictionary).get("exploring", false))):
			out.append(id)
	return out


## Walk a unit toward a cell in real time (exploring): a step every WALK_STEP seconds, each an
## explore_move through the rules engine. Returns "" or why not.
func walk_to(unit_id: String, cell: Vector2i) -> String:
	if not unit_id in exploring_units():
		return "That unit isn't free to walk right now."
	_walk[unit_id] = cell
	return ""


func _walk_step() -> void:
	for id: String in _walk.keys():
		var u: Dictionary = view.get("units", {}).get(id, {})
		var to: Vector2i = _walk[id]
		if u.is_empty() or not id in exploring_units():
			_walk.erase(id)
			continue
		var at := Vector2i(int(u["cell"][0]), int(u["cell"][1])) if u.get("cell") is Array else Vector2i(u.get("cell", Vector2i.ZERO))
		if at == to:
			_walk.erase(id)
			continue
		var next := _walk_next(id, at, to)
		if next == at or not _explore_move(id, next):
			_walk.erase(id)  # no way closer: stop where it is


## The next space toward `to`: of the spaces the rules say this unit can reach (around
## obstacles), the closest to `to`, preferring a short step so the walk looks continuous.
func _walk_next(id: String, at: Vector2i, to: Vector2i) -> Vector2i:
	var st: GameState = host.state if is_host else mirror
	var field := _walk_field(st, to)
	if not field.has(at):
		# The target is somewhere the walk field doesn't reach (up a steep rise): head straight
		# for it as far as the ground allows.
		field = {}
		for c: Vector2i in st.map.cells():
			field[c] = st.map.grid.distance(c, to)
	var here := int(field.get(at, 1 << 20))
	var best := at
	var best_key := Vector2(here, 1e9)
	for sp: Dictionary in RulesQueries.reachable(st, id).get("spaces", []):
		var c := Vector2i(int(sp["cell"][0]), int(sp["cell"][1]))
		var key := Vector2(int(field.get(c, 1 << 20)), maxi(0, int(sp.get("cost", 0)) - WALK_SPACES))
		if key.x < here and (key.y < best_key.y or (key.y == best_key.y and key.x < best_key.x)):
			best = c
			best_key = key
	return best


var _field_for := Vector2i(-99999, -99999)
var _field: Dictionary = {}


## Spaces from each cell to `to` over ground a walker can cross (no impassable terrain, steps
## of at most 1 level): the way around walls and cliffs. Cached per target.
func _walk_field(st: GameState, to: Vector2i) -> Dictionary:
	if to == _field_for:
		return _field
	_field_for = to
	_field = {to: 0}
	var queue: Array[Vector2i] = [to]
	var map := st.map
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n: Vector2i in map.grid.neighbors(c):
			if _field.has(n) or not map.has_cell(n) or map.column(n).has_tag(BattleMap.TAG_IMPASSABLE):
				continue
			if absi(map.ground_height(n) - map.ground_height(c)) > 1:
				continue
			_field[n] = int(_field[c]) + 1
			queue.append(n)
	return _field


func _explore_move(id: String, cell: Vector2i) -> bool:
	var a := {"type": "explore_move", "actor": id, "params": {"to": [cell.x, cell.y]}}
	if is_host:
		var u := host.state.unit(id)
		if u == null:
			return false
		var r: RuleResult = host.submit(u.controller, a)["result"]
		if r.ok and r.grey_area != "" and host.is_ai_seat(NetHost.GM_SEAT) and Rulings.CATALOG.has(r.grey_area):
			# A table ruling the step needs (e.g. uneven ground): the AI GM answers it with the
			# suggested reading, as it does in a fight, and the step goes again.
			host.submit(NetHost.GM_SEAT, {"type": "set_ruling", "params": {"id": r.grey_area, "choice": Rulings.suggested(r.grey_area)}})
			r = host.submit(u.controller, a)["result"]
		return r.ok and r.grey_area == ""
	client.submit(a)
	return true


## Careful mode (turn-based exploring, DESIGN.md: off by default, for heists and stealth): the
## host's GM switches exploring to turns (start_combat mode "explore") or back to real time
## (end_combat). Contact with the enemy turns it into the fight (AiDirector). Returns "" or why not.
func set_careful(on: bool) -> String:
	if not is_host:
		return "The host switches careful mode."
	var st := host.state
	if on:
		if st.phase != GameState.PHASE_SETUP:
			return "Careful mode is for exploring, before a fight."
		_walk.clear()
		var r: RuleResult = host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS, "mode": "explore"}})["result"]
		return "" if r.ok else r.reason
	if st.turn_mode != "explore":
		return "Careful mode is off."
	var r2: RuleResult = host.submit(NetHost.GM_SEAT, {"type": "end_combat"})["result"]
	return "" if r2.ok else r2.reason


func careful() -> bool:
	return str(view.get("turn_mode", "combat")) == "explore" and str(view.get("phase", "")) == GameState.PHASE_COMBAT


## A fight between the squad's two sides (a split vote, PvpBattle).
func is_split_fight() -> bool:
	if is_host:
		return PvpBattle.is_pvp(mission)
	return GameFlow.story_client != null and GameFlow.story_client.story != null and Decisions.current(GameFlow.story_client.story).has("split")


## "Yield": the person at this screen gives up for their side; once everyone on that side has,
## the other side wins (PvpBattle.yield_side). Online, the host decides.
func pvp_yield() -> void:
	if is_host:
		_yield(seat)
	elif client != null:
		client.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "pvp_yield": true})


func _yield(from: String) -> void:
	if not is_host or mission == null:
		return
	var a := PvpBattle.yield_side(mission, host.state, from)
	if not a.is_empty():
		mission.outcome = str(a["params"]["outcome"])
		mission.outcome_reason = str(a["params"]["reason"])
		mission.ended = true
		host.submit(NetHost.GM_SEAT, a)


## Who the game is waiting on, as the seat on screen may know it (NetHost.waiting_on).
func waiting() -> Dictionary:
	return host.waiting_on(seat) if is_host else client.waiting


## The unit whose turn the person at this screen should play now ("" if none).
func my_turn_unit() -> String:
	var w := waiting()
	return str(w.get("unit", "")) if w.get("state", "") == "turn" and w.get("you", false) and not awaiting_handoff else ""


## True when the people at this screen should choose who goes next.
func my_pick() -> bool:
	var w := waiting()
	return w.get("state", "") == "pick" and w.get("you", false) and not awaiting_handoff


## The question an AI-driven mech's pilot answers at the start of its turn ({} if none, or
## not for this screen): {kind, text, options: [{label, action, tip}]} (NhpAi.question).
func nhp_question() -> Dictionary:
	var w := waiting()
	if w.get("state", "") != "nhp" or not w.get("you", false) or awaiting_handoff:
		return {}
	return w.get("question", {})


## "Let the AI go": the AI activates one of its squadmates now (host).
func let_ai_go() -> void:
	if is_host:
		host.ai_go_now = true


## AI squadmates waiting to act on the side whose pick it is, when it's this screen's pick.
func ai_squadmates_waiting() -> Array:
	if not is_host or not my_pick():
		return []
	var out: Array = []
	for u in TurnRules.waiting(host.state, host.state.turn_side):
		if host.is_ai_seat(u.controller):
			out.append(u.id)
	return out


## Sends the chosen option's action (through the host, like any action).
func answer_nhp(action: Dictionary) -> void:
	engine.submit(mirror, action)


## The reaction question the engine is asking the people at this screen ({} if none):
## {id, unit, reaction: "brace"/"overwatch"/..., context: {weapons: [...], damage...}}.
func my_reaction() -> Dictionary:
	var w := waiting()
	if w.get("state", "") != "reaction" or not w.get("you", false) or awaiting_handoff:
		return {}
	return view.get("pending", {})


## Answers the reaction question: take it or not (Overwatch: which weapon).
func answer_reaction(take: bool, weapon: String = "") -> String:
	var p := my_reaction()
	if p.is_empty():
		return "Nothing to answer."
	var params := {"take": take}
	if weapon != "":
		params["weapon"] = weapon
	var action := {"type": "react", "actor": str(p.get("unit", "")), "params": params}
	if is_host:
		var out := host.submit(engine.seat, action)
		return "" if (out["result"] as RuleResult).ok else (out["result"] as RuleResult).reason
	client.submit(action)
	return ""


## "I'll go" with `unit_id` (yours or an AI squadmate's). Returns "" or why not.
func pick(unit_id: String) -> String:
	if is_host:
		var out := hot.pick_next(unit_id)
		return "" if (out["result"] as RuleResult).ok else (out["result"] as RuleResult).reason
	client.pick_next(unit_id)
	return ""


## Hot-seat: the next person has the screen.
func confirm_handoff() -> void:
	awaiting_handoff = false
	if is_host:
		hot.confirm_handoff()


func local_humans() -> Array:
	return _local_humans.duplicate()


## Seats played at this screen (by people or, after set_ai, by the AI).
func local_seats() -> Array:
	return Array(hot.seats) if is_host else [seat]


## Hands a seat at this screen to the AI, or takes it back (DESIGN: switch any time).
func set_ai(the_seat: String, on: bool) -> void:
	if not is_host or not the_seat in hot.seats:
		return
	host.set_seat_ai(the_seat, on)
	if on:
		_local_humans.erase(the_seat)
	elif not _local_humans.has(the_seat):
		_local_humans.append(the_seat)
	waiting_changed.emit(waiting())


## Hot-seat: the screen goes to whichever person here the game is waiting on, also when the
## engine asks someone else at this screen about a reaction (Brace, Overwatch).
func _follow_waiting() -> void:
	if busy or awaiting_handoff or hot.awaiting_handoff:
		return
	var w := host.waiting_on()
	if not w.get("state", "") in ["turn", "reaction", "nhp"] or (w.get("seats", []) as Array).is_empty():
		return
	var target: String = w["seats"][0]
	if target != hot.current_seat and target in hot.seats and _local_humans.has(target):
		hot.pass_to(target)


func _on_view(the_seat: String, the_view: Dictionary, events: Array) -> void:
	seat = the_seat
	engine.seat = the_seat
	view = the_view
	_sync_mirror()
	# Our own action: the turn UI already plays those events.
	view_updated.emit(the_seat, the_view, [] if engine.submitting else events)
	_seen(events)
	_check_end(events)


func _on_client_view(the_view: Dictionary, events: Array) -> void:
	seat = client.seat
	engine.seat = client.seat
	view = the_view
	_sync_mirror()
	view_updated.emit(seat, the_view, events)
	_seen(events)
	_check_end(events)


func _seen(events: Array) -> void:
	if not events.is_empty():
		events_seen.emit(seat, events)


func _on_resolved(_seat: String, _action: Dictionary, _result: RuleResult, events: Array) -> void:
	battle_events.append_array(events)
	if not events.is_empty():
		host_events.emit(events)


func _sync_mirror() -> void:
	if mirror == null:
		mirror = ViewMirror.build(view)
	else:
		ViewMirror.sync(mirror, view)


func _on_handoff(next_seat: String, display_name: String) -> void:
	if _local_humans.size() <= 1:
		hot.confirm_handoff()  # One person at this screen: nothing to hide.
		return
	awaiting_handoff = true
	handoff.emit(next_seat, display_name)


func _on_waiting(_info: Dictionary) -> void:
	waiting_changed.emit(waiting())


func _on_answer(_id: int, result: Dictionary) -> void:
	if not result.get("ok", true):
		refused.emit(str(result.get("reason", "")), str(result.get("rule_ref", "")))


func _on_ai_log(_unit: String, text: String) -> void:
	log_line.emit(text)


func _on_mission_over(the_outcome: String, reason: String) -> void:
	_finish(the_outcome, reason)


## A parley ended the fight (story event "battle_end_requested", Core p.60): the GM ends the
## mission with the agreed outcome, through the rules engine like any GM action. Host only.
func end_by_parley(e: Dictionary) -> bool:
	if not is_host or over or mission == null or mission.ended:
		return false
	var action := CampaignLoop.end_by_parley(mission, e)
	mission.ended = true
	return (host.submit(NetHost.GM_SEAT, action)["result"] as RuleResult).ok


## A human GM reveals the mission's twist (their GM tools, story event twist_revealed): the
## GM narrates it in the battle for the squad, as the AI GM would (Core p.43). Host only.
func gm_reveal_twist(twist: Dictionary) -> bool:
	if not is_host or over or mission == null or str(twist.get("reveal", "")).strip_edges() == "":
		return false
	var a := {"type": "gm_narrate", "params": {"kind": "twist", "id": str(twist.get("id", "")), "title": "Twist",
		"text": str(twist["reveal"]), "question": str(twist.get("question", "")), "seen_by": GmTwist.SEEN_BY.duplicate(), "rule_ref": GmTwist.REF}}
	GmTwist.done(mission, a)
	return (host.submit(NetHost.GM_SEAT, a)["result"] as RuleResult).ok


## This screen is a human GM's (their seat is the GM's).
func is_gm_screen() -> bool:
	return seat == NetHost.GM_SEAT


func _check_end(events: Array) -> void:
	for e: Dictionary in events:
		if e.get("type", "") == "mission_ended":
			_finish(str(e.get("outcome", "")), str(e.get("reason", "")))
	if not over and str(view.get("phase", "")) == GameState.PHASE_ENDED and not is_host:
		_finish(str(view.get("outcome", "none")), "")


func _finish(the_outcome: String, reason: String) -> void:
	if over:
		return
	over = true
	outcome = the_outcome
	outcome_reason = reason
	mission_over.emit(the_outcome, reason)
