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
## See src/net/README.md for the full API.

var host: NetHost
var hot_seat: HotSeat
var client: NetClient


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
func open_online(game_host: NetHost = host) -> void:
	game_host.open_room(WebRtcTransport.new())


func join_online(room_code: String, player_name: String, seat: String = "") -> NetClient:
	leave()
	client = NetClient.new(WebRtcTransport.new())
	client.join(NetProtocol.normalize_room_code(room_code), player_name, seat)
	return client


func leave() -> void:
	if client != null:
		client.leave()
	if host != null:
		host.close()
	client = null
	host = null
	hot_seat = null


func _process(delta: float) -> void:
	if host != null:
		host.poll()
	if client != null:
		client.poll(delta)
