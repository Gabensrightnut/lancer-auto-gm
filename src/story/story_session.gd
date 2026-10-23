class_name StorySession
extends RefCounted
## The story between battles in multiplayer. The host owns the real StoryState and runs
## every action through StoryEngine; clients get StoryView views and events, never secrets.
## Each player acts for their own seat only: the seat comes from the connection, never from
## the message, so nobody can choose for someone else's pilot or act as the GM.
##
## Over the network it rides the session's lobby channel (NetHost.lobby_message /
## NetHost.send_lobby and NetClient.lobby_updated; payload keys "story_action" and "story"),
## so it works wherever players are connected, in or between missions. Hot-seat and solo
## just call submit() for the local seats.

signal updated(view: Dictionary, events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
## Seats played on this machine (they may act as "gm" for host-only actions).
var local_seats: Array = []
## func(payload: Dictionary) that sends to every client. Set by attach_net_host().
var broadcast: Callable
## func(payload: Dictionary) that sends to every client but a human GM's seat, and func(seat,
## payload) -> bool that sends to one seat. Set by attach_net_host(): a human GM online gets
## the GM's view (secrets and twists, StoryView "gm"), everyone else the players' view.
var broadcast_players: Callable
var send_to: Callable
## func() -> [seats] of friends connected right now (each gets its own view: their wallet,
## inventory, bounty and trades are theirs alone). Set by attach_net_host().
var connected_seats: Callable
## Story actions already run, by "seat:nonce:id": a friend's request repeated after a dropped
## connection doesn't run twice (no duplicated trades or gifts).
var _done: Dictionary = {}
var _done_order: Array = []


func _init(e: StoryEngine, s: StoryState, c: Campaign) -> void:
	engine = e
	story = s
	campaign = c


## Runs one action for `seat`. A remote seat acts only as itself: "gm" only for the friend
## sitting in the GM seat, which the host opens only for a human GM (NetHost.human_gm).
func submit(seat: String, action: Dictionary, remote: bool = false) -> Dictionary:
	var a := action.duplicate(true)
	# Remote players act only as their own seat; seats on the host machine may act as the GM.
	a["seat"] = seat if remote else str(a.get("seat", seat))
	var r := engine.submit(story, campaign, a)
	if r["ok"]:
		_send(r["events"])
	return r


func view_for(seat: String = "") -> Dictionary:
	return StoryView.view_for(story, campaign, seat)


func _send(events: Array, extra: Dictionary = {}) -> void:
	var view := view_for()
	var evs := StoryView.events_for(events)
	updated.emit(view, evs)
	if broadcast.is_valid():
		var payload := {"story": {"view": view, "events": evs}}
		payload["story"].merge(extra, true)
		if connected_seats.is_valid() and send_to.is_valid():
			for seat: String in connected_seats.call():
				var own := {"story": {"view": view_for(seat), "events": StoryView.events_for(events, seat, story)}}
				own["story"].merge(extra, true)
				send_to.call(seat, own)
		elif broadcast_players.is_valid() and send_to.is_valid():
			broadcast_players.call(payload)
			var gm := {"story": {"view": view_for("gm"), "events": StoryView.events_for(events, "gm")}}
			gm["story"].merge(extra, true)
			send_to.call("gm", gm)
		else:
			broadcast.call(payload)


## Sends the current view to everyone (e.g. after a player joins).
func resync() -> void:
	_send([])


## A message from a remote seat: {"story_action": action, "id": n}. Refusals go back to
## everyone tagged with the seat and id (the lobby channel only broadcasts).
func handle_message(seat: String, msg: Dictionary) -> void:
	if not msg.get("story_action") is Dictionary:
		return
	var key := "%s:%s:%s" % [seat, msg.get("nonce", ""), msg.get("id", 0)]
	if msg.has("nonce") and _done.has(key):
		return  # already run (a repeat after a reconnect)
	_done[key] = true
	_done_order.append(key)
	if _done_order.size() > 500:
		_done.erase(_done_order.pop_front())
	var r := submit(seat, msg["story_action"], true)
	if not r["ok"] and broadcast.is_valid():
		broadcast.call({"story": {"refused": {"seat": seat, "id": msg.get("id", 0), "reason": r["reason"], "rule_ref": r.get("rule_ref", "")}}})


func attach_net_host(host: NetHost) -> void:
	host.lobby_message.connect(func(seat: String, msg: Dictionary) -> void: handle_message(seat, msg))
	broadcast = func(payload: Dictionary) -> void: host.send_lobby(payload)
	broadcast_players = func(payload: Dictionary) -> void: host.send_lobby(payload, [NetHost.GM_SEAT])
	send_to = func(seat: String, payload: Dictionary) -> bool: return host.send_lobby_to(seat, payload)
	connected_seats = func() -> Array:
		var out: Array = []
		var table := host.seat_table()
		for seat: String in table:
			if str(table[seat].get("where", "")) == "remote" and bool(table[seat].get("connected", false)):
				out.append(seat)
		return out
	host.seats_changed.connect(func(_t: Dictionary) -> void: resync())
