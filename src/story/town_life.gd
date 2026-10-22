class_name TownLife
extends RefCounted
## Life in a hub, for doing things yourself (DESIGN.md section 11): a clock (dawn, day,
## evening, night) and waiting; where each person is at each time of day and where they
## sleep; rooms with locks; things that belong to someone and are kept somewhere; and
## sneaking, following, lockpicking, pickpocketing, breaking in and knocking someone out,
## each a narrative skill check with the book's triggers (Core p.26-27). Nobody is offered
## "steal it" as a choice: the squad finds out where something is kept and when its owner
## sleeps, and goes and does it. Witnesses, alarms and consequences follow.
##
## StoryEngine actions (hub only, not in a mission or a conversation):
##   wait {periods}             go {pilot, spot, room}        follow {pilot, npc}
##   sneak {pilot, spot, room}  pick_lock {pilot, spot, room}  break_in {pilot, spot, room}
##   pickpocket {pilot, npc, item}  take_out {pilot, npc}  take {pilot, item}  slip_away {pilot}
## State in story.flags: _clock, _where, _items, _open, _out, _caught, _bounty.

const FILE := "res://data/game/story/town_life.json"
const ACTIONS := ["wait", "go", "follow", "sneak", "pick_lock", "break_in", "pickpocket", "take_out", "take", "slip_away"]
const CHECKS := ["follow", "sneak", "pick_lock", "break_in", "pickpocket", "take_out", "slip_away"]
const REF_GM := "Core p.45: the GM decides what happens on a failed check"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func handles(type: String) -> bool:
	return ACTIONS.has(type)


# --- Clock -------------------------------------------------------------------------------

static func clock(story: StoryState) -> Dictionary:
	if not story.flags.has("_clock"):
		story.flags["_clock"] = {"day": 1, "period": 1}
	return story.flags["_clock"]


static func period(story: StoryState) -> String:
	var ps: Array = data().get("periods", ["dawn", "day", "evening", "night"])
	return str(ps[int(clock(story)["period"]) % ps.size()])


static func period_name(story: StoryState) -> String:
	return str(data().get("period_names", {}).get(period(story), period(story)))


static func is_dark(story: StoryState) -> bool:
	return period(story) in ["night", "dawn"]


## Time passes: n periods. People wake up, doors left open get noticed and shut.
static func advance(story: StoryState, n: int = 1) -> Array:
	var c := clock(story)
	var ps := (data().get("periods", []) as Array).size()
	for i in range(n):
		c["period"] = int(c["period"]) + 1
		if int(c["period"]) >= ps:
			c["period"] = 0
			c["day"] = int(c["day"]) + 1
			# Tempers cool a little overnight (Tones).
			for id: String in story.npcs:
				if int(story.npcs[id].get("temper", 0)) > 0:
					story.npcs[id]["temper"] = int(story.npcs[id]["temper"]) - 1
	story.flags["_open"] = {}
	var out: Dictionary = story.flags.get("_out", {})
	for npc: String in out.keys():
		if _stamp(story) >= int(out[npc]):
			out.erase(npc)
	story.flags["_out"] = out
	story.flags.erase("_caught")
	var lines: Array = data().get("lines", {}).get("wait", ["Time passes."])
	var events: Array = [{"type": "time_passed", "day": int(c["day"]), "period": period(story),
		"text": str(lines[story.dice.die(lines.size()) - 1]).replace("{period}", period_name(story).to_lower())}]
	events.append_array(_discover_thefts(story))
	return events


static func _stamp(story: StoryState) -> int:
	return int(clock(story)["day"]) * 10 + int(clock(story)["period"])


# --- Places and people -------------------------------------------------------------------

static func spots(story: StoryState) -> Array:
	return (story.hub.get("spots", []) as Array).map(func(s: Dictionary) -> String: return str(s["id"]))


## A schedule place that exists in this hub (homes and missing buildings fall back to the
## rooms above the bar, then the square).
static func _fit(story: StoryState, spot: String, room: String) -> Array:
	var have := spots(story)
	if have.has(spot):
		return [spot, room]
	if spot == "house" and have.has("bar"):
		return ["bar", "upstairs"]
	return ["plaza", "square"] if have.has("plaza") else [str(have[0]) if not have.is_empty() else "plaza", "square"]


## Where someone is right now: {spot, room, asleep, out}.
static func where_npc(story: StoryState, npc_id: String, at_period: String = "") -> Dictionary:
	var npc: Dictionary = story.npcs.get(npc_id, {})
	var sch: Dictionary = data().get("schedules", {})
	var mine: Dictionary = npc.get("schedule", sch.get(str(npc.get("role", "")), sch.get("default", {})))
	var p := at_period if at_period != "" else period(story)
	var entry: Array = mine.get(p, ["plaza", "square"])
	var fit := _fit(story, str(entry[0]), str(entry[1]))
	return {"spot": fit[0], "room": fit[1], "asleep": entry.size() > 2 and str(entry[2]) == "asleep",
		"out": (story.flags.get("_out", {}) as Dictionary).has(npc_id), "dead": bool(npc.get("dead", false))}


static func room_info(spot_kind: String, room: String) -> Dictionary:
	return data().get("rooms", {}).get(spot_kind, {}).get(room, {"name": room, "public": false, "lock": 1})


static func spot_kind(story: StoryState, spot: String) -> String:
	for s: Dictionary in story.hub.get("spots", []):
		if str(s["id"]) == spot:
			return str(s.get("kind", spot))
	return spot


## People in a room: [npc ids], awake or not.
static func present(story: StoryState, spot: String, room: String, awake_only: bool = true) -> Array:
	var out: Array = []
	for id: String in story.hub.get("npcs", []):
		var w := where_npc(story, id)
		if bool(w["dead"]) or str(w["spot"]) != spot or str(w["room"]) != room:
			continue
		if awake_only and (bool(w["asleep"]) or bool(w["out"])):
			continue
		out.append(id)
	return out


static func pilot_at(story: StoryState, pid: String) -> Dictionary:
	return story.flags.get("_where", {}).get(pid, {"spot": "plaza", "room": "square"})


static func _set_pilot(story: StoryState, pid: String, spot: String, room: String) -> void:
	var w: Dictionary = story.flags.get("_where", {})
	w[pid] = {"spot": spot, "room": room}
	story.flags["_where"] = w


static func is_open(story: StoryState, spot: String, room: String) -> bool:
	return (story.flags.get("_open", {}) as Dictionary).has("%s:%s" % [spot, room])


static func _open(story: StoryState, spot: String, room: String) -> void:
	var o: Dictionary = story.flags.get("_open", {})
	o["%s:%s" % [spot, room]] = true
	story.flags["_open"] = o


## Whose room this is (for consequences): whoever sleeps or works there.
static func owner_of(story: StoryState, spot: String, room: String) -> String:
	for id: String in story.hub.get("npcs", []):
		for p: String in data().get("periods", []):
			var w := where_npc(story, id, p)
			if str(w["spot"]) == spot and str(w["room"]) == room and not room_info(spot_kind(story, spot), room).get("public", false):
				return id
	return ""


# --- Things ------------------------------------------------------------------------------

## Something that belongs to someone and is kept somewhere: on them ("person") or in a room
## or container (spot + room). lock: 0 none, 1 locked, 2 a safe. effects: what having it does
## (StoryEffects vocabulary), e.g. {"set_flag": ...}.
static func add_item(story: StoryState, spec: Dictionary) -> String:
	var items: Dictionary = story.flags.get("_items", {})
	var id := str(spec.get("id", "item_%d" % items.size()))
	var it := {"id": id, "name": str(spec.get("name", "something")), "owner": str(spec.get("owner", "")), "kept": str(spec.get("kept", "room")),
		"spot": str(spec.get("spot", "")), "room": str(spec.get("room", "")), "lock": int(spec.get("lock", 0)), "value": int(spec.get("value", 10)),
		"effects": (spec.get("effects", []) as Array).duplicate(true), "holder": "", "stolen": false, "missed": false, "hub": str(story.hub.get("id", ""))}
	items[id] = it
	story.flags["_items"] = items
	return id


static func item(story: StoryState, id: String) -> Dictionary:
	return story.flags.get("_items", {}).get(id, {})


static func items_here(story: StoryState, spot: String, room: String) -> Array:
	return (story.flags.get("_items", {}) as Dictionary).values().filter(func(it: Dictionary) -> bool:
		return str(it["holder"]) == "" and str(it["kept"]) != "person" and str(it["spot"]) == spot and str(it["room"]) == room and str(it["hub"]) == str(story.hub.get("id", "")))


## A few things worth knowing about in every hub (our own): the company rep's papers in the
## office safe, the bartender's strongbox in the back room, the fixer's ledger on them.
static func seed_items(story: StoryState) -> void:
	if (story.flags.get("_items_seeded", []) as Array).has(str(story.hub.get("id", ""))):
		return
	for id: String in story.hub.get("npcs", []):
		var npc: Dictionary = story.npcs[id]
		match str(npc.get("role", "")):
			"company_rep":
				add_item(story, {"id": "%s_papers" % id, "name": "%s's contract papers" % npc["name"], "owner": id, "kept": "room", "spot": "office", "room": "safe", "lock": 2, "value": 40,
					"effects": [{"set_flag": "secret_known:%s" % id}, {"set_flag": "read_papers:%s" % id}]})
			"bartender":
				add_item(story, {"id": "%s_box" % id, "name": "%s's strongbox" % npc["name"], "owner": id, "kept": "room", "spot": "bar", "room": "back", "lock": 1, "value": 30, "effects": [{"set_flag": "took_box:%s" % id}]})
			"fixer":
				add_item(story, {"id": "%s_ledger" % id, "name": "%s's ledger" % npc["name"], "owner": id, "kept": "person", "value": 25,
					"effects": [{"set_flag": "secret_known:%s" % id}]})
	var seeded: Array = (story.flags.get("_items_seeded", []) as Array).duplicate()
	seeded.append(str(story.hub.get("id", "")))
	story.flags["_items_seeded"] = seeded


# --- Doing things ------------------------------------------------------------------------

## Why this can't be done now ("" if it can).
static func refusal(story: StoryState, campaign: Campaign, type: String, p: Dictionary, pid: String) -> String:
	if story.phase == "mission":
		return "Not in the middle of a mission."
	if Dialogue.is_open(story):
		return "Finish the conversation first."
	if story.hub.is_empty():
		return "The squad isn't in town."
	if type != "wait" and (pid == "" or not story.is_alive(pid)):
		return "Which pilot?"
	match type:
		"wait":
			if int(p.get("periods", 1)) < 1 or int(p.get("periods", 1)) > 4:
				return "Wait one to four parts of the day."
		"go", "sneak", "pick_lock", "break_in":
			var spot := str(p.get("spot", ""))
			var room := str(p.get("room", ""))
			if not spots(story).has(spot) or (room_info(spot_kind(story, spot), room).is_empty()):
				return "There's no such place here."
			var info := room_info(spot_kind(story, spot), room)
			if type == "go" and not bool(info.get("public", false)) and not is_open(story, spot, room) and int(info.get("lock", 1)) > 0:
				return "It's locked."
			if type == "go" and not bool(info.get("public", false)) and not present(story, spot, room).is_empty() and not is_open(story, spot, room):
				return "%s won't let you in." % story.npcs[present(story, spot, room)[0]]["name"]
			if type in ["pick_lock", "break_in"] and (int(info.get("lock", 0)) == 0 or is_open(story, spot, room)):
				return "It isn't locked."
		"follow", "take_out", "pickpocket":
			var npc := str(p.get("npc", ""))
			if not (story.hub.get("npcs", []) as Array).has(npc):
				return "Nobody like that here."
			var w := where_npc(story, npc)
			if bool(w["dead"]):
				return "They're dead."
			if bool(w["out"]) and type != "pickpocket":
				return "They're already out cold."
			var me := pilot_at(story, pid)
			if type != "follow" and (str(me["spot"]) != str(w["spot"]) or str(me["room"]) != str(w["room"])):
				return "You'd have to be where they are."
			if type == "pickpocket":
				var it := item(story, str(p.get("item", "")))
				if it.is_empty() or str(it["kept"]) != "person" or str(it["owner"]) != npc or str(it["holder"]) != "":
					return "They don't have that on them."
		"take":
			var it := item(story, str(p.get("item", "")))
			if it.is_empty() or str(it["holder"]) != "" or str(it["kept"]) == "person":
				return "There's nothing like that to take here."
			var me := pilot_at(story, pid)
			if str(me["spot"]) != str(it["spot"]) or (str(me["room"]) != str(it["room"]) and str(it["room"]) != "safe"):
				return "It isn't here."
			if int(it["lock"]) > 0 and not is_open(story, str(it["spot"]), str(it["room"])):
				return "It's locked away."
			var watching := present(story, str(it["spot"]), str(me["room"])).filter(func(n: String) -> bool: return n == str(it["owner"]))
			if not watching.is_empty():
				return "%s is right there." % story.npcs[watching[0]]["name"]
		"slip_away":
			if str(story.flags.get("_caught", "")) != pid:
				return "Nobody's after you."
	return ""


static func apply(story: StoryState, campaign: Campaign, type: String, p: Dictionary, pid: String) -> Array:
	match type:
		"wait":
			return advance(story, int(p.get("periods", 1)))
		"go":
			_set_pilot(story, pid, str(p["spot"]), str(p["room"]))
			return [{"type": "moved", "pilot": pid, "spot": p["spot"], "room": p["room"], "text": "%s goes to %s." % [_cs(campaign, pid), _place(story, str(p["spot"]), str(p["room"]))]}]
		"sneak":
			var spot := str(p["spot"])
			var room := str(p["room"])
			var info := room_info(spot_kind(story, spot), room)
			var locked := int(info.get("lock", 0)) > 0 and not is_open(story, spot, room)
			if locked:
				return [{"type": "blocked", "text": "The door is locked. You'd need to pick it or force it."}]
			var r := _check(story, campaign, pid, "sneak", {"difficult": not is_dark(story) and not present(story, spot, room).is_empty()})
			var events: Array = r["events"]
			if r["success"]:
				_set_pilot(story, pid, spot, room)
				events.append({"type": "moved", "pilot": pid, "spot": spot, "room": room, "sneaking": true, "text": "%s slips into %s unseen." % [_cs(campaign, pid), _place(story, spot, room)]})
			else:
				events.append_array(_seen(story, campaign, pid, spot, room, false, owner_of(story, spot, room), 0))
			return events
		"follow":
			var npc := str(p["npc"])
			var r := _check(story, campaign, pid, "follow", {"difficult": not is_dark(story)})
			var events: Array = r["events"]
			var ps: Array = data().get("periods", [])
			var nxt := str(ps[(int(clock(story)["period"]) + 1) % ps.size()])
			if r["success"]:
				var w := where_npc(story, npc, nxt)
				var sleep := ""
				for q: String in ps:
					var ws := where_npc(story, npc, q)
					if bool(ws["asleep"]):
						sleep = _place(story, str(ws["spot"]), str(ws["room"]))
				story.flags["knows_schedule:%s" % npc] = true
				var slept := (", and they sleep in %s" % sleep) if sleep != "" else ""
				events.append({"type": "learned", "npc": npc, "text": "%s tails %s unnoticed: next they go to %s%s." % [_cs(campaign, pid), story.npcs[npc]["name"], _place(story, str(w["spot"]), str(w["room"])), slept]})
				events.append_array(advance(story, 1))
				_set_pilot(story, pid, str(w["spot"]), "main" if str(w["spot"]) == "bar" else str(_public_room(story, str(w["spot"]))))
			else:
				_temper(story, npc, 2)
				events.append({"type": "noticed", "npc": npc, "text": "%s notices the tail and doesn't like it." % story.npcs[npc]["name"]})
			return events
		"pick_lock", "break_in":
			var spot := str(p["spot"])
			var room := str(p["room"])
			var info := room_info(spot_kind(story, spot), room)
			var safe := int(info.get("lock", 1)) >= 2
			var r := _check(story, campaign, pid, type, {"difficult": safe})
			var events: Array = r["events"]
			var loud := type == "break_in"
			if r["success"] or loud:
				_open(story, spot, room)
				events.append({"type": "opened", "spot": spot, "room": room, "text": "%s %s %s." % [_cs(campaign, pid), "forces open" if loud else "picks the lock on", _place(story, spot, room)]})
			if loud or not r["success"]:
				events.append_array(_seen(story, campaign, pid, spot, room, loud, owner_of(story, spot, room), 0))
			return events
		"pickpocket":
			var npc := str(p["npc"])
			var it := item(story, str(p["item"]))
			var w := where_npc(story, npc)
			if bool(w["out"]):
				return _taken(story, campaign, pid, it)
			var r := _check(story, campaign, pid, "pickpocket", {"risky": not bool(w["asleep"])})
			var events: Array = r["events"]
			if r["success"]:
				events.append_array(_taken(story, campaign, pid, it))
			else:
				_temper(story, npc, 4)
				var caught: Array = [{"type": "seen", "pilot": pid, "witnesses": [npc], "text": "%s catches your hand." % story.npcs[npc]["name"], "rule_ref": REF_GM}]
				events.append_array(caught)
				events.append_array(_seen(story, campaign, pid, str(w["spot"]), str(w["room"]), false, npc, int(it["value"]), npc))
			return events
		"take_out":
			var npc := str(p["npc"])
			var w := where_npc(story, npc)
			var r := _check(story, campaign, pid, "take_out", {"difficult": not bool(w["asleep"])})
			var events: Array = r["events"]
			if r["success"]:
				var out: Dictionary = story.flags.get("_out", {})
				out[npc] = _stamp(story) + 2
				story.flags["_out"] = out
				events.append({"type": "knocked_out", "npc": npc, "text": "%s goes down without a sound." % story.npcs[npc]["name"]})
				events.append_array(_seen(story, campaign, pid, str(w["spot"]), str(w["room"]), false, npc, 0, npc))
			else:
				_temper(story, npc, 3)
				events.append_array(_seen(story, campaign, pid, str(w["spot"]), str(w["room"]), true, npc, 0))
			return events
		"take":
			var it := item(story, str(p["item"]))
			var events := _taken(story, campaign, pid, it)
			var me := pilot_at(story, pid)
			events.append_array(_seen(story, campaign, pid, str(me["spot"]), str(me["room"]), false, str(it["owner"]), int(it["value"]), str(it["owner"])))
			return events
		"slip_away":
			var r := _check(story, campaign, pid, "slip_away", {})
			var events: Array = r["events"]
			story.flags.erase("_caught")
			if r["success"]:
				_set_pilot(story, pid, "plaza", "square")
				events.append({"type": "escaped", "pilot": pid, "text": "%s is gone before anyone can stop them. Nobody's sure who it was." % _cs(campaign, pid)})
			else:
				events.append_array(_caught_fight(story, campaign, pid))
			return events
	return []


static func _public_room(story: StoryState, spot: String) -> String:
	var rooms: Dictionary = data().get("rooms", {}).get(spot_kind(story, spot), {})
	for r: String in rooms:
		if bool(rooms[r].get("public", false)):
			return r
	return rooms.keys()[0] if not rooms.is_empty() else "square"


static func _place(story: StoryState, spot: String, room: String) -> String:
	var sname := spot
	for s: Dictionary in story.hub.get("spots", []):
		if str(s["id"]) == spot:
			sname = str(s.get("name", spot))
	return "%s at %s" % [room_info(spot_kind(story, spot), room).get("name", room), sname]


static func _cs(campaign: Campaign, pid: String) -> String:
	return str(campaign.pilots.get(pid, {}).get("callsign", "A pilot"))


static func _check(story: StoryState, campaign: Campaign, pid: String, kind: String, extra: Dictionary) -> Dictionary:
	var cfg: Dictionary = data().get("actions", {}).get(kind, {})
	var opts := {"skills": cfg.get("skills", []), "label": str(cfg.get("label", kind)), "consequence": str(cfg.get("consequence", "")),
		"risky": bool(cfg.get("risky", false)) or bool(extra.get("risky", false)), "difficult": bool(extra.get("difficult", false)), "tags": ["stealth", "town"]}
	var rec := NarrativeCheck.roll(story.dice, campaign.pilots[pid], Economy.check_opts(story, campaign, pid, opts))
	rec["rule_ref"] = str(cfg.get("ref", ""))
	var ok := str(rec.get("outcome", "fail")) != "fail"
	return {"success": ok, "events": [{"type": "narrative_check", "pilot": pid, "check": rec, "rule_ref": rec["rule_ref"]}]}


static func _taken(story: StoryState, campaign: Campaign, pid: String, it: Dictionary) -> Array:
	it["holder"] = pid
	it["stolen"] = true
	var events: Array = [{"type": "item_taken", "pilot": pid, "item": it["id"], "text": "%s has %s." % [_cs(campaign, pid), it["name"]]}]
	events.append_array(StoryEffects.apply_all(it.get("effects", []), story, campaign, {"speaker": pid, "npc": str(it["owner"])}))
	return events


## Who saw it, and what follows: a named thief loses standing, picks up a bounty and makes an
## enemy; with a guard about, the alarm goes up and the squad can try to slip away (or fight).
static func _seen(story: StoryState, campaign: Campaign, pid: String, spot: String, room: String, loud: bool, owner: String, value: int, exclude: String = "") -> Array:
	var who: Array = present(story, spot, room).filter(func(n: String) -> bool: return n != exclude)
	if loud:
		for r: String in data().get("rooms", {}).get(spot_kind(story, spot), {}):
			for n: String in present(story, spot, r):
				if not who.has(n) and n != exclude:
					who.append(n)
	var crowd := int(data().get("crowd", {}).get(period(story), 1))
	var outside := bool(room_info(spot_kind(story, spot), room).get("public", false)) or loud
	var stranger := outside and story.dice.die(6) <= crowd
	if who.is_empty() and not stranger:
		return []
	var lines: Array = data().get("lines", {}).get("seen", ["{witness} sees it."])
	var witness := str(story.npcs[who[0]]["name"]) if not who.is_empty() else "Someone in the street"
	var events: Array = [{"type": "seen", "pilot": pid, "witnesses": who, "text": str(lines[story.dice.die(lines.size()) - 1]).replace("{witness}", witness), "rule_ref": REF_GM}]
	var fac := str(story.npcs.get(owner, {}).get("faction", story.hub.get("faction", "")))
	if fac != "":
		events.append_array(StoryEffects.apply({"standing": fac, "add": -1}, story, campaign, {}))
	if owner != "":
		_temper(story, owner, 5)
	story.flags["_bounty"] = int(story.flags.get("_bounty", 0)) + value * int(data().get("witness", {}).get("bounty_per_value", 1))
	var guards: Array = data().get("witness", {}).get("guards", [])
	var guard_seen := who.any(func(n: String) -> bool: return guards.has(str(story.npcs[n].get("role", ""))))
	if guard_seen or loud:
		var al: Array = data().get("lines", {}).get("alarm", ["The alarm goes up."])
		story.flags["_caught"] = pid
		events.append({"type": "alarm", "pilot": pid, "text": str(al[story.dice.die(al.size()) - 1]), "can_slip": true})
	return events


static func _caught_fight(story: StoryState, campaign: Campaign, pid: String) -> Array:
	return [{"type": "combat_requested", "spec": {"hook": "standoff", "on_foot": true, "in_town": true, "reason": "%s was caught. Now it's a fight." % _cs(campaign, pid)},
		"rule_ref": "Core p.45: switching to mech combat"}]


## An NPC's temper (0 calm .. 10 boiling), for conversations (DESIGN section 11).
static func _temper(story: StoryState, npc: String, add: int) -> void:
	if story.npcs.has(npc):
		story.npcs[npc]["temper"] = clampi(int(story.npcs[npc].get("temper", 0)) + add, 0, 10)


## Things missed: when the owner next comes back to where it was kept.
static func _discover_thefts(story: StoryState) -> Array:
	var events: Array = []
	for it: Dictionary in (story.flags.get("_items", {}) as Dictionary).values():
		if bool(it["stolen"]) and not bool(it["missed"]) and str(it["owner"]) != "" and str(it["hub"]) == str(story.hub.get("id", "")):
			var w := where_npc(story, str(it["owner"]))
			if not bool(w["asleep"]) and not bool(w["out"]):
				it["missed"] = true
				_temper(story, str(it["owner"]), 3)
				events.append({"type": "item_missed", "npc": it["owner"], "item": it["id"], "text": "%s has noticed %s is gone." % [story.npcs[str(it["owner"])]["name"], it["name"]]})
	return events
