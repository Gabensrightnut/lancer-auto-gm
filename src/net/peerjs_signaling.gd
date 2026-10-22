class_name PeerJsSignaling
extends RefCounted
## Talks to a PeerJS server (https://github.com/peers/peerjs-server) over a WebSocket to swap
## WebRTC connection offers. The server only relays small JSON messages between ids; the game
## itself never goes through it.
##
## Server -> us: {"type": "OPEN"} | {"type": "ID-TAKEN"} | {"type": "ERROR", "payload": {"msg"}}
##               {"type": "OFFER"/"ANSWER"/"CANDIDATE", "src": id, "payload": {...}}
##               {"type": "LEAVE"/"EXPIRE", "src": id}   (that id is gone / never came)
## Us -> server: {"type": "OFFER"/"ANSWER"/"CANDIDATE", "dst": id, "payload": {...}}
##               (the public server drops senders whose payloads don't look like the official
##               PeerJS client's; WebRtcTransport builds them to match)
##               {"type": "HEARTBEAT"} every few seconds.

signal opened
signal failed(reason: String, id_taken: bool)
signal received(type: String, src: String, payload: Dictionary)
signal peer_gone(src: String)

const HEARTBEAT_MS := 5000
const OPEN_TIMEOUT_MS := 15000

var id := ""
var is_open := false

var _server: Dictionary
var _ws := WebSocketPeer.new()
var _started_ms := 0
var _last_beat_ms := 0
var _active := false


func _init(server: Dictionary) -> void:
	_server = server


func open(peer_id: String) -> void:
	close()
	id = peer_id
	var url := "%s://%s:%d%speerjs?key=%s&id=%s&token=%s&version=1.5.4" % [
		"wss" if _server.get("secure", true) else "ws", _server["host"], int(_server["port"]),
		_server.get("path", "/"), _server.get("key", "peerjs"), peer_id,
		Crypto.new().generate_random_bytes(8).hex_encode()]
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url)
	_active = true
	_started_ms = Time.get_ticks_msec()
	if err != OK:
		_fail("Couldn't reach the matchmaking server (error %d)." % err, false)


func send(type: String, dst: String, payload: Dictionary) -> void:
	if is_open:
		_ws.send_text(JSON.stringify({"type": type, "dst": dst, "payload": payload}))


func poll() -> void:
	if not _active:
		return
	_ws.poll()
	var now := Time.get_ticks_msec()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if now - _last_beat_ms > HEARTBEAT_MS:
				_last_beat_ms = now
				_ws.send_text('{"type":"HEARTBEAT"}')
			while _active and _ws.get_available_packet_count() > 0:
				_on_text(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_fail("Lost the matchmaking server (code %d)." % _ws.get_close_code(), false)
		WebSocketPeer.STATE_CONNECTING:
			if now - _started_ms > OPEN_TIMEOUT_MS:
				_fail("The matchmaking server didn't answer. Check your internet connection.", false)


func close() -> void:
	if _active:
		_ws.close()
	_active = false
	is_open = false


func _on_text(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	var type := str(msg.get("type", ""))
	var src := str(msg.get("src", ""))
	match type:
		"OPEN":
			is_open = true
			opened.emit()
		"ID-TAKEN":
			_fail("That room code is already in use.", true)
		"ERROR":
			var payload: Variant = msg.get("payload", {})
			_fail("Matchmaking server error: %s" % (payload.get("msg", "") if payload is Dictionary else str(payload)), false)
		"LEAVE", "EXPIRE":
			peer_gone.emit(src)
		"OFFER", "ANSWER", "CANDIDATE":
			var payload: Variant = msg.get("payload", {})
			if payload is Dictionary:
				received.emit(type, src, payload)


func _fail(reason: String, id_taken: bool) -> void:
	close()
	failed.emit(reason, id_taken)
