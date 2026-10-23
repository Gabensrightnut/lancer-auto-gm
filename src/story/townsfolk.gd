class_name Townsfolk
extends RefCounted
## Every person you can talk to is worth talking to (data/game/npcs/townsfolk.json): a
## backstory line, a worry, a tie to someone else in town, and something they can do for you
## (a job they need done, a rumour or intel, a contact, training, a trade); no two people in
## one town want the same job done. They remember you: what you did for them or to them, and
## they bring it up the next time you talk. Conversations open up as you come back and as they
## trust you more (extra replies in any conversation: options_for).

const FILE := "res://data/game/npcs/townsfolk.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return str(list[rng.randi_range(0, list.size() - 1)]) if not list.is_empty() else ""


## Gives everyone in a new hub their story and something to offer, and makes sure no two of
## them want the same job (NpcGen.make_hub).
static func dress_hub(story: StoryState, hub: Dictionary, rng: RandomNumberGenerator, wants: Array) -> void:
	var d := data()
	var ids: Array = hub.get("npcs", [])
	var all_wants: Array = wants + (d.get("more_wants", []) as Array)
	var used := {}
	for id: String in ids:
		var npc: Dictionary = story.npcs[id]
		var role := str(npc.get("role", "local"))
		var lines: Array = d.get("backstory", {}).get(role, d.get("backstory", {}).get("default", []))
		npc["backstory"] = _pick(rng, lines).replace("{name}", str(npc["name"])).replace("{event}", _pick(rng, d.get("events", ["the old days"]))) \
			.replace("{faction}", str(npc.get("faction", hub.get("faction", "the town"))))
		npc["worry"] = _pick(rng, d.get("worries", []))
		npc["service"] = str(d.get("services", {}).get(role, d.get("services", {}).get("default", "rumor")))
		npc["rumor"] = _pick(rng, d.get("rumors", []))
		# No two people in town want the same job done.
		var hook := str(npc.get("want_hook", ""))
		if hook != "" and used.has(hook):
			var free: Array = all_wants.filter(func(w: Dictionary) -> bool: return str(w.get("hook", "")) != "" and not used.has(str(w["hook"])))
			if not free.is_empty():
				var w: Dictionary = free[rng.randi_range(0, free.size() - 1)]
				npc["want"] = str(w["text"])
				npc["want_hook"] = str(w["hook"])
			else:
				npc["want_hook"] = ""
		if str(npc.get("want_hook", "")) != "":
			used[str(npc["want_hook"])] = true
	# A tie to someone else here.
	for i in range(ids.size()):
		if ids.size() < 2:
			break
		var npc: Dictionary = story.npcs[ids[i]]
		var other := str(ids[(i + 1 + rng.randi_range(0, ids.size() - 2)) % ids.size()])
		if other == str(ids[i]):
			continue
		npc["tie"] = {"npc": other, "text": _pick(rng, data().get("ties", [])).replace("{other}", str(story.npcs[other]["name"]))}


## What they did for (or to) this person, remembered to bring up next time.
static func remember(story: StoryState, npc_id: String, kind: String, what: String) -> void:
	var npc: Dictionary = story.npcs.get(npc_id, {})
	if npc.is_empty():
		return
	var mem: Array = npc.get("memory", [])
	mem.append({"kind": kind, "what": what, "mission": story.mission_number, "said": false})
	npc["memory"] = mem.slice(maxi(0, mem.size() - 6))


## The line they open with when they remember something they haven't brought up yet ("").
static func memory_line(story: StoryState, npc_id: String) -> String:
	var npc: Dictionary = story.npcs.get(npc_id, {})
	for m: Dictionary in npc.get("memory", []):
		if bool(m.get("said", false)):
			continue
		m["said"] = true
		var lines: Array = data().get("memory", {}).get(str(m["kind"]), [])
		if lines.is_empty():
			return ""
		var t := str(lines[absi(hash([npc_id, m["mission"], m["kind"]])) % lines.size()]).replace("{what}", str(m["what"]))
		return t.substr(0, 1).to_upper() + t.substr(1)
	return ""


## Extra replies in any conversation with a townsperson: who they are (the first time), what's
## worrying them (once you've met before, or they trust you), and what they can do for you.
static func options_for(story: StoryState, campaign: Campaign, ctx: Dictionary, node_id: String) -> Array:
	if node_id != "menu":
		return []
	var id := str(ctx.get("npc", ""))
	var npc: Dictionary = story.npcs.get(id, {})
	if npc.is_empty() or bool(npc.get("authored", false)) or not npc.has("backstory"):
		return []
	var out: Array = []
	out.append({"id": "tf_about", "once": true, "extra": true, "text": "Tell me about yourself.", "tags": ["curious"], "priority": 2, "next": "menu",
		"reply": str(npc["backstory"]) + (" %s %s." % [_short(str(npc["name"])), npc["tie"]["text"]] if npc.has("tie") and story.npcs.has(str(npc["tie"].get("npc", ""))) else "")})
	var met_before := int(npc.get("talks", 0)) >= 1 or int(npc.get("trust", 0)) >= 1 or story.get_standing(str(npc.get("faction", ""))) >= 1
	if met_before and str(npc.get("worry", "")) != "":
		out.append({"id": "tf_worry", "once": true, "extra": true, "text": "Something's on your mind. What is it?", "tags": ["kind"], "priority": 2, "next": "menu",
			"reply": "Honestly? %s." % _cap(str(npc["worry"]))})
	var svc := str(npc.get("service", ""))
	var lines: Array = data().get("service_lines", {}).get(svc, [])
	if not lines.is_empty():
		var rumor := str(npc.get("rumor", ""))
		var text := str({"rumor": "Heard anything worth knowing?", "intel": "Anything I should watch out for?", "training": "Can you teach me anything?",
			"trade": "Got anything for a lancer?", "contact": "Who should I know around here?"}.get(svc, "Anything you can do for me?"))
		var effects: Array = []
		if svc == "contact":
			effects.append({"contact": "$npc"})
		elif svc == "training":
			effects.append({"reserve": "custom", "name": "A trick from {npc}", "to": "speaker", "source": "$npc.name", "note": "+1 Accuracy on one skill check this mission (training)"})
		out.append({"id": "tf_service", "once": true, "extra": true, "text": text, "tags": ["practical"], "priority": 2, "next": "menu", "effects": effects,
			"reply": str(lines[absi(hash([id, svc])) % lines.size()]).replace("{rumor}", rumor)})
	return out


static func _short(name: String) -> String:
	return name.split(" ")[0] if name.contains(" ") else name


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)
