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

var state: GameState
var engine: RulesEngine
var view_filter: ViewFilter
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

var _peer_seat: Dictionary = {}  # peer -> seat
var _seat_peer: Dictionary = {}  # seat -> connected peer
var _seat_token: Dictionary = {}  # seat -> reconnect token (kept while the player is away)
var _player_names: Dictionary = {}  # seat -> name the player gave


func _init(game_state: GameState, rules_engine: RulesEngine, filter: ViewFilter = null) -> void:
	state = game_state
	engine = rules_engine
	view_filter = filter if filter != null else ViewFilter.new()


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
func submit(seat: String, action: Dictionary) -> Dictionary:
	var actor := state.unit(str(action.get("actor", "")))
	if actor == null and seat != GM_SEAT:
		# Actions without an actor (start_combat, gm_spawn, gm_end_mission...) are the host's.
		return {"result": RuleResult.deny("Only the GM can do that.", ""), "events": []}
	if actor != null and actor.controller != seat:
		var no := RuleResult.deny("%s isn't yours to command." % actor.name if actor.name != "" else "That unit isn't yours to command.", "")
		return {"result": no, "events": []}
	var out := engine.submit(state, action)
	var events: Array = out["events"]
	action_resolved.emit(seat, action, out["result"], events)
	if not events.is_empty():
		send_updates(events)
	return out


## Sends every seat its view and the events it may see. Call this after anything that
## changes the state outside submit() (setting up a battle, loading a save).
func send_updates(events: Array = []) -> void:
	for seat: String in local_seats:
		var view := view_filter.view_for(state, seat)
		local_update.emit(seat, view, NetEventFilter.events_for(view_filter, state, seat, events, view))
	for seat: String in _seat_peer:
		_send_update(seat, events)
	updates_sent.emit(events)


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
	transport.send(_seat_peer[seat], {"t": NetProtocol.UPDATE, "view": view, "events": seen})


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
	if transport == null:
		return
	for seat: String in _seat_peer:
		transport.send(_seat_peer[seat], {"t": NetProtocol.SEATS, "seats": table})
