class_name LoopbackTransport
extends NetTransport
## In-memory transport: a host and its clients in one process, linked through a shared Hub.
## Used by tests and hot-seat. Messages still go through JSON text, exactly as they would on
## the wire, and the hub keeps a log of every byte sent so tests can check for leaks.

## Shared "network" for loopback transports: open rooms and a log of everything sent.
class Hub:
	extends RefCounted
	var rooms: Dictionary = {}  # room code -> WeakRef to the host LoopbackTransport
	## Every message sent: {"from": int, "to": int, "room": String, "text": String}.
	var wire_log: Array[Dictionary] = []

	## Everything that was sent to one client, as raw text.
	func text_sent_to(room: String, peer: int) -> String:
		var out := PackedStringArray()
		for m in wire_log:
			if m["room"] == room and m["to"] == peer:
				out.append(m["text"])
		return "\n".join(out)


var hub: Hub
var room := ""
## This end's peer id (HOST_PEER for the host).
var peer_id := 0
var _links: Dictionary = {}  # peer id -> WeakRef to the LoopbackTransport at the other end
var _inbox: Array = []  # [kind, peer, payload] waiting for poll()
var _next_peer := NetTransport.HOST_PEER + 1


func _init(shared_hub: Hub) -> void:
	hub = shared_hub


func host(room_code: String) -> void:
	is_host = true
	peer_id = NetTransport.HOST_PEER
	if _ref(hub.rooms.get(room_code)) != null:
		_inbox.append(["failed", 0, "Room %s is already open." % room_code])
		return
	room = room_code
	hub.rooms[room] = weakref(self)
	_inbox.append(["hosted", 0, room])


func join(room_code: String) -> void:
	is_host = false
	var host_end: LoopbackTransport = _ref(hub.rooms.get(room_code))
	if host_end == null:
		_inbox.append(["failed", 0, "No game with room code %s." % room_code])
		return
	room = room_code
	peer_id = host_end._next_peer
	host_end._next_peer += 1
	_links = {NetTransport.HOST_PEER: weakref(host_end)}
	host_end._links[peer_id] = weakref(self)
	host_end._inbox.append(["connected", peer_id, null])
	_inbox.append(["connected", NetTransport.HOST_PEER, null])


func send(peer: int, msg: Dictionary) -> void:
	var other: LoopbackTransport = _ref(_links.get(peer))
	if other == null:
		return
	var text := JSON.stringify(msg)
	hub.wire_log.append({"from": peer_id, "to": other.peer_id, "room": room, "text": text})
	other._inbox.append(["message", peer_id, text])


func poll() -> void:
	var batch := _inbox
	_inbox = []
	for item: Array in batch:
		match item[0]:
			"hosted":
				hosted.emit(item[2])
			"failed":
				failed.emit(item[2])
			"connected":
				peer_connected.emit(item[1])
			"disconnected":
				peer_disconnected.emit(item[1])
			"message":
				var msg: Variant = JSON.parse_string(item[2])
				if msg is Dictionary:
					message_received.emit(item[1], msg)


## Cuts the link to `peer` as if the network dropped. Both ends hear about it.
func disconnect_peer(peer: int) -> void:
	var other: LoopbackTransport = _ref(_links.get(peer))
	if other == null:
		return
	_links.erase(peer)
	other._links.erase(peer_id)
	_inbox.append(["disconnected", peer, null])
	other._inbox.append(["disconnected", peer_id, null])


func close() -> void:
	for peer: int in _links.keys():
		disconnect_peer(peer)
	if is_host and _ref(hub.rooms.get(room)) == self:
		hub.rooms.erase(room)


# Links are weak so linked transports don't keep each other alive.
static func _ref(link: Variant) -> LoopbackTransport:
	return (link as WeakRef).get_ref() if link is WeakRef else null
