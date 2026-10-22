class_name NetRoom
extends RefCounted
## One online room with several places in play at once (exploring, DESIGN.md "Exploring vs.
## fighting"): each area is its own NetHost (its GameState, rules engine and filtered views:
## exploring with explore_move, a fight there with start_combat/join_combat), and the room owns
## the real connection and puts each friend in the area their player is in. Friends only get
## the updates of their own area. Moving someone to another area hands their connection over;
## they keep their seat (and reconnect token).
##
##   var room := NetRoom.new()
##   room.add_area("town", town_host)       # NetHost per area, all with the same seats
##   room.open(transport, code)
##   room.move_seat("p2", "saltpan")        # travel, or a story event calling everyone
##
## Single-area games keep using NetHost.open_room directly ("one room, one game").

signal room_opened(code: String)
signal seat_moved(seat: String, area: String)

var transport: NetTransport
var room_code := ""
var default_area := ""
var areas: Dictionary = {}  # id -> {host: NetHost, link: AreaLink}
var _peer_area: Dictionary = {}  # peer -> area id
var _peer_seat: Dictionary = {}  # peer -> seat
var _seat_area: Dictionary = {}  # seat -> area id
var _hello: Dictionary = {}  # peer -> the client's hello
var _room_token: Dictionary = {}  # seat -> the token the client was given (first welcome)
var _area_token: Dictionary = {}  # area -> {seat: that area's token}
var _welcomed: Dictionary = {}  # peer -> true once the client has had its welcome


func add_area(id: String, host: NetHost) -> void:
	var link := AreaLink.new(self, id)
	areas[id] = {"host": host, "link": link}
	_area_token[id] = {}
	if default_area == "":
		default_area = id
	host.open_room(link, room_code)


func host_of(area: String) -> NetHost:
	return areas.get(area, {}).get("host")


func area_of(seat: String) -> String:
	return str(_seat_area.get(seat, ""))


func open(net: NetTransport, code: String = "") -> void:
	transport = net
	transport.hosted.connect(func(c: String) -> void:
		room_code = c
		room_opened.emit(c))
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.message_received.connect(_on_message)
	transport.host(code if code != "" else NetProtocol.new_room_code())


func poll() -> void:
	if transport != null:
		transport.poll()


## Puts a connected friend's seat in another area (their mech or pilot travelled there).
func move_seat(seat: String, area: String) -> bool:
	if not areas.has(area):
		return false
	var peer := _peer_of(seat)
	_seat_area[seat] = area
	if peer < 0 or str(_peer_area.get(peer, "")) == area:
		return peer >= 0
	_link(str(_peer_area[peer])).peer_disconnected.emit(peer)
	_enter(peer, area)
	seat_moved.emit(seat, area)
	return true


func _peer_of(seat: String) -> int:
	for p: int in _peer_seat:
		if _peer_seat[p] == seat:
			return p
	return -1


func _link(area: String) -> AreaLink:
	return areas[area]["link"]


func _on_message(peer: int, msg: Dictionary) -> void:
	if str(msg.get("t", "")) == NetProtocol.HELLO:
		_hello[peer] = msg.duplicate()
		var seat := ""
		for s: String in _room_token:
			if str(msg.get("token", "")) != "" and _room_token[s] == str(msg.get("token", "")):
				seat = s  # coming back after a drop
		if seat != "":
			_peer_seat[peer] = seat
			_welcomed[peer] = false  # they get the welcome again (with their room token)
		_enter(peer, area_of(seat) if seat != "" and area_of(seat) != "" else default_area)
		return
	if _peer_area.has(peer):
		_link(str(_peer_area[peer])).message_received.emit(peer, msg)


## Hands a connection to an area's host: as if the friend had just said hello there, for
## their seat (the area's own token for it if they've been there before).
func _enter(peer: int, area: String) -> void:
	_peer_area[peer] = area
	var hello: Dictionary = (_hello.get(peer, {}) as Dictionary).duplicate()
	hello.erase("token")
	var seat := str(_peer_seat.get(peer, ""))
	if seat != "":
		if (_area_token[area] as Dictionary).has(seat):
			hello["token"] = _area_token[area][seat]
		else:
			hello["seat"] = seat
	var link := _link(area)
	link.peer_connected.emit(peer)
	link.message_received.emit(peer, hello)


func _on_peer_disconnected(peer: int) -> void:
	if _peer_area.has(peer):
		_link(str(_peer_area[peer])).peer_disconnected.emit(peer)
	_peer_area.erase(peer)
	_peer_seat.erase(peer)
	_hello.erase(peer)
	_welcomed.erase(peer)


## An area host sending to a friend: welcomes are the room's (once, with the first token).
func _send_from(area: String, peer: int, msg: Dictionary) -> void:
	if str(msg.get("t", "")) == NetProtocol.WELCOME:
		var seat := str(msg.get("seat", ""))
		_area_token[area][seat] = str(msg.get("token", ""))
		_peer_seat[peer] = seat
		_seat_area[seat] = area
		if bool(_welcomed.get(peer, false)):
			return
		_welcomed[peer] = true
		if not _room_token.has(seat):
			_room_token[seat] = str(msg.get("token", ""))
		var m := msg.duplicate()
		m["token"] = _room_token[seat]
		transport.send(peer, m)
		return
	if str(_peer_area.get(peer, "")) == area or str(msg.get("t", "")) == NetProtocol.REFUSED:
		transport.send(peer, msg)


## The transport an area's NetHost sees: the room's friends who are in that area.
class AreaLink:
	extends NetTransport

	var room: NetRoom
	var area := ""

	func _init(r: NetRoom, id: String) -> void:
		room = r
		area = id
		is_host = true

	func host(code: String) -> void:
		hosted.emit.call_deferred(code)

	func send(peer: int, msg: Dictionary) -> void:
		room._send_from(area, peer, msg)

	func disconnect_peer(peer: int) -> void:
		if str(room._peer_area.get(peer, "")) == area and room.transport != null:
			room.transport.disconnect_peer(peer)
