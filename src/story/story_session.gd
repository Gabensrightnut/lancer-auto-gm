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


func _init(e: StoryEngine, s: StoryState, c: Campaign) -> void:
	engine = e
	story = s
	campaign = c


## Runs one action for `seat`. Remote seats may never act as "gm".
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
		broadcast.call(payload)


## Sends the current view to everyone (e.g. after a player joins).
func resync() -> void:
	_send([])


## A message from a remote seat: {"story_action": action, "id": n}. Refusals go back to
## everyone tagged with the seat and id (the lobby channel only broadcasts).
func handle_message(seat: String, msg: Dictionary) -> void:
	if not msg.get("story_action") is Dictionary:
		return
	var r := submit(seat, msg["story_action"], true)
	if not r["ok"] and broadcast.is_valid():
		broadcast.call({"story": {"refused": {"seat": seat, "id": msg.get("id", 0), "reason": r["reason"], "rule_ref": r.get("rule_ref", "")}}})


func attach_net_host(host: NetHost) -> void:
	host.lobby_message.connect(func(seat: String, msg: Dictionary) -> void: handle_message(seat, msg))
	broadcast = func(payload: Dictionary) -> void: host.send_lobby(payload)
	host.seats_changed.connect(func(_t: Dictionary) -> void: resync())
