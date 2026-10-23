class_name SquadLobby
extends RefCounted
## The squad-creation lobby at the start of a new campaign (the user's request), without UI.
## Four pilot slots side by side. An empty slot can be claimed ("Join": online each player
## claims one, solo you fill whichever you like); its player then makes a character (the full
## creator) or loads a saved one, and marks it Ready. The host can leave a slot empty or "Add
## bot" (an AI squadmate, made on the host, customizable or randomized; it follows its human as
## always). Every character that comes in (made, loaded, imported, a friend's, a bot) goes through
## the sanity check (CharacterSanity: rebuilt from the book for this campaign's starting LL, with
## a report of anything left out). Start unlocks when every claimed slot is Ready. A player can
## leave and the host can kick: the slot goes back to empty. The squad's shared history
## (SessionZero.squad_history) updates as pilots are made.
##
## Online it rides the lobby channel like the rest: a friend's message {"squad": {claim |
## leave | ready: bool | character: {...}}} acts on their own seat only (the seat comes from the
## connection); everyone gets the slots' public state (finished pilots, who's ready).

signal changed

const SEATS := ["p1", "p2", "p3", "p4"]

var db: ContentDB
var campaign: Campaign
## seat -> {state: "empty" | "claimed" | "bot", owner (player name), pilot: {}, ready, report: [], passed, leader}
var slots: Dictionary = {}
## The squad's history lines (story's), and the reroll used.
var history: Array = []
var history_variant := 0
## The host's NetHost (online), for seats and the lobby channel.
var host: NetHost


func _init(content: ContentDB, the_campaign: Campaign) -> void:
	db = content
	campaign = the_campaign
	for seat: String in SEATS:
		slots[seat] = _empty()


static func _empty() -> Dictionary:
	return {"state": "empty", "owner": "", "pilot": {}, "ready": false, "report": [], "passed": false, "leader": ""}


## "Join": `who` claims an empty slot. "" or why not.
func claim(seat: String, who: String) -> String:
	if not slots.has(seat):
		return "No such slot."
	if str(slots[seat]["state"]) != "empty":
		return "Someone's already in that slot."
	slots[seat] = _empty()
	slots[seat]["state"] = "claimed"
	slots[seat]["owner"] = who
	changed.emit()
	return ""


## Leaving, or the host kicking: the slot goes back to empty.
func release(seat: String) -> void:
	if slots.has(seat):
		slots[seat] = _empty()
		_history()
		changed.emit()


## The host's "Add bot": an AI squadmate made on the host (a random pilot, sanity-checked),
## following `leader` (a human seat).
func add_bot(seat: String, leader: String = "p1") -> String:
	if not slots.has(seat) or str(slots[seat]["state"]) != "empty":
		return "That slot isn't free."
	slots[seat]["state"] = "bot"
	slots[seat]["leader"] = leader
	randomize_bot(seat)
	return ""


## A new random pilot for a bot slot (the host's "Randomize").
func randomize_bot(seat: String) -> void:
	var rng := NameGen.new(_rng(seat))
	var p := campaign.new_pilot(rng.pilot_name(), rng.callsign())
	campaign.pilots.erase(p["id"])
	p["persona"] = Squadmate.suggest(p)
	set_character(seat, CharacterRoster.from_pilot(p))
	slots[seat]["ready"] = true  # bots are ready when they're made


func _rng(seat: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([campaign.id, seat, Time.get_ticks_usec()])
	return r


## A character for a slot: made in the creator, loaded from the roster, imported, a friend's,
## or a bot's. Always rebuilt and checked (CharacterSanity); the slot shows the report. Changing
## the character un-readies the slot. "" or why not.
func set_character(seat: String, character: Dictionary) -> String:
	if not slots.has(seat) or str(slots[seat]["state"]) == "empty":
		return "Claim the slot first."
	var r := CharacterSanity.rebuild(db, campaign, character)
	if (r["pilot"] as Dictionary).is_empty():
		return CharacterSanity.describe(r["report"])
	slots[seat]["pilot"] = r["pilot"]
	slots[seat]["report"] = r["report"]
	slots[seat]["passed"] = r["passed"]
	slots[seat]["ready"] = false
	_history()
	changed.emit()
	return ""


func set_ready(seat: String, on: bool) -> String:
	if not slots.has(seat) or (slots[seat]["pilot"] as Dictionary).is_empty():
		return "Make a character first."
	slots[seat]["ready"] = on
	changed.emit()
	return ""


## Start unlocks when at least one slot has a human and every claimed slot is Ready.
func can_start() -> String:
	var any := false
	for seat: String in SEATS:
		var s: Dictionary = slots[seat]
		if str(s["state"]) == "claimed":
			any = true
			if not bool(s["ready"]):
				return "Waiting for %s to be ready." % (str(s["owner"]) if str(s["owner"]) != "" else seat)
		if str(s["state"]) == "bot" and (s["pilot"] as Dictionary).is_empty():
			return "A bot slot has no pilot yet."
	return "" if any else "Someone has to join first."


## The finished squad for the campaign: [{seat, pilot, ai, leader}] in seat order.
func squad() -> Array:
	var out: Array = []
	for seat: String in SEATS:
		var s: Dictionary = slots[seat]
		if not (s["pilot"] as Dictionary).is_empty() and str(s["state"]) != "empty":
			out.append({"seat": seat, "pilot": s["pilot"], "ai": str(s["state"]) == "bot", "leader": s["leader"]})
	return out


## Story's "how these people know each other", from the pilots made so far.
func _history() -> void:
	var c := Campaign.create(campaign.name)
	var st := StoryState.new(1)
	for e: Dictionary in squad():
		c.pilots[e["pilot"]["id"]] = e["pilot"]
	history = SessionZero.squad_history(st, c, history_variant) if c.pilots.size() >= 2 else []


func reroll_history() -> void:
	history_variant += 1
	_history()
	changed.emit()


## What everyone sees (online): each slot's state, owner, the finished pilot's public face and
## build, ready, and whether it passed the sanity check.
func summary() -> Dictionary:
	var out := {}
	for seat: String in SEATS:
		var s: Dictionary = slots[seat]
		var p: Dictionary = s["pilot"]
		out[seat] = {"state": s["state"], "owner": s["owner"], "ready": s["ready"], "passed": s["passed"], "report": (s["report"] as Array).duplicate(true),
			"pilot": {} if p.is_empty() else {"name": p.get("name", ""), "callsign": p.get("callsign", ""), "portrait": p.get("portrait", {}),
				"persona": p.get("persona", ""), "background": p.get("background", ""), "mechs": (p.get("mechs", []) as Array).duplicate(true)}}
	return {"slots": out, "history": history.duplicate(true), "can_start": can_start()}


## A friend's message on the lobby channel, for their own seat only (host).
func on_message(seat: String, who: String, msg: Dictionary) -> void:
	var m: Variant = msg.get("squad")
	if not m is Dictionary or not slots.has(seat):
		return
	if bool((m as Dictionary).get("claim", false)):
		claim(seat, who)
	elif bool((m as Dictionary).get("leave", false)):
		release(seat)
	elif (m as Dictionary).has("ready"):
		set_ready(seat, bool(m["ready"]))
	elif (m as Dictionary).get("character") is Dictionary:
		if str(slots[seat]["state"]) == "claimed":
			set_character(seat, m["character"])
