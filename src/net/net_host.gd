class_name NetHost
extends RefCounted
## The host's side of a game session. Owns the GameState and RulesEngine; every action, from
## a remote client, a player at this machine or the procedural GM, comes through submit().
## After each change every seat gets only its own ViewFilter view and the events it may see.
##
## Seats are the ids in state.seats. A seat is either local (played on this machine: the
## host's own seat, or several for hot-seat) or taken by a remote client, who gets a token
## so it can take the same seat back after a dropped connection.

signal room_opened(room_code: String)
signal open_failed(reason: String)
## The seat table changed (someone joined, dropped or came back). See seat_table().
signal seats_changed(table: Dictionary)
## New view + events for a seat played on this machine.
signal local_update(seat: String, view: Dictionary, events: Array)
## Any action that went through the rules engine, from any seat.
signal action_resolved(seat: String, action: Dictionary, result: RuleResult, events: Array)
## Every seat has been sent its view for the latest change.
signal updates_sent(events: Array)
## A seated client sent a lobby message (ready-up). See LobbyModel.
signal lobby_message(seat: String, msg: Dictionary)
## Who the game is waiting on changed. See waiting_on().
signal waiting_changed(info: Dictionary)

var state: GameState
var engine: RulesEngine
var view_filter: ViewFilter
## AI-driven units (NhpAi: cascading NHP, SEKHMET, COMP/CON, Fourth Gate): unit id -> the round
## its pilot's seat answered the start-of-turn question, and a COMP/CON's standing command.
var nhp_answered: Dictionary = {}
var nhp_orders: Dictionary = {}
var transport: NetTransport
var room_code := ""
var local_seats := PackedStringArray()

## The procedural GM's seat (enemies, and host-only actions like starting combat).
const GM_SEAT := "gm"

## Seats an AI plays whenever no human is in them (drop-in: a friend who joins takes over,
## and the AI picks the seat back up when they leave). The GM seat is AI unless set false.
var ai_seats: Dictionary = {GM_SEAT: true}
## Host option, off by default: every seat nobody is sitting in gets an AI pilot.
var fill_empty_with_ai := false
## Seats kept empty for a friend who joins later (never filled by the AI).
var reserved_seats: Dictionary = {}

## Seats that must reconnect before a resumed mission goes on (see hold_until_back()).
var paused_for: Array = []
var _last_waiting: Dictionary = {}
var _peer_seat: Dictionary = {}  # peer -> seat
var _seat_peer: Dictionary = {}  # seat -> connected peer
var _seat_token: Dictionary = {}  # seat -> reconnect token (kept while the player is away)
var _player_names: Dictionary = {}  # seat -> name the player gave


func _init(game_state: GameState, rules_engine: RulesEngine, filter: ViewFilter = null) -> void:
	state = game_state
	engine = rules_engine
	view_filter = filter if filter != null else ViewFilter.new()


func remove_local_seat(seat: String) -> void:
	var i := local_seats.find(seat)
	if i >= 0:
		local_seats.remove_at(i)
		_seats_changed()


## Sends lobby info to every connected player.
func send_lobby(data: Dictionary) -> void:
	if transport == null:
		return
	for seat: String in _seat_peer:
		transport.send(_seat_peer[seat], {"t": NetProtocol.LOBBY, "lobby": data})


func add_local_seat(seat: String) -> void:
	assert(state.seats.has(seat), "unknown seat " + seat)
	if not seat in local_seats:
		local_seats.append(seat)


## Opens the game to remote players. Leave `code` empty for a fresh random room code.
func open_room(net: NetTransport, code: String = "") -> void:
	transport = net
	transport.hosted.connect(_on_hosted)
	transport.failed.connect(open_failed.emit)
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.message_received.connect(_on_message)
	transport.host(code if code != "" else NetProtocol.new_room_code())


func poll() -> void:
	if transport != null:
		transport.poll()


func close() -> void:
	if transport != null:
		transport.close()


## Runs an action for `seat` through the rules engine. A seat may only command units it
## controls. Returns {"result": RuleResult, "events": Array}.
##
## "I'll go": picking who acts next is a start_turn for that unit. In Lancer the players
## decide among themselves which of them goes next, so a human seat may pick its own unit,
## an AI squadmate on its side, or (people sharing this screen) any seat played here.
func submit(seat: String, action: Dictionary) -> Dictionary:
	if not paused_for.is_empty():
		return {"result": RuleResult.deny("Waiting for everyone to reconnect before the mission goes on.", ""), "events": []}
	var actor := state.unit(str(action.get("actor", "")))
	if actor != null and seat != GM_SEAT and NhpAi.auto(actor):
		return _pilot_of_ai_unit(seat, actor, action)
	if actor == null and seat != GM_SEAT:
		# Actions without an actor (start_combat, gm_spawn, gm_end_mission...) are the host's.
		return {"result": RuleResult.deny("Only the GM can do that.", ""), "events": []}
	if actor != null and action.get("type", "") == "start_turn" and actor.controller != seat:
		var why := _pick_refusal(seat, actor)
		if why != "":
			return {"result": RuleResult.deny(why, TurnRules.REF_TURN_ORDER), "events": []}
		return _run(actor.controller, action)
	if actor != null and actor.controller != seat:
		var no := RuleResult.deny("%s isn't yours to command." % actor.name if actor.name != "" else "That unit isn't yours to command.", "")
		return {"result": no, "events": []}
	return _run(seat, action)


## The AI (AiDirector) acting for a unit it drives by its own rules (NhpAi), whoever its
## controller is. Same engine, same updates; no seat check.
func submit_ai(action: Dictionary) -> Dictionary:
	if not paused_for.is_empty():
		return {"result": RuleResult.deny("Waiting for everyone to reconnect before the mission goes on.", ""), "events": []}
	var actor := state.unit(str(action.get("actor", "")))
	return _run(actor.controller if actor != null else GM_SEAT, action)


## A pilot whose mech an AI drives may still answer its start-of-turn question (nhp_answer),
## Shut Down a cascading NHP (the seat it had before the cascade), take back control, and
## react; everything else is the AI's (Core p.107; the systems' text).
func _pilot_of_ai_unit(seat: String, actor: Unit, action: Dictionary) -> Dictionary:
	if seat != NhpAi.pilot_seat(actor):
		return {"result": RuleResult.deny("%s isn't yours to command." % (actor.name if actor.name != "" else "That unit"), ""), "events": []}
	if not NhpAi.pilot_may(state, actor, action):
		return {"result": RuleResult.deny("%s's AI is in control: you can only answer it, Shut Down a cascade, or take back control." % actor.name, AISystems.REF), "events": []}
	var type := str(action.get("type", ""))
	if type == "nhp_answer":
		if state.active_unit != actor.id:
			return {"result": RuleResult.deny("Answer at the start of its turn.", AISystems.REF), "events": []}
		nhp_answered[actor.id] = state.round_number
		var order: Variant = action.get("params", {}).get("order")
		if order is Dictionary:
			nhp_orders[actor.id] = (order as Dictionary).duplicate()
		_waiting_check()
		_seats_changed()
		return {"result": RuleResult.allow(), "events": []}
	if type == "start_turn":
		var why := _pick_refusal(seat, actor) if actor.controller != seat else ""
		if why != "":
			return {"result": RuleResult.deny(why, TurnRules.REF_TURN_ORDER), "events": []}
		return _run(actor.controller, action)
	if type in ["shut_down", "activate", "ai_control"]:
		nhp_answered[actor.id] = state.round_number
	return _run(seat, action)


## The start-of-turn question for the active AI-driven unit's pilot (NhpAi.question), or {}
## when it's answered (or there's nothing to ask).
func nhp_question() -> Dictionary:
	var u := state.unit(state.active_unit) if state.active_unit != "" else null
	if u == null or not state.pending.is_empty() or int(nhp_answered.get(u.id, -1)) == state.round_number:
		return {}
	return NhpAi.question(state, u)


## The seat is played here or by a connected friend (not AI, not away).
func seat_present(seat: String) -> bool:
	if is_ai_seat(seat):
		return false
	return seat in local_seats or _seat_peer.has(seat)


func _run(seat: String, action: Dictionary) -> Dictionary:
	var out := engine.submit(state, action)
	var events: Array = out["events"]
	action_resolved.emit(seat, action, out["result"], events)
	if not events.is_empty():
		send_updates(events)
	return out


## Why `seat` may not pick `u` to act next ("" if it may).
## Seat setup worth keeping in a mission autosave: who sat where (reconnect tokens, names),
## AI and reserved seats, which seats are played at this machine. Host-only: never sent.
func export_seats() -> Dictionary:
	return {"tokens": _seat_token.duplicate(), "names": _player_names.duplicate(), "ai": ai_seats.duplicate(),
		"reserved": reserved_seats.duplicate(), "local": Array(local_seats), "fill_empty_with_ai": fill_empty_with_ai}


## Restores export_seats() on a resumed mission. Players who were connected get their seats
## back by reconnecting (their token), and the game holds until they all are.
func import_seats(d: Dictionary) -> void:
	_seat_token = (d.get("tokens", {}) as Dictionary).duplicate()
	_player_names = (d.get("names", {}) as Dictionary).duplicate()
	ai_seats = (d.get("ai", {GM_SEAT: true}) as Dictionary).duplicate()
	reserved_seats = (d.get("reserved", {}) as Dictionary).duplicate()
	fill_empty_with_ai = bool(d.get("fill_empty_with_ai", false))
	for seat: Variant in d.get("local", []):
		if state.seats.has(str(seat)):
			add_local_seat(str(seat))
	_seats_changed()


## Resuming a saved mission: nothing happens until every remote player is back (or the host
## lets the game go on without them with stop_holding()).
func hold_until_back() -> void:
	paused_for.clear()
	for seat: String in _seat_token:
		if not _seat_peer.has(seat) and not ai_seats.get(seat, false):
			paused_for.append(seat)
	_seats_changed()


func stop_holding() -> void:
	paused_for.clear()
	_seats_changed()


func _pick_refusal(seat: String, u: Unit) -> String:
	var info: Dictionary = state.seats.get(seat, {})
	if info.is_empty() or str(info.get("side", "")) != u.side:
		return "You can only choose who goes next on your own side."
	if is_ai_seat(seat):
		return "That seat is played by the AI."
	if is_ai_seat(u.controller):
		return ""  # An AI squadmate: the players choose when it goes.
	if seat in local_seats and u.controller in local_seats:
		return ""  # Several seats at this screen: the people here decide.
	return "%s belongs to another player, who has to choose to go themselves." % (u.name if u.name != "" else u.id)


## Who the game is waiting on, as `for_seat` may know it ("" = the host's full picture).
## {state: "setup"/"turn"/"pick"/"ended", seats: [seat ids that must act], ai: bool (the AI
##  is acting, no human needed), unit: active unit id (turn), side: side picking (pick),
##  units: unit ids that can still go (pick, own side only), you: bool (for_seat must act),
##  text: plain sentence for the UI}
## Nothing ever times out: a human seat is waited on until it acts.
func waiting_on(for_seat: String = "") -> Dictionary:
	var my_side: String = state.seats.get(for_seat, {}).get("side", "")
	var all_seen := for_seat == "" or for_seat == GM_SEAT
	var info := {"state": "", "seats": [], "ai": false, "unit": "", "side": "", "units": [], "text": ""}
	if not paused_for.is_empty():
		info["state"] = "reconnect"
		info["seats"] = paused_for.duplicate()
		var names := PackedStringArray()
		for seat: String in paused_for:
			names.append(_seat_name(seat))
		info["text"] = "Waiting for %s to reconnect." % ", ".join(names)
	elif state.phase == GameState.PHASE_ENDED:
		info["state"] = "ended"
		info["text"] = "The mission is over."
	elif state.phase != GameState.PHASE_COMBAT:
		info["state"] = "setup"
		info["ai"] = is_ai_seat(GM_SEAT)
		info["seats"] = [] if info["ai"] else [GM_SEAT]
		info["text"] = "The GM is setting up the battle." if info["ai"] else "Waiting for the GM to start the battle."
	elif state.pending.has("ruling"):
		# The engine is paused on an open rules question: the GM decides (set_ruling).
		info["state"] = "ruling"
		info["ai"] = is_ai_seat(GM_SEAT)
		info["seats"] = [] if info["ai"] else [GM_SEAT]
		info["text"] = "The GM is deciding a rules question: %s" % state.pending.get("context", {}).get("question", "")
	elif not state.pending.is_empty():
		# The engine is paused until this unit's controller decides on a reaction.
		var r := state.unit(state.pending.get("unit", ""))
		info["state"] = "reaction"
		info["ai"] = is_ai_seat(r.controller)
		info["seats"] = [] if info["ai"] else [r.controller]
		info["unit"] = r.id if all_seen or my_side == r.side else ""
		info["text"] = "Waiting for %s to decide whether to %s." % [
			(r.name if r.name != "" else r.id) if info["unit"] != "" else "an enemy",
			String(state.pending.get("reaction", "react")).capitalize()]
	elif not nhp_question().is_empty():
		# An AI drives this mech; its pilot decides one thing first (Shut Down, a command...).
		var q := nhp_question()
		var u := state.unit(state.active_unit)
		info["state"] = "nhp"
		info["ai"] = not seat_present(q["seat"])
		info["seats"] = [] if info["ai"] else [q["seat"]]
		info["unit"] = u.id if all_seen or my_side == u.side else ""
		if for_seat == q["seat"] or for_seat == "":
			info["question"] = {"kind": q["kind"], "text": q["text"], "options": q["options"]}
			info["text"] = q["text"]
		else:
			info["text"] = "Waiting for %s to decide what %s's AI does." % [_seat_name(q["seat"]), u.name]
	elif state.active_unit != "" and NhpAi.auto(state.unit(state.active_unit)):
		var u := state.unit(state.active_unit)
		info["state"] = "turn"
		info["ai"] = true
		info["unit"] = u.id if all_seen or my_side == u.side or not u.has_status("Hidden") else ""
		info["text"] = {"cascade": "%s's cascading NHP is acting.", "sekhmet": "SEKHMET drives %s.", "compcon": "%s's COMP/CON follows its command.",
			"fourth_gate": "%s fights for its new side (Fourth Gate)."}.get(NhpAi.kind(u), "%s's AI is acting.") % u.name
	elif state.active_unit != "":
		var u := state.unit(state.active_unit)
		info["state"] = "turn"
		info["ai"] = is_ai_seat(u.controller)
		info["seats"] = [] if info["ai"] else [u.controller]
		var seen := all_seen or my_side == u.side or not u.has_status("Hidden")
		info["unit"] = u.id if seen else ""
		var who := (u.name if u.name != "" else u.id) if seen else "A hidden enemy"
		if info["ai"]:
			info["text"] = "%s is taking its turn." % who
		else:
			info["text"] = "Waiting for %s: %s's turn." % [_seat_name(u.controller), who]
	else:
		var side := state.turn_side
		info["state"] = "pick"
		info["side"] = side
		var humans: Array = []
		for seat: String in state.seats:
			if str(state.seats[seat].get("side", "")) == side and not is_ai_seat(seat):
				humans.append(seat)
		info["seats"] = humans
		info["ai"] = humans.is_empty()
		if all_seen or my_side == side:
			for u in TurnRules.waiting(state, side):
				info["units"].append(u.id)
		if humans.is_empty():
			info["text"] = "The %s are choosing who acts next." % side
		else:
			var names := PackedStringArray()
			for seat: String in humans:
				names.append(_seat_name(seat))
			info["text"] = "%s pick: who goes next? (%s)" % [side.capitalize(), ", ".join(names)]
	info["you"] = for_seat != "" and for_seat in info["seats"]
	return info


func _seat_name(seat: String) -> String:
	var player: String = _player_names.get(seat, "")
	return player if player != "" else str(state.seats.get(seat, {}).get("name", seat))


func _waiting_check() -> void:
	var info := waiting_on()
	if info != _last_waiting:
		_last_waiting = info
		waiting_changed.emit(info)


## Sends every seat its view and the events it may see. Call this after anything that
## changes the state outside submit() (setting up a battle, loading a save).
func send_updates(events: Array = []) -> void:
	for seat: String in local_seats:
		var view := view_filter.view_for(state, seat)
		local_update.emit(seat, view, NetEventFilter.events_for(view_filter, state, seat, events, view))
	for seat: String in _seat_peer:
		_send_update(seat, events)
	updates_sent.emit(events)
	_waiting_check()


## Lets the AI play `seat` (or hands it back to people). Works mid-mission.
func set_seat_ai(seat: String, on: bool) -> void:
	ai_seats[seat] = on
	_seats_changed()


func set_fill_empty_with_ai(on: bool) -> void:
	fill_empty_with_ai = on
	_seats_changed()


func set_seat_reserved(seat: String, on: bool) -> void:
	if on:
		reserved_seats[seat] = true
	else:
		reserved_seats.erase(seat)
	_seats_changed()


## Is the AI playing this seat right now? A connected remote player always plays their seat;
## a seat set to AI is played by the AI otherwise (also a local one); with "fill empty seats"
## on, any seat nobody is sitting in (and not reserved) gets the AI too.
func is_ai_seat(seat: String) -> bool:
	if _seat_peer.has(seat):
		return false
	if ai_seats.get(seat, false):
		return true
	if seat in local_seats or reserved_seats.has(seat):
		return false
	return fill_empty_with_ai and state.seats.has(seat)


## seat -> {name, side, player, where: "local"/"remote"/"open", connected, ai, reserved}
func seat_table() -> Dictionary:
	var table := {}
	for seat: String in state.seats:
		var info: Dictionary = state.seats[seat]
		var where := "open"
		if seat in local_seats:
			where = "local"
		elif _seat_token.has(seat):
			where = "remote"
		table[seat] = {
			"name": info.get("name", seat), "side": info.get("side", ""),
			"player": _player_names.get(seat, ""), "where": where,
			"connected": where == "local" or _seat_peer.has(seat),
			"ai": is_ai_seat(seat), "reserved": reserved_seats.has(seat),
		}
	return table


## Frees a remote seat (e.g. the player isn't coming back) so someone else can take it.
func release_seat(seat: String) -> void:
	if _seat_peer.has(seat):
		transport.disconnect_peer(_seat_peer[seat])
	_seat_token.erase(seat)
	_player_names.erase(seat)
	_seats_changed()


func _send_update(seat: String, events: Array) -> void:
	var view := view_filter.view_for(state, seat)
	var seen := NetEventFilter.events_for(view_filter, state, seat, events, view)
	transport.send(_seat_peer[seat], {"t": NetProtocol.UPDATE, "view": view, "events": seen, "waiting": waiting_on(seat)})


func _on_hosted(code: String) -> void:
	room_code = code
	room_opened.emit(code)


func _on_peer_connected(_peer: int) -> void:
	pass  # Nothing is sent until the client says hello.


func _on_peer_disconnected(peer: int) -> void:
	var seat: String = _peer_seat.get(peer, "")
	_peer_seat.erase(peer)
	if seat != "" and _seat_peer.get(seat) == peer:
		_seat_peer.erase(seat)
		_seats_changed()


func _on_message(peer: int, msg: Dictionary) -> void:
	match msg.get("t"):
		NetProtocol.HELLO:
			_on_hello(peer, msg)
		NetProtocol.LOBBY:
			if _peer_seat.has(peer):
				lobby_message.emit(_peer_seat[peer], msg)
		NetProtocol.ACTION:
			var seat: String = _peer_seat.get(peer, "")
			var action: Variant = msg.get("action")
			if seat == "" or not action is Dictionary:
				return
			var out := submit(seat, action)
			transport.send(peer, {"t": NetProtocol.RESULT, "id": msg.get("id", 0), "result": (out["result"] as RuleResult).to_dict()})


func _on_hello(peer: int, msg: Dictionary) -> void:
	if _peer_seat.has(peer):
		return
	if str(msg.get("version", "")) != NetProtocol.game_version():
		_refuse(peer, NetProtocol.REFUSE_VERSION,
			"The host is on version %s and you're on %s. Close the game and open the launcher to update." % [NetProtocol.game_version(), msg.get("version", "?")])
		return
	var lacking := PackLibrary.missing(state.packs, msg.get("packs", []) if msg.get("packs") is Array else [])
	if not lacking.is_empty():
		_refuse(peer, NetProtocol.REFUSE_PACKS,
			"This game uses content packs you don't have (or a different version): %s. Add them to your packs folder and join again." % PackLibrary.describe(lacking))
		return
	var seat := ""
	var token := str(msg.get("token", ""))
	for s: String in _seat_token:
		if token != "" and _seat_token[s] == token:
			seat = s  # Coming back after a drop.
	if seat == "":
		var wanted := str(msg.get("seat", ""))
		if wanted != "":
			if not _seat_is_open(wanted):
				_refuse(peer, NetProtocol.REFUSE_SEAT_TAKEN, "That seat is already taken.")
				return
			seat = wanted
		else:
			for s: String in state.seats:
				if s != "gm" and _seat_is_open(s):
					seat = s
					break
		if seat == "":
			_refuse(peer, NetProtocol.REFUSE_FULL, "Every seat in this game is taken.")
			return
		_seat_token[seat] = NetProtocol.new_token()
	if _seat_peer.has(seat):
		# The old connection for this seat is stale; the new one replaces it.
		var old: int = _seat_peer[seat]
		_peer_seat.erase(old)
		transport.disconnect_peer(old)
	_peer_seat[peer] = seat
	_seat_peer[seat] = peer
	paused_for.erase(seat)
	_player_names[seat] = str(msg.get("name", "")).left(32)
	transport.send(peer, {
		"t": NetProtocol.WELCOME, "seat": seat, "token": _seat_token[seat],
		"room": room_code, "version": NetProtocol.game_version(),
	})
	_send_update(seat, [])
	_seats_changed()


func _seat_is_open(seat: String) -> bool:
	return state.seats.has(seat) and not seat in local_seats and not _seat_token.has(seat)


func _refuse(peer: int, code: String, reason: String) -> void:
	transport.send(peer, {"t": NetProtocol.REFUSED, "code": code, "reason": reason})
	transport.disconnect_peer(peer)


func _seats_changed() -> void:
	var table := seat_table()
	seats_changed.emit(table)
	_waiting_check()
	if transport == null:
		return
	for seat: String in _seat_peer:
		transport.send(_seat_peer[seat], {"t": NetProtocol.SEATS, "seats": table, "waiting": waiting_on(seat)})
