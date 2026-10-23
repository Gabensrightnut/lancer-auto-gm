class_name StoryClient
extends StoryEngine
## A remote player's stand-in for StoryEngine: the story UI calls submit() exactly as on the
## host, but the action goes to the host and the answer comes back as a new view. Checks
## (validate) still run locally on the mirrored state so buttons can say why they're off.
## `story` and `campaign` are mirrors rebuilt from each StoryView; keep a reference to them
## through `mirror_changed`.

signal mirror_changed(story: StoryState, campaign: Campaign, events: Array)
signal refused(reason: String, rule_ref: String)

var seat := ""
var story: StoryState
var campaign: Campaign
## func(payload: Dictionary) that sends to the host. Set by attach_net_client().
var send: Callable
var _next_id := 1
## Tells this client's requests apart from an earlier run's (the host runs each one once).
var _nonce := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _init(content: ContentDB = null, my_seat: String = "") -> void:
	super(content)
	seat = my_seat


## Sends the action to the host; the result arrives as a view (mirror_changed).
func submit(_story: StoryState, _campaign: Campaign, action: Dictionary) -> Dictionary:
	var a := action.duplicate(true)
	a["seat"] = seat
	var why := validate(story if story != null else _story, campaign if campaign != null else _campaign, a)
	if not why.is_empty():
		return {"ok": false, "reason": why["reason"], "rule_ref": why.get("rule_ref", ""), "events": []}
	if send.is_valid():
		send.call({"story_action": a, "id": _next_id, "nonce": _nonce})
	_next_id += 1
	return {"ok": true, "reason": "", "rule_ref": "", "events": [], "pending": true}


## A payload from the host ({"story": {view, events} | {refused}}).
func receive(payload: Dictionary) -> void:
	var s: Variant = payload.get("story")
	if not s is Dictionary:
		return
	if s.has("refused"):
		if str(s["refused"].get("seat", "")) == seat:
			refused.emit(str(s["refused"].get("reason", "")), str(s["refused"].get("rule_ref", "")))
		return
	if s.get("view") is Dictionary:
		var m := StoryView.mirror(s["view"])
		story = m["story"]
		campaign = m["campaign"]
		mirror_changed.emit(story, campaign, s.get("events", []))


func attach_net_client(client: NetClient) -> void:
	client.lobby_updated.connect(func(lobby: Dictionary) -> void: receive(lobby))
	send = func(payload: Dictionary) -> void:
		var msg := payload.duplicate()
		msg["t"] = NetProtocol.LOBBY
		client.transport.send(NetTransport.HOST_PEER, msg)
