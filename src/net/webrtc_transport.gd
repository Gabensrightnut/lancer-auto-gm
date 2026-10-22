class_name WebRtcTransport
extends NetTransport
## Online play: direct player-to-player WebRTC data channels, so nobody opens ports.
## A PeerJS signaling server (see NetConfig) is only used to swap connection offers when a
## player joins; game messages go straight between the host and each client.
##
## Needs the webrtc-native GDExtension (addons/webrtc_native) on desktop. available() says
## whether it loaded.

## Longest message text put in one data-channel packet; longer ones are split into chunks.
const CHUNK_CHARS := 12000
## How long to wait before closing a link we cut, so the last message (e.g. a refusal) gets out.
const CLOSE_DELAY_MS := 500
## A host that loses the signaling server retries this often.
const REOPEN_DELAY_MS := 10000

var config: Dictionary
var room := ""

var _sig: PeerJsSignaling
## peer -> {pc, ch, remote (signaling id), conn (PeerJS connection id), open, chunks}
var _peers: Dictionary = {}
var _by_remote: Dictionary = {}  # signaling id -> peer
var _next_peer := NetTransport.HOST_PEER + 1
var _closing: Dictionary = {}  # peer -> time (msec) to close it
var _join_deadline_ms := 0
var _chunk_seq := 0
var _hosted := false
var _reopen_at_ms := 0


func _init(cfg: Dictionary = {}) -> void:
	config = cfg if not cfg.is_empty() else NetConfig.load_config()


## True if WebRTC works in this build (the GDExtension loaded).
static func available() -> bool:
	var pc := WebRTCPeerConnection.new()
	var ok := pc.initialize({}) == OK
	pc.close()
	return ok


func host(room_code: String) -> void:
	close()
	is_host = true
	room = room_code
	_sig = _new_signaling()
	_sig.opened.connect(_on_host_signaling_open)
	_sig.open(_host_id(room_code))


func join(room_code: String) -> void:
	close()
	is_host = false
	room = room_code
	_sig = _new_signaling()
	_sig.opened.connect(_on_client_signaling_open)
	_sig.peer_gone.connect(_on_client_host_gone)
	_join_deadline_ms = Time.get_ticks_msec() + int(float(config.get("join_timeout_sec", 25.0)) * 1000.0)
	_sig.open("%s-c-%s" % [config.get("id_prefix", "lancerautogm"), Crypto.new().generate_random_bytes(6).hex_encode()])


func send(peer: int, msg: Dictionary) -> void:
	var p: Dictionary = _peers.get(peer, {})
	if not p.get("open", false):
		return
	var ch: WebRTCDataChannel = p["ch"]
	var text := JSON.stringify(msg)
	if text.length() <= CHUNK_CHARS:
		ch.put_packet(text.to_utf8_buffer())
		return
	# "#<msg id>,<index>,<count>|<part>": reassembled in order by _on_packet.
	_chunk_seq += 1
	var count := ceili(float(text.length()) / CHUNK_CHARS)
	for i in range(count):
		var part := text.substr(i * CHUNK_CHARS, CHUNK_CHARS)
		ch.put_packet(("#%d,%d,%d|" % [_chunk_seq, i, count] + part).to_utf8_buffer())


func poll() -> void:
	var now := Time.get_ticks_msec()
	if is_host and _hosted and _sig == null and now >= _reopen_at_ms:
		_sig = _new_signaling()
		_sig.opened.connect(_on_host_signaling_open)
		_sig.open(_host_id(room))
	if _sig != null:
		_sig.poll()
	for peer: int in _peers.keys():
		if not _peers.has(peer):
			continue
		var p: Dictionary = _peers[peer]
		var pc: WebRTCPeerConnection = p["pc"]
		var ch: WebRTCDataChannel = p["ch"]
		pc.poll()
		if not p["open"] and ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			p["open"] = true
			if not is_host and _sig != null:
				_sig.close()  # Connected: the matchmaking server isn't needed any more.
				_sig = null
			peer_connected.emit(peer)
		while _peers.has(peer) and ch.get_available_packet_count() > 0:
			_on_packet(peer, ch.get_packet().get_string_from_utf8())
		var pc_state := pc.get_connection_state()
		var dead := pc_state == WebRTCPeerConnection.STATE_FAILED or pc_state == WebRTCPeerConnection.STATE_CLOSED
		if p["open"] and ch.get_ready_state() == WebRTCDataChannel.STATE_CLOSED:
			dead = true
		if _closing.has(peer) and now >= int(_closing[peer]):
			dead = true
		if dead and _peers.has(peer):
			var was_open: bool = p["open"]
			_drop(peer)
			if was_open or is_host:
				peer_disconnected.emit(peer)
			else:
				failed.emit("Couldn't connect to the host. Their network or yours may block direct connections.")
	if not is_host and _join_deadline_ms > 0 and not _peers.get(NetTransport.HOST_PEER, {}).get("open", false):
		if now > _join_deadline_ms:
			_join_deadline_ms = 0
			_give_up("No answer from room %s. Check the code and that the host has the game open." % room)
	elif not is_host:
		_join_deadline_ms = 0


func disconnect_peer(peer: int) -> void:
	if _peers.has(peer):
		_closing[peer] = Time.get_ticks_msec() + CLOSE_DELAY_MS


func close() -> void:
	if _sig != null:
		_sig.close()
		_sig = null
	for peer: int in _peers.keys():
		_drop(peer)
	_closing.clear()
	_join_deadline_ms = 0
	_hosted = false


func _new_signaling() -> PeerJsSignaling:
	var sig := PeerJsSignaling.new(config["signaling"])
	sig.failed.connect(_on_signaling_failed)
	sig.received.connect(_on_signal)
	return sig


func _host_id(room_code: String) -> String:
	return "%s-%s" % [config.get("id_prefix", "lancerautogm"), room_code]


func _new_peer(peer: int, remote: String, conn: String = "") -> Dictionary:
	var pc := WebRTCPeerConnection.new()
	pc.initialize({"iceServers": config.get("ice_servers", [])})
	# Negotiated channel: both ends create it with the same id, no extra handshake.
	var ch := pc.create_data_channel("game", {"negotiated": true, "id": 1})
	ch.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
	pc.session_description_created.connect(_on_description.bind(peer))
	pc.ice_candidate_created.connect(_on_candidate.bind(peer))
	if conn == "":
		conn = "dc_" + Crypto.new().generate_random_bytes(6).hex_encode()
	var p := {"pc": pc, "ch": ch, "remote": remote, "conn": conn, "open": false, "chunks": {}}
	_peers[peer] = p
	_by_remote[remote] = peer
	return p


func _drop(peer: int) -> void:
	var p: Dictionary = _peers.get(peer, {})
	_peers.erase(peer)
	_closing.erase(peer)
	if p.is_empty():
		return
	_by_remote.erase(p["remote"])
	(p["ch"] as WebRTCDataChannel).close()
	(p["pc"] as WebRTCPeerConnection).close()


func _on_host_signaling_open() -> void:
	if not _hosted:
		_hosted = true
		hosted.emit(room)


func _on_client_signaling_open() -> void:
	var p := _new_peer(NetTransport.HOST_PEER, _host_id(room))
	(p["pc"] as WebRTCPeerConnection).create_offer()


func _on_client_host_gone(src: String) -> void:
	if src == _host_id(room) and not _peers.get(NetTransport.HOST_PEER, {}).get("open", false):
		_give_up("No game is open with room code %s." % room)


func _on_signaling_failed(reason: String, id_taken: bool) -> void:
	if is_host and _hosted:
		# Players already in stay connected (game traffic doesn't use the server). Keep
		# trying to reopen the room so new players and reconnects can get in.
		_sig = null
		_reopen_at_ms = Time.get_ticks_msec() + REOPEN_DELAY_MS
		return
	_give_up(reason if not id_taken else "Room code %s is already in use." % room)


func _give_up(reason: String) -> void:
	close()
	failed.emit(reason)


# Payloads follow the official PeerJS client's format exactly: the public server drops
# senders whose messages don't match it.
func _on_signal(type: String, src: String, payload: Dictionary) -> void:
	var desc: Variant = payload.get("sdp", {})
	match type:
		"OFFER":
			if not is_host or not desc is Dictionary:
				return
			if _by_remote.has(src):
				_drop(_by_remote[src])
			var peer := _next_peer
			_next_peer += 1
			var p := _new_peer(peer, src, str(payload.get("connectionId", "")))
			(p["pc"] as WebRTCPeerConnection).set_remote_description("offer", str(desc.get("sdp", "")))
		"ANSWER":
			var p: Dictionary = _peers.get(_by_remote.get(src, -1), {})
			if not p.is_empty() and desc is Dictionary:
				(p["pc"] as WebRTCPeerConnection).set_remote_description("answer", str(desc.get("sdp", "")))
		"CANDIDATE":
			var p: Dictionary = _peers.get(_by_remote.get(src, -1), {})
			var c: Variant = payload.get("candidate", {})
			if not p.is_empty() and c is Dictionary:
				(p["pc"] as WebRTCPeerConnection).add_ice_candidate(
					str(c.get("sdpMid", "")), int(c.get("sdpMLineIndex", 0)), str(c.get("candidate", "")))


func _on_description(type: String, sdp: String, peer: int) -> void:
	var p: Dictionary = _peers.get(peer, {})
	if p.is_empty() or _sig == null:
		return
	(p["pc"] as WebRTCPeerConnection).set_local_description(type, sdp)
	var payload := {"sdp": {"sdp": sdp, "type": type}, "type": "data", "connectionId": p["conn"]}
	if type == "offer":
		payload.merge({"label": p["conn"], "reliable": false, "serialization": "binary"})
	_sig.send(type.to_upper(), p["remote"], payload)


func _on_candidate(media: String, index: int, name: String, peer: int) -> void:
	var p: Dictionary = _peers.get(peer, {})
	if not p.is_empty() and _sig != null:
		_sig.send("CANDIDATE", p["remote"], {
			"candidate": {"candidate": name, "sdpMid": media, "sdpMLineIndex": index},
			"type": "data", "connectionId": p["conn"],
		})


func _on_packet(peer: int, text: String) -> void:
	if text.begins_with("#"):
		var bar := text.find("|")
		var head := text.substr(1, bar - 1).split(",")
		if bar < 0 or head.size() != 3:
			return
		var chunks: Dictionary = _peers[peer]["chunks"]
		var parts: Array = chunks.get(head[0], [])
		if parts.is_empty():
			parts.resize(int(head[2]))
			chunks[head[0]] = parts
		parts[int(head[1])] = text.substr(bar + 1)
		if parts.has(null):
			return
		chunks.erase(head[0])
		text = "".join(PackedStringArray(parts))
	var msg: Variant = JSON.parse_string(text)
	if msg is Dictionary:
		message_received.emit(peer, msg)
