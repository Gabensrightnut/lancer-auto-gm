class_name NetClient
extends RefCounted
## A remote player's side of a session. Never holds the real GameState: it gets its own
## filtered view from the host and sends actions for the host's rules engine to judge.
## If the connection drops it rejoins the same room with its seat token by itself.

## Seated: you play `seat`. Comes again after every reconnect.
signal joined(seat: String)
## The host turned us away. `code` is a NetProtocol.REFUSE_* value; `reason` is for the player.
signal refused(code: String, reason: String)
## Couldn't reach the room at all (wrong code, host offline, no internet).
signal join_failed(reason: String)
signal view_updated(view: Dictionary, events: Array)
## Answer to submit(): RuleResult.to_dict() (ok, reason, rule_ref, grey_area, options).
signal action_answered(request_id: int, result: Dictionary)
signal seats_changed(table: Dictionary)
## Lobby settings and seat rows from the host (LobbyModel.summary()).
signal lobby_updated(lobby: Dictionary)
## Who the game is waiting on changed (NetHost.waiting_on() as this seat may know it).
## info["you"] is true when it's waiting on you.
signal waiting_changed(info: Dictionary)
## Lost the host. `retrying` is true while reconnect attempts continue.
signal connection_lost(retrying: bool)

const RECONNECT_DELAYS := [1.0, 2.0, 4.0, 8.0, 15.0, 30.0]

var transport: NetTransport
var room_code := ""
var player_name := ""
var seat := ""
var token := ""
## The latest view from the host (empty until the first update).
var view: Dictionary = {}
## Who the game is waiting on (see waiting_changed).
var waiting: Dictionary = {}
var connected := false
## Content packs installed here, sent to the host so it can check we match the game's.
var packs: Array = []
## Remember the seat token on this computer, so rejoin_last() works even after a restart.
var remember_session := false

const SESSION_FILE := "user://net_session.json"
var auto_reconnect := true

var _wanted_seat := ""
var _next_request := 1
var _reconnect_try := -1  # -1: not reconnecting
var _reconnect_wait := 0.0
var _refused := false


func _init(net: NetTransport) -> void:
	transport = net
	transport.peer_connected.connect(_on_connected)
	transport.peer_disconnected.connect(_on_disconnected)
	transport.message_received.connect(_on_message)
	transport.failed.connect(_on_failed)


## Joins a room. `wanted_seat` may be "" to take any free seat.
func join(code: String, name: String, wanted_seat: String = "") -> void:
	room_code = code
	player_name = name
	_wanted_seat = wanted_seat
	_refused = false
	transport.join(code)


## Sends an action to the host. The answer arrives as action_answered(id, result); the
## resulting events arrive in the next view_updated.
func submit(action: Dictionary) -> int:
	var id := _next_request
	_next_request += 1
	transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.ACTION, "id": id, "action": action})
	return id


## Call every frame with the frame time.
func poll(delta: float = 0.0) -> void:
	transport.poll()
	if _reconnect_try >= 0 and _reconnect_wait > 0.0:
		_reconnect_wait -= delta
		if _reconnect_wait <= 0.0:
			_reconnect_wait = -1.0  # An attempt is under way; failure schedules the next.
			transport.close()
			transport.join(room_code)


func leave() -> void:
	auto_reconnect = false
	_reconnect_try = -1
	transport.close()
	connected = false


func _on_connected(_peer: int) -> void:
	connected = true
	transport.send(NetTransport.HOST_PEER, {
		"t": NetProtocol.HELLO, "version": NetProtocol.game_version(), "name": player_name,
		"token": token, "seat": _wanted_seat, "packs": packs,
	})


func _on_disconnected(_peer: int) -> void:
	var was_connected := connected
	connected = false
	if _reconnect_try >= 0:
		_retry_later()
	elif _refused or not auto_reconnect or seat == "":
		if was_connected and not _refused:
			connection_lost.emit(false)
	else:
		_reconnect_try = 0
		_reconnect_wait = RECONNECT_DELAYS[0]
		connection_lost.emit(true)


func _on_failed(reason: String) -> void:
	if _reconnect_try >= 0:
		_retry_later()
	else:
		join_failed.emit(reason)


func _retry_later() -> void:
	_reconnect_try += 1
	if _reconnect_try >= RECONNECT_DELAYS.size():
		_reconnect_try = -1
		connection_lost.emit(false)
		return
	_reconnect_wait = RECONNECT_DELAYS[_reconnect_try]


func _on_message(_peer: int, msg: Dictionary) -> void:
	match msg.get("t"):
		NetProtocol.WELCOME:
			seat = str(msg.get("seat", ""))
			token = str(msg.get("token", ""))
			if remember_session:
				var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
				if f != null:
					f.store_string(JSON.stringify({"room": room_code, "seat": seat, "token": token, "name": player_name}))
			_reconnect_try = -1
			joined.emit(seat)
		NetProtocol.REFUSED:
			_refused = true
			_reconnect_try = -1
			refused.emit(str(msg.get("code", "")), str(msg.get("reason", "")))
		NetProtocol.UPDATE:
			view = msg.get("view", {})
			view_updated.emit(view, msg.get("events", []))
			_set_waiting(msg.get("waiting", {}))
		NetProtocol.RESULT:
			action_answered.emit(int(msg.get("id", 0)), msg.get("result", {}))
		NetProtocol.LOBBY:
			if msg.get("lobby") is Dictionary:
				lobby_updated.emit(msg["lobby"])
		NetProtocol.SEATS:
			seats_changed.emit(msg.get("seats", {}))
			_set_waiting(msg.get("waiting", {}))


## Rejoins the last game this computer was in, taking back the same seat (e.g. after the
## host resumed a saved mission). Returns false if there's nothing to rejoin.
func rejoin_last() -> bool:
	var last := last_session()
	if last.is_empty():
		return false
	token = str(last.get("token", ""))
	join(str(last["room"]), str(last.get("name", "")), str(last.get("seat", "")))
	return true


static func last_session() -> Dictionary:
	if not FileAccess.file_exists(SESSION_FILE):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SESSION_FILE)) != OK or not json.data is Dictionary:
		return {}
	return json.data if json.data.has("room") else {}


## Lobby: tell the host we're ready (or not).
func send_ready(is_ready: bool) -> void:
	transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "ready": is_ready})


## "I'll go": ask to take the next turn with `unit_id` (yours, or an AI squadmate's).
func pick_next(unit_id: String) -> int:
	return submit({"type": "start_turn", "actor": unit_id})


func _set_waiting(info: Variant) -> void:
	if info is Dictionary and not (info as Dictionary).is_empty() and info != waiting:
		waiting = info
		waiting_changed.emit(waiting)
