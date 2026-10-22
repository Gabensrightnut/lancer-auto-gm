class_name Cloning
extends RefCounted
## Death and cloning (Core p.83-84; data/game/story/cloning.json). A pilot's genetic template
## is kept somewhere: a city with sanctioned facilities (facsimile, lawful, slow) or a ship
## with a flash vat (fast, unlawful). If the pilot dies, the squad has to go there to wake the
## clone, between missions (cloned characters can't join a mission in progress). The clone
## keeps all License Levels (by the book; the house rule hr_clone_ll_penalty takes one away),
## remembers nothing from the start of the mission they died on, comes back with a quirk
## (always for flash, and with every cloning after the first), and a slightly different
## backstory (their upbringing shifts; genetic origin perks stay). The next clone starts
## growing as soon as one wakes. Templates can be corrupted, tampered with or destroyed.
## A player may instead make a new character: that's up to them.
##
## Each player may also keep one extra pilot, a close relation (friend, family, partner, or a
## clone), unless their pilot has already died once; they choose which pilot flies.
##
## StoryEngine actions: store_template {pilot, kind}, wake_clone {pilot},
## add_second_pilot {seat, name, callsign, relation}, set_active_pilot {seat, pilot}.
## Effect {"clone_template": {"pilot", "state": "corrupted" | "tampered" | "destroyed"}}.

const FILE := "res://data/game/story/cloning.json"
const KEY := "_templates"
const REF := "Core p.83-84: cloning"
const RELATIONS := ["friend", "family", "partner", "clone"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func template(story: StoryState, pid: String) -> Dictionary:
	return story.flags.get(KEY, {}).get(pid, {})


static func _here(story: StoryState) -> String:
	var at := str(Sector.get_sector(story).get("at", ""))
	return at if at != "" else str(story.hub.get("id", ""))


## Which kind of cloning this place can do: facsimile with a sanctioned patron or in the Union
## Core; flash where the law looks away (or aboard a ship with a flash vat).
static func available(story: StoryState, campaign: Campaign) -> Array:
	var out: Array = []
	var w := Sector.current(story)
	var culture := str(w.get("culture", story.hub.get("culture", "")))
	if culture == "union_core" or (data().get("sanctioned_patrons", []) as Array).has(str(campaign.options.get("patron", ""))) or bool(story.hub.get("clone_vats", false)):
		out.append("facsimile")
	if (data().get("flash_cultures", []) as Array).has(culture) or bool(story.hub.get("flash_vat", false)):
		out.append("flash")
	return out


static func store_refusal(story: StoryState, campaign: Campaign, pid: String, kind: String) -> String:
	if not campaign.pilots.has(pid) or not story.is_alive(pid):
		return "Which pilot?"
	if not available(story, campaign).has(kind):
		return "Nobody here can keep a %s template. Facsimile needs a sanctioned patron or the Union Core; flash cloning is unlawful, so it's only done where nobody asks (Core p.83)." % kind
	return ""


static func store(story: StoryState, campaign: Campaign, pid: String, kind: String) -> Array:
	var all: Dictionary = (story.flags.get(KEY, {}) as Dictionary).duplicate(true)
	all[pid] = {"at": _here(story), "where": str(story.hub.get("name", "")), "kind": kind, "ready_in": int(data().get("growth", {}).get(kind, 8)), "state": "ok"}
	story.flags[KEY] = all
	var text := "%s's genetic template is stored at %s (%s). A usable clone will take %s to grow." % [campaign.pilots[pid].get("callsign", ""), story.hub.get("name", ""), kind,
		"years" if kind == "facsimile" else "a few months"]
	var events: Array = [{"type": "template_stored", "pilot": pid, "kind": kind, "text": text, "rule_ref": REF}]
	if kind == "flash":
		story.flags["_bounty"] = int(story.flags.get("_bounty", 0)) + 50
		events.append({"type": "unlawful", "text": "Flash cloning is broadly unlawful (Core p.83). If anyone finds out, there'll be questions."})
	return events


## Time passes: templates grow, one mission at a time.
static func tick(story: StoryState) -> void:
	var all: Dictionary = story.flags.get(KEY, {})
	for pid: String in all:
		all[pid]["ready_in"] = maxi(0, int(all[pid].get("ready_in", 0)) - 1)


static func on_death(story: StoryState, campaign: Campaign, pid: String) -> Array:
	var t := template(story, pid)
	if t.is_empty() or str(t["state"]) == "destroyed":
		return []
	var ready := int(t["ready_in"]) <= 0
	return [{"type": "clone_possible", "pilot": pid, "at": t["at"], "ready": ready,
		"text": ("%s's clone can be woken at %s. Someone has to go there." % [campaign.pilots[pid].get("callsign", ""), t["where"]]) if ready
			else "%s has a template at %s, but the clone won't be ready for a long time yet." % [campaign.pilots[pid].get("callsign", ""), t["where"]], "rule_ref": REF}]


static func wake_refusal(story: StoryState, campaign: Campaign, pid: String) -> String:
	if not story.dead.has(pid):
		return "That pilot isn't dead."
	var t := template(story, pid)
	if t.is_empty() or str(t["state"]) == "destroyed":
		return "There's no template to wake a clone from."
	if int(t["ready_in"]) > 0:
		return "The clone isn't grown yet."
	if str(t["at"]) != _here(story):
		return "The clone is at %s. You'll have to go there." % t["where"]
	if story.phase == "mission":
		return "A cloned pilot can't join a mission in progress (Core p.83)."
	return ""


static func wake(story: StoryState, campaign: Campaign, pid: String) -> Array:
	var p: Dictionary = campaign.pilots[pid]
	var t := template(story, pid)
	var died_on := int(story.dead[pid].get("mission", story.mission_number))
	story.dead.erase(pid)
	story.flags.erase("dead_" + pid)
	story.pilot_hp[pid] = StoryEffects.max_hp(p)
	p["clones"] = int(p.get("clones", 0)) + 1
	p["deaths"] = int(p.get("deaths", 0)) + 1
	var events: Array = []
	# Quirks: always for flash clones, and with every cloning after the first (Core p.83);
	# a corrupted or tampered template adds one more.
	var quirks: Array = (p.get("quirks", []) as Array).duplicate()
	var n := (1 if str(t["kind"]) == "flash" or int(p["clones"]) > 1 else 0) + (1 if str(t["state"]) in ["corrupted", "tampered"] else 0)
	var list: Array = data().get("quirks", [])
	for i in range(n):
		var q := str(list[story.dice.die(list.size()) - 1])
		quirks.append(q)
		events.append({"type": "clone_quirk", "pilot": pid, "text": q})
	p["quirks"] = quirks
	# The memory gap: nothing since the start of the mission they died on.
	var m := Squadmate.memory(story, pid)
	m["recent"] = {}
	m["gap_from_mission"] = died_on
	# A slightly different backstory: the upbringing shifts; genetic perks stay.
	var o: Dictionary = p.get("origin", {})
	if not o.is_empty():
		var ups: Array = Origin.data().get("upbringing", [])
		var cur := str(o.get("upbringing", ""))
		var others: Array = ups.filter(func(u: Dictionary) -> bool: return str(u["id"]) != cur)
		if not others.is_empty():
			o["upbringing"] = str(others[story.dice.die(others.size()) - 1]["id"])
			events.append({"type": "clone_backstory", "pilot": pid, "text": "%s remembers growing up a little differently than they used to." % p.get("callsign", "")})
	if StoryHouseRules.on(campaign, "hr_clone_ll_penalty") and int(p.get("ll", 0)) > 0:
		p["ll"] = int(p["ll"]) - 1
		events.append({"type": "clone_ll", "pilot": pid, "text": "The clone has lost some of the edge: one License Level down (house rule: Your idea, not a book rule)."})
	var lines: Array = data().get("woke", ["{name} is back."])
	events.push_front({"type": "clone_woke", "pilot": pid, "text": str(lines[story.dice.die(lines.size()) - 1]).replace("{name}", str(p.get("callsign", ""))),
		"note": "They keep all License Levels and remember nothing after the start of the mission they died on (Core p.83).", "rule_ref": REF, "gather": true})
	# The next one starts growing.
	t["ready_in"] = int(data().get("growth", {}).get(str(t["kind"]), 8))
	t["state"] = "ok"
	return events


static func damage(story: StoryState, pid: String, state: String) -> Array:
	var all: Dictionary = story.flags.get(KEY, {})
	if not all.has(pid):
		return []
	all[pid]["state"] = state
	return [{"type": "template_" + state, "pilot": pid, "text": "%s's genetic template has been %s." % [pid, state]}]


# --- A second pilot ----------------------------------------------------------------------

static func second_refusal(story: StoryState, campaign: Campaign, seat: String, p: Dictionary) -> String:
	if not story.seats.has(seat):
		return "Which player?"
	var main := story.pilot_of_seat(seat)
	if int(campaign.pilots.get(main, {}).get("deaths", 0)) > 0 or story.dead.has(main):
		return "A pilot who has already died once can't bring in a second."
	if str(story.seats[seat].get("second", "")) != "":
		return "Each player keeps one extra pilot at most."
	if not RELATIONS.has(str(p.get("relation", ""))):
		return "A close relation: friend, family, partner or clone."
	if str(p.get("name", "")).strip_edges() == "":
		return "Name them."
	return ""


static func add_second(story: StoryState, campaign: Campaign, seat: String, p: Dictionary) -> Array:
	var main := story.pilot_of_seat(seat)
	var np := campaign.new_pilot(str(p["name"]), str(p.get("callsign", p["name"])))
	np["relation"] = {"to": main, "kind": str(p["relation"])}
	np["ll"] = int(campaign.pilots[main].get("ll", 0))
	story.seats[seat]["second"] = np["id"]
	return [{"type": "second_pilot", "seat": seat, "pilot": np["id"], "text": "%s (%s of %s) joins, ready to fly if needed." % [np["callsign"], p["relation"], campaign.pilots[main].get("callsign", "")]}]


static func set_active(story: StoryState, campaign: Campaign, seat: String, pid: String) -> Array:
	var cur := story.pilot_of_seat(seat)
	var second := str(story.seats[seat].get("second", ""))
	if pid == second:
		story.seats[seat]["second"] = cur
	story.seats[seat]["pilot"] = pid
	return [{"type": "active_pilot", "seat": seat, "pilot": pid, "text": "%s takes the cockpit." % campaign.pilots[pid].get("callsign", "")}]
