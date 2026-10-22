extends Node
## Autoload "Net": the one place the UI starts and ends play sessions. It keeps the current
## session ticking every frame. UI code connects to the session's own signals:
##
##   Single player / host:  var host := Net.start_local(state, engine, ["p1"])
##                          host.local_update -> draw view, animate events
##                          host.submit("p1", action) -> {"result": RuleResult, "events"}
##   Open it online:        Net.open_online(host)   then host.room_opened(code) -> show code
##   Hot-seat:              var hot := Net.start_hot_seat(state, engine, ["p1", "p2"])
##                          hot.handoff_requested / hot.confirm_handoff() / hot.view_updated
##   Join a friend:         var client := Net.join_online(code, "Name")
##                          client.joined / view_updated / action_answered / refused /
##                          join_failed / connection_lost; client.submit(action)
##   AI GM + squadmates:    var gm := Net.attach_ai(GmSettings.from_preset("Teaching"), mission)
##                          gm.ai_log(unit, text) -> battle log; host.set_seat_ai(seat, on)
## See src/net/README.md for the full API.

var host: NetHost
var hot_seat: HotSeat
var client: NetClient
## Plays AI seats (GM enemies, AI squadmates) on the host. See attach_ai().
var director: AiDirector
## Seconds between AI steps, so the board can animate each one.
var ai_step_interval := 0.6

var _ai_wait := 0.0


## True if online play works in this build (the WebRTC add-on loaded).
func online_available() -> bool:
	return WebRtcTransport.available()


## Starts a game hosted on this machine. `seats` are the seats played here.
func start_local(state: GameState, engine: RulesEngine, seats: Array, filter: ViewFilter = null) -> NetHost:
	leave()
	host = NetHost.new(state, engine, filter)
	for seat: String in seats:
		host.add_local_seat(seat)
	return host


## Several players at this screen. Call hot_seat.start() once the UI is listening.
func start_hot_seat(state: GameState, engine: RulesEngine, seats: Array, filter: ViewFilter = null) -> HotSeat:
	leave()
	host = NetHost.new(state, engine, filter)
	hot_seat = HotSeat.new(host, seats)
	return hot_seat


## Lets remote players join the hosted game. host.room_opened(code) gives the room code.
## Pass the saved room code when resuming a mission so players can rejoin the same room.
func open_online(game_host: NetHost = host, room_code: String = "") -> void:
	game_host.open_room(WebRtcTransport.new(), room_code)


func join_online(room_code: String, player_name: String, seat: String = "") -> NetClient:
	leave()
	client = NetClient.new(WebRtcTransport.new())
	client.packs = PackLibrary.new().installed_summaries()
	client.remember_session = true
	client.join(NetProtocol.normalize_room_code(room_code), player_name, seat)
	return client


## Rejoins the last online game from this computer with the same seat. null if none.
func rejoin_last() -> NetClient:
	if NetClient.last_session().is_empty():
		return null
	leave()
	client = NetClient.new(WebRtcTransport.new())
	client.packs = PackLibrary.new().installed_summaries()
	client.remember_session = true
	client.rejoin_last()
	return client


## Lets the procedural GM and AI squadmates play on the host started above. Which seats the
## AI plays: host.set_seat_ai(seat, true), host.set_fill_empty_with_ai(true); "gm" by default.
func attach_ai(gm_settings: GmSettings = null, mission: Mission = null) -> AiDirector:
	director = AiDirector.new(host, gm_settings, mission)
	return director


## Picks a saved mission back up on this (host) computer: same state and dice, same seats, same
## room code online. Play holds until every remote player has reconnected.
## Returns MissionAutosave.resume()'s result ({host, mission, settings, room, error}).
func resume_mission(store: SaveStore, campaign_id: String) -> Dictionary:
	leave()
	var r := MissionAutosave.resume(store, campaign_id)
	if r["error"] != "":
		return r
	host = r["host"]
	if not (host.export_seats()["tokens"] as Dictionary).is_empty():
		open_online(host, r["room"])
	director = AiDirector.new(host, r["settings"], r["mission"])
	host.hold_until_back()
	return r


func leave() -> void:
	if client != null:
		client.leave()
	if host != null:
		host.close()
	client = null
	host = null
	hot_seat = null
	director = null


func _process(delta: float) -> void:
	if host != null:
		host.poll()
	if client != null:
		client.poll(delta)
	if director != null:
		_ai_wait -= delta
		if _ai_wait <= 0.0 and director.step():
			_ai_wait = ai_step_interval
