class_name NetTransport
extends RefCounted
## Moves messages between one host and its clients. Sessions (NetHost, NetClient) only talk
## to this interface, so the same session code runs over LoopbackTransport (tests, hot-seat)
## and WebRtcTransport (online).
##
## Peers are ints. The host is always HOST_PEER; clients get other numbers from the host's
## transport. Messages are JSON-safe Dictionaries; transports send them as JSON text.

const HOST_PEER := 1

## Host side: the room is open under `room_code` and clients can join.
signal hosted(room_code: String)
## Host side: a client connected. Client side: connected to the host (peer == HOST_PEER).
signal peer_connected(peer: int)
## Either side: the link to `peer` is gone (client side: HOST_PEER means the host is lost).
signal peer_disconnected(peer: int)
signal message_received(peer: int, msg: Dictionary)
## Couldn't host or join at all (room code not found, signaling server down...).
signal failed(reason: String)

var is_host := false


func host(_room_code: String) -> void:
	push_error("NetTransport.host not implemented")


func join(_room_code: String) -> void:
	push_error("NetTransport.join not implemented")


func send(_peer: int, _msg: Dictionary) -> void:
	pass


## Call every frame: delivers queued messages and connection changes as signals.
func poll() -> void:
	pass


func disconnect_peer(_peer: int) -> void:
	pass


func close() -> void:
	pass
