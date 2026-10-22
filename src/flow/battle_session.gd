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

var _ai_wait := 0.0
var _local_humans: Array = []


## A battle hosted on this computer. `local_seats`: seats played by people at this screen.
static func for_host(net_host: NetHost, ai: AiDirector, the_mission: Mission, local_seats: Array, save: MissionAutosave = null) -> BattleSession:
	var s := BattleSession.new()
	s.host = net_host
	s.director = ai
	s.mission = the_mission
	s.autosave = save
	s._local_humans = local_seats.filter(func(x: String) -> bool: return not net_host.is_ai_seat(x))
	var screen_seats: Array = s._local_humans.duplicate()
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
	if is_host:
		host.poll()
		_follow_waiting()
		if director != null and not busy and not over and not awaiting_handoff:
			_ai_wait -= delta
			if _ai_wait <= 0.0 and director.step():
				_ai_wait = ai_interval
	elif client != null:
		client.poll(delta)


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
