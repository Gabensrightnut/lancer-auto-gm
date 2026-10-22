class_name Squadmate
extends RefCounted
## AI squadmates as characters (DESIGN.md "Solo play and AI squadmates"): a persona that fits
## the pilot's triggers and background, a team role and battle stance that fit the frame (or
## the persona, for the all-rounder Everest), and a memory of what happened to them: wounds,
## wrecked mechs, friends who died, being the squad's best shot, the kinds of replies they
## chose. The memory shifts what they like in conversations and downtime, and colors their
## banter between missions (banter.json) and barks in battle (barks.json).
##
## Memory lives in story.flags["_squad_memory"][pilot id] so it saves with the campaign.

const PERSONAS := "res://data/game/story/personas.json"
const BANTER := "res://data/game/story/banter.json"
const BARKS := "res://data/game/story/barks.json"
const KEY := "_squad_memory"

static var _cache: Dictionary = {}


static func _json(path: String) -> Dictionary:
	if not _cache.has(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_cache[path] = d if d is Dictionary else {}
	return _cache[path]


# --- Who they are ------------------------------------------------------------------------

## The persona a pilot's triggers and background point to (their best trigger counts double).
static func suggest(pilot: Dictionary) -> String:
	var d := _json(PERSONAS)
	var votes := {}
	var trig: Dictionary = d.get("from_triggers", {})
	for t: Dictionary in NarrativeCheck.triggers_of(pilot):
		var pr := str(trig.get(str(t["id"]), ""))
		if pr != "":
			votes[pr] = int(votes.get(pr, 0)) + int(t["rank"]) + 1
	var bg := str(d.get("from_background", {}).get(str(pilot.get("background", "")), ""))
	if bg != "":
		votes[bg] = int(votes.get(bg, 0)) + 2
	var best := "steady"
	var n := 0
	var keys := votes.keys()
	keys.sort()
	for k: String in keys:
		if int(votes[k]) > n:
			n = int(votes[k])
			best = k
	return best


## The team role: the frame's own (lancer-data mechtype) unless it's the all-rounder, then the
## persona's. {"role", "stance"} where stance is the AiDirector order.
static func role(pilot: Dictionary, persona: String, db: ContentDB = null) -> Dictionary:
	var d := _json(PERSONAS)
	var r := "Balanced"
	if db != null:
		var mech: Dictionary = {}
		for m: Dictionary in pilot.get("mechs", []):
			if m["id"] == pilot.get("active_mech", "") or mech.is_empty():
				mech = m
		var types: Array = db.frame(str(mech.get("frame", ""))).get("mechtype", [])
		if not types.is_empty():
			r = str(types[0])
	if r == "Balanced":
		r = str(d.get("roles", {}).get(persona, "Balanced"))
	return {"role": r, "stance": str(d.get("stance", {}).get(r, "follow"))}


## Battle orders for every AI squadmate (AiDirector.set_orders by seat/unit id).
static func orders(story: StoryState, campaign: Campaign, db: ContentDB = null) -> Dictionary:
	var out := {}
	for s: String in story.seats:
		if not story.is_ai(s):
			continue
		var p: Dictionary = campaign.pilots.get(story.pilot_of_seat(s), {})
		out[s] = {"stance": role(p, persona_of(story, s), db)["stance"]}
	return out


static func persona_of(story: StoryState, seat: String) -> String:
	return str(story.seats.get(seat, {}).get("persona", "steady"))


# --- What they remember ------------------------------------------------------------------

static func memory(story: StoryState, pid: String) -> Dictionary:
	if not story.flags.has(KEY):
		story.flags[KEY] = {}
	var all: Dictionary = story.flags[KEY]
	if not all.has(pid):
		all[pid] = {"wounds": 0, "downs": 0, "wrecks": 0, "lost": [], "missions": 0, "mvp": 0, "tags": {}, "recent": {}}
	return all[pid]


## Updates memories from story events (StoryEngine.submit calls this).
static func observe(story: StoryState, campaign: Campaign, events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"pilot_harmed":
				if int(e.get("amount", 0)) > 0:
					var m := memory(story, str(e["pilot"]))
					m["wounds"] = int(m["wounds"]) + int(e["amount"])
					m["recent"]["wounded"] = true
			"down_and_out_roll":
				var m := memory(story, str(e["pilot"]))
				m["downs"] = int(m["downs"]) + 1
				m["recent"]["wounded"] = true
			"pilot_died":
				var fallen := str(campaign.pilots.get(str(e["pilot"]), {}).get("callsign", ""))
				for pid: String in campaign.pilots:
					if pid != str(e["pilot"]) and story.is_alive(pid):
						var m := memory(story, pid)
						if not (m["lost"] as Array).has(fallen):
							(m["lost"] as Array).append(fallen)
						m["recent"]["lost_friend"] = fallen
			"dialogue_choice":
				var pid := story.pilot_of_seat(str(e.get("by", "")))
				if pid != "":
					var m := memory(story, pid)
					for t: Variant in e.get("tags", []):
						m["tags"][str(t)] = int(m["tags"].get(str(t), 0)) + 1
			"debrief":
				var sm: Dictionary = story.last_mission.get("summary", {})
				for pid: String in campaign.pilots:
					if not story.is_alive(pid):
						continue
					var m := memory(story, pid)
					var cs := str(campaign.pilots[pid].get("callsign", ""))
					m["missions"] = int(m["missions"]) + 1
					m["recent"]["result"] = str(e.get("outcome", ""))
					if (sm.get("lost", []) as Array).has(cs):
						m["wrecks"] = int(m["wrecks"]) + 1
						m["recent"]["wrecked"] = true
					if str(sm.get("mvp", "")) == cs:
						m["mvp"] = int(m["mvp"]) + 1
						m["recent"]["mvp"] = true


## Persona likes shifted by memory (personas.json "history").
static func likes(story: StoryState, pid: String, persona: Dictionary) -> Dictionary:
	var out: Dictionary = (persona.get("likes", {}) as Dictionary).duplicate()
	var h: Dictionary = _json(PERSONAS).get("history", {})
	var m := memory(story, pid)
	var apply := func(key: String) -> void:
		for t: String in h.get(key, {}).get("likes", {}):
			out[t] = float(out.get(t, 0)) + float(h[key]["likes"][t])
	if int(m["wounds"]) + int(m["downs"]) * 3 >= int(h.get("wounded", {}).get("min", 3)):
		apply.call("wounded")
	if not (m["lost"] as Array).is_empty():
		apply.call("lost_friend")
	if int(m["mvp"]) >= int(h.get("mvp", {}).get("min", 2)):
		apply.call("mvp")
	if int(m["wrecks"]) >= int(h.get("wrecked", {}).get("min", 2)):
		apply.call("wrecked")
	return out


## Downtime wishes shaped by memory: someone who just lost a friend goes for a drink to forget
## (if there's a bar), otherwise their persona's own list.
static func downtime_prefs(story: StoryState, pid: String, persona: Dictionary) -> Array:
	var prefs: Array = (persona.get("downtime", ["dt_get_focused"]) as Array).duplicate()
	var m := memory(story, pid)
	if str(m["recent"].get("lost_friend", "")) != "" and StoryConditions.check({"hub_has": "bar"}, story, null, {}):
		prefs.push_front("dt_get_a_damn_drink:Forget the last mission")
	return prefs


# --- What they say -----------------------------------------------------------------------

## A topic for this squadmate's banter, most pressing first.
static func topic(story: StoryState, pid: String) -> String:
	var m := memory(story, pid)
	var rc: Dictionary = m["recent"]
	if str(rc.get("lost_friend", "")) != "":
		return "lost_friend"
	if bool(rc.get("wrecked", false)):
		return "wrecked"
	if bool(rc.get("wounded", false)):
		return "wounded"
	if bool(rc.get("mvp", false)):
		return "mvp"
	var res := str(rc.get("result", ""))
	if res == "victory":
		return "won"
	if res == "defeat":
		return "lost"
	# Small talk alternates between the situation at the hub and everything else.
	if not story.arc.is_empty() and str(m.get("last_topic", "")) != "arc":
		return "arc"
	return "idle"


## One to three lines of squad banter between missions: AI squadmates talk about what they
## remember, sometimes with a reply. Clears the "recent" memories afterwards.
static func banter(story: StoryState, campaign: Campaign, max_lines: int = 2) -> Array:
	var b := _json(BANTER)
	var events: Array = []
	var seats := story.seats.keys()
	seats.sort()
	var speakers: Array = seats.filter(func(s: String) -> bool: return story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)))
	if speakers.is_empty():
		return events
	# The squadmate with the most to say goes first.
	var order := ["lost_friend", "wrecked", "wounded", "mvp", "won", "lost", "arc", "idle"]
	speakers.sort_custom(func(a: String, c: String) -> bool:
		return order.find(topic(story, story.pilot_of_seat(a))) < order.find(topic(story, story.pilot_of_seat(c))))
	for i in range(mini(max_lines, speakers.size())):
		var s: String = speakers[i]
		var pid := story.pilot_of_seat(s)
		var persona := persona_of(story, s)
		var t := topic(story, pid)
		var lines: Array = b.get("personas", {}).get(persona, b.get("personas", {}).get("steady", {})).get(t, [])
		if lines.is_empty():
			continue
		var ctx := {"speaker": pid, "vars": _vars(story, campaign, pid)}
		var text := StoryText.fill(str(lines[_pick(story, "banter:%s:%s" % [persona, t], lines.size())]), story, campaign, ctx)
		events.append({"type": "banter", "pilot": pid, "seat": s, "persona": persona, "topic": t, "text": text,
			"face": {"portrait": PortraitSpec.for_pilot(campaign.pilots[pid]), "expression": _banter_face(t)}})
		memory(story, pid)["last_topic"] = t
		# Someone answers, now and then.
		var others: Array = seats.filter(func(o: String) -> bool: return o != s and story.is_alive(story.pilot_of_seat(o)))
		if not others.is_empty() and story.dice.die(3) == 1:
			var o: String = others[story.dice.die(others.size()) - 1]
			var replies: Array = b.get("replies", {}).get("reply_" + persona_of(story, o), [])
			if not replies.is_empty():
				events.append({"type": "banter", "pilot": story.pilot_of_seat(o), "seat": o, "persona": persona_of(story, o), "topic": "reply",
					"text": str(replies[_pick(story, "reply:" + persona_of(story, o), replies.size())]),
					"face": {"portrait": PortraitSpec.for_pilot(campaign.pilots[story.pilot_of_seat(o)]), "expression": "neutral"}})
	for pid: String in campaign.pilots:
		memory(story, pid)["recent"] = {}
	return events


## Barks for one battle event, for AI squadmates' units. `unit_pilot` = unit id -> pilot id;
## `seat_of_unit` = unit id -> seat. Cosmetic: uses its own seeded RNG, never the game dice.
## Returns [{unit, pilot, text}].
static func barks_for(story: StoryState, campaign: Campaign, e: Dictionary, unit_pilot: Dictionary, seat_of_unit: Dictionary) -> Array:
	var k := _json(BARKS)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([e, story.story_seed])
	var out: Array = []
	var say := func(unit: String, moment: String, extra: Dictionary) -> void:
		var seat := str(seat_of_unit.get(unit, ""))
		var pid := str(unit_pilot.get(unit, ""))
		if seat == "" or pid == "" or not story.is_ai(seat) or rng.randf() > float(k.get("chance", 0.45)):
			return
		var persona := persona_of(story, seat)
		var lines: Array = k.get("personas", {}).get(persona, {}).get(moment, [])
		var m := memory(story, pid)
		if moment == "start":
			if not (m["lost"] as Array).is_empty():
				lines = k.get("history", {}).get("lost_friend_start", lines)
			elif int(m["wounds"]) >= 3:
				lines = k.get("history", {}).get("wounded_start", lines)
		if lines.is_empty():
			return
		var vars := _vars(story, campaign, pid)
		vars.merge(extra, true)
		out.append({"unit": unit, "pilot": pid, "face": {"portrait": PortraitSpec.for_pilot(campaign.pilots.get(pid, {"id": pid})),
			"expression": _bark_face(moment)}, "text": StoryText.fill(str(lines[rng.randi_range(0, lines.size() - 1)]), story, campaign, {"speaker": pid, "vars": vars})})
	match str(e.get("type", "")):
		"combat_started":
			for u: String in unit_pilot:
				say.call(u, "start", {})
		"attack_rolled":
			var res := str(e.get("result", ""))
			say.call(str(e.get("attacker", "")), "crit" if res == "crit" else ("hit" if res == "hit" else "miss"), {})
		"damage_dealt":
			say.call(str(e.get("target", "")), "damaged", {})
		"structure_lost":
			say.call(str(e.get("unit", "")), "structure", {})
		"stress_lost":
			say.call(str(e.get("unit", "")), "overheat", {})
		"unit_destroyed":
			var dead := str(e.get("unit", ""))
			if unit_pilot.has(dead):
				var ally := str(campaign.pilots.get(str(unit_pilot[dead]), {}).get("callsign", "them"))
				for u: String in unit_pilot:
					if u != dead:
						say.call(u, "ally_down", {"ally": ally})
						break
			else:
				for u: String in unit_pilot:
					say.call(u, "enemy_down", {})
					break
	return out


static func _banter_face(t: String) -> String:
	return {"lost_friend": "sad", "wrecked": "worried", "wounded": "hurt", "mvp": "smug", "won": "smiling", "lost": "sad", "arc": "determined"}.get(t, "neutral")


static func _bark_face(moment: String) -> String:
	return {"start": "determined", "hit": "smiling", "crit": "shouting", "miss": "angry", "damaged": "hurt", "structure": "hurt",
		"overheat": "worried", "ally_down": "shouting", "enemy_down": "smug"}.get(moment, "neutral")


static func _vars(story: StoryState, campaign: Campaign, pid: String) -> Dictionary:
	var m := memory(story, pid)
	var others: Array = campaign.pilots.keys().filter(func(o: String) -> bool: return o != pid and story.is_alive(o))
	others.sort()
	var v := {"other": str(campaign.pilots.get(others[story.dice.die(others.size()) - 1] if not others.is_empty() else "", {}).get("callsign", "everyone")),
		"friend": str((m["lost"] as Array).back()) if not (m["lost"] as Array).is_empty() else "",
		"last_place": str(story.last_mission.get("place", "the last job"))}
	return v


static func _pick(story: StoryState, key: String, n: int) -> int:
	return StoryText._pick_index(key, n, story)
