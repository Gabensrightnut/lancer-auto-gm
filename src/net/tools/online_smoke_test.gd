extends SceneTree
## Manual check of real online play (needs internet; not part of the unit tests):
##   godot --headless --path . -s res://src/net/tools/online_smoke_test.gd
## Opens a room through the real signaling server, joins it over WebRTC from the same
## machine, sends one action and a big message, and prints what happened.

var host: NetHost
var client: NetClient
var t := 0.0
var got_big := false
var done := false


func _init() -> void:
	if not WebRtcTransport.available():
		print("FAIL: WebRTC extension not loaded (addons/webrtc_native).")
		quit(1)
		return
	var s := GameState.new(7)
	s.seats = {"p1": {"name": "Player 1", "side": "players"}}
	var u := Unit.new()
	u.id = "mech"
	u.controller = "p1"
	s.add_unit(u)
	s.active_unit = "mech"
	host = NetHost.new(s, RulesEngine.new())
	host.room_opened.connect(_on_room_opened)
	host.open_failed.connect(func(r: String) -> void: _finish("FAIL host: " + r))
	host.open_room(WebRtcTransport.new())


func _on_room_opened(code: String) -> void:
	print("room open: ", code)
	client = NetClient.new(WebRtcTransport.new())
	client.joined.connect(func(seat: String) -> void:
		print("joined as ", seat, " after %.1fs" % t)
		client.submit({"type": "end_turn", "actor": "mech"}))
	client.join_failed.connect(func(r: String) -> void: _finish("FAIL join: " + r))
	client.refused.connect(func(_c: String, r: String) -> void: _finish("FAIL refused: " + r))
	client.action_answered.connect(func(_id: int, r: Dictionary) -> void:
		print("action answered: ok=", r["ok"])
		# A view bigger than one data-channel packet, to exercise chunking.
		var big := {"t": NetProtocol.UPDATE, "view": {"pad": "x".repeat(50000)}, "events": []}
		host.transport.send(host._seat_peer["p1"], big))
	client.view_updated.connect(func(v: Dictionary, _e: Array) -> void:
		if v.has("pad") and v["pad"].length() == 50000:
			_finish("PASS: joined, action resolved, 50 KB message arrived in %.1fs" % t))
	client.join(code, "Smoke tester")


func _process(delta: float) -> bool:
	t += delta
	if host != null:
		host.poll()
	if client != null:
		client.poll(delta)
	if t > 45.0 and not done:
		_finish("FAIL: timed out")
	return done


func _finish(msg: String) -> void:
	if done:
		return
	print(msg)
	done = true
	if client != null:
		client.leave()
	if host != null:
		host.close()
