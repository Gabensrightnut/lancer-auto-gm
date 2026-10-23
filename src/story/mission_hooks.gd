class_name MissionHooks
extends RefCounted
## Procedural mission hooks (DESIGN.md section 9): who wants what done, the goal and the
## stakes (a briefing sets both, Core p.40), from data/game/story/hooks.json, the hub's
## people and COMP/CON's name lists. Story events (a favor owed, stolen goods...) add their
## own hooks; the job board fills the rest.

const FILE := "res://data/game/story/hooks.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"templates": {}}
	return _data


## A hook from template `template_id`. opts: patron (npc id). {} if the template is unknown.
static func make(story: StoryState, campaign: Campaign, template_id: String, opts: Dictionary = {}) -> Dictionary:
	var t: Dictionary = data().get("templates", {}).get(template_id, {})
	if t.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, story.mission_number, story.hooks.size(), template_id, story.dice.die(1000)])
	var names := NameGen.new(rng)
	var patron_id := str(opts.get("patron", ""))
	if patron_id == "" or not story.npcs.has(patron_id):
		patron_id = _pick_patron(story, rng, campaign)
	var patron: Dictionary = story.npcs.get(patron_id, {})
	var conflict: Dictionary = story.hub.get("conflict", {})
	var rival := str(opts.get("rival", ""))
	if rival == "" and not conflict.is_empty():
		var pf := str(patron.get("faction", ""))
		rival = str(conflict["b"]) if pf == str(conflict["a"]) else (str(conflict["a"]) if pf == str(conflict["b"]) else "")
	var hook := {
		"id": "hook_%d_%d" % [story.mission_number, story.hooks.size() + rng.randi_range(0, 9999)],
		"rival": rival, "hazardous": bool(t.get("hazardous", false)),
		"template": template_id, "patron_id": patron_id,
		"patron": str(patron.get("name", "the local council")),
		"faction": str(patron.get("faction", story.hub.get("faction", ""))),
		"place": _pick(rng, data().get("places", ["the outskirts"])),
		"enemy": _pick(rng, data().get("enemies", ["raiders"])),
		"cargo": names.cargo(), "operation": names.operation(),
		"sitrep": _pick(rng, t.get("sitreps", ["sitrep_standardcombat"])),
		"seed": rng.randi(), "culture": str(story.hub.get("culture", "")),
		"map_culture": str(NpcGen.cultures().get(str(story.hub.get("culture", "")), {}).get("map_culture", "")),
		# The world's own landscape (Sector), else one of its culture kit's.
		"landscape": str(story.hub["landscape"]) if str(story.hub.get("landscape", "")) != "" else _pick(rng, NpcGen.cultures().get(str(story.hub.get("culture", "")), {}).get("landscapes", [])),
	}
	# Fights in town (DESIGN: battles where the squad is): the job happens at one of the hub's
	# own buildings, and world-maps builds the battle from the town's layout (town_for).
	# Boarding jobs (Core p.42: board a hostile ship and take it over): which map world-maps
	# builds (two docked ships, an enemy ship's interior, the squad's own transport).
	if t.has("boarding"):
		hook["boarding"] = (t["boarding"] as Dictionary).duplicate()
		hook["landscape"] = ""  # the generator builds the ships from opts.boarding
	var spot := town_spot(story, str(t.get("town_spot", "")), rng)
	if bool(t.get("in_town", false)) and not spot.is_empty():
		hook["in_town"] = true
		hook["on_foot"] = bool(t.get("on_foot", false))
		hook["town_spot"] = str(spot["id"])
		hook["place"] = str(spot.get("name", hook["place"]))
	var ctx := {"hook": hook, "npc": patron_id, "vars": {"place": hook["place"], "enemy": hook["enemy"], "cargo": hook["cargo"],
		"patron": hook["patron"], "hub": story.hub.get("name", "the settlement"), "rival": rival, "spot": str(spot.get("name", "the square"))}}
	for k in ["title", "objective", "stakes", "question"]:
		hook[k] = StoryText.fill(_pick(rng, t.get(k, [""])), story, campaign, ctx)
	hook["success"] = (t.get("success", []) as Array).duplicate(true)
	hook["failure"] = (t.get("failure", []) as Array).duplicate(true)
	# Helping one side of the hub's conflict costs you with the other (our bookkeeping).
	if rival != "":
		hook["success"].append({"standing": "$hook.rival", "add": -1})
	# A job that touches a pilot's past (Core p.43: stakes tied to backgrounds).
	var personal := BackgroundStory.personal_for(story, campaign, template_id, rng)
	if not personal.is_empty():
		hook["personal"] = personal
		hook["stakes"] = "%s %s" % [hook["stakes"], personal["line"]]
	var twist := pick_twist(rng, str(opts.get("twist", "")), campaign)
	if not twist.is_empty():
		if twist.has("town"):
			# Jumped before leaving town: the fight is at this spot (hidden with the twist).
			twist["town"] = (twist["town"] as Dictionary).duplicate()
			twist["town"]["spot"] = str(spot.get("id", "plaza"))
		twist["reveal"] = StoryText.fill(str(twist["reveal"]), story, campaign, ctx)
		twist["question"] = StoryText.fill(str(twist["question"]), story, campaign, ctx)
		hook["twist"] = twist
	# Who leads the other side: an arc's commander, or one back for revenge (Rivals).
	Rivals.attach(story, hook, rng, str(opts.get("commander", "")))
	# Where it is, and how the squad gets there: walk, dropship, ship or a hired ride (Journeys).
	Journeys.dress(story, campaign, hook)
	return hook


## A hidden mid-mission twist (Core p.43: goals change when new information comes to light),
## or {} (data/game/story/twists.json). `wanted` forces one by id.
## The table's tone makes twists likelier or rarer, and content it switched off never comes up
## (SessionZero).
## A building of the current hub for a fight in town: one of `kind` if it has one, else the
## bar, the market or the square.
static func town_spot(story: StoryState, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var spots: Array = story.hub.get("spots", [])
	for k: String in ([kind] if kind != "" else []) + ["bar", "market", "plaza"]:
		var found: Array = spots.filter(func(s: Dictionary) -> bool: return str(s.get("kind", "")) == k)
		if not found.is_empty():
			return found[rng.randi_range(0, found.size() - 1)]
	return spots[0] if not spots.is_empty() else {}


## What world-maps needs to build a battle in the hub itself, or {} for a fight elsewhere: the
## hub, its layout (the same spots the 3D town is built from) and where the fight starts.
static func town_for(story: StoryState, hook: Dictionary) -> Dictionary:
	var tw: Dictionary = hook.get("twist", {}).get("town", {})
	if not bool(hook.get("in_town", false)) and tw.is_empty():
		return {}
	var at := str(hook.get("town_spot", tw.get("spot", "plaza")))
	var spot: Dictionary = {}
	for s: Dictionary in story.hub.get("spots", []):
		if str(s["id"]) == at:
			spot = s
	return {"hub_id": str(story.hub.get("id", "")), "hub_name": str(story.hub.get("name", "")), "kind": str(story.hub.get("kind", "town")),
		"culture": str(story.hub.get("culture", "")), "map_culture": str(hook.get("map_culture", "")), "landscape": str(story.hub.get("landscape", hook.get("landscape", ""))),
		"seed": int(story.hub.get("seed", 0)), "spots": (story.hub.get("spots", []) as Array).duplicate(true),
		"at": at, "at_name": str(spot.get("name", "")), "on_foot": bool(hook.get("on_foot", false)) or bool(tw.get("on_foot", false))}


static func pick_twist(rng: RandomNumberGenerator, wanted: String = "", campaign: Campaign = null) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/story/twists.json"))
	var list: Array = (d.get("twists", []) if d is Dictionary else []).filter(func(t: Dictionary) -> bool:
		return str(t["id"]) == wanted or SessionZero.allowed(campaign, "twists", str(t["id"])))
	if list.is_empty() or (wanted == "" and rng.randf() > float(d.get("chance", 0.4)) * SessionZero.twist_factor(campaign)):
		return {}
	var pick: Dictionary = {}
	if wanted != "":
		for t: Dictionary in list:
			if str(t["id"]) == wanted:
				pick = t
	if pick.is_empty():
		var total := 0
		for t: Dictionary in list:
			total += int(t.get("weight", 1))
		var roll := rng.randi_range(1, maxi(total, 1))
		for t: Dictionary in list:
			roll -= int(t.get("weight", 1))
			if roll <= 0:
				pick = t
				break
	var out := {"id": pick["id"], "reveal": _pick(rng, pick.get("reveal", [""])), "question": str(pick.get("question", "")),
		"effects": (pick.get("effects", []) as Array).duplicate(true)}
	if pick.has("town"):
		out["town"] = (pick["town"] as Dictionary).duplicate()
	return out


## Fills the job board up to `count` hooks from the board templates (by weight), preferring
## the wants of people the squad has met.
static func fill_board(story: StoryState, campaign: Campaign, count: int = 3) -> Array:
	# The authored main campaign (AI GM): its chapter's job only, never procedural plot.
	if CampaignScript.active(campaign):
		return CampaignScript.fill_board(story, campaign)
	var added: Array = []
	var templates: Dictionary = data().get("templates", {})
	var arc_hook := StoryArc.ensure(story, campaign)
	if not arc_hook.is_empty():
		added.append(arc_hook)
	var guard := 0
	while story.hooks.size() < count and guard < 20:
		guard += 1
		var tid := ""
		var patron := ""
		for npc_id: String in story.contacts:
			var npc: Dictionary = story.npcs.get(npc_id, {})
			var want := str(npc.get("want_hook", ""))
			if want != "" and not _has_template_from(story, want, npc_id):
				tid = want
				patron = npc_id
				break
		if tid == "":
			tid = _weighted(story, templates)
		var hook := make(story, campaign, tid, {"patron": patron})
		if not hook.is_empty():
			story.hooks.append(hook)
			added.append(hook)
	# The first town: a couple of short local jobs you can walk out to (a reason to leave town
	# before the first big mission).
	if story.mission_number <= 1 and campaign.history.is_empty():
		var n := int(Townsfolk.data().get("start_area", {}).get("local_jobs", 2))
		for h: Dictionary in story.hooks:
			if n <= 0:
				break
			if h.has("boarding") or bool(h.get("tutorial", false)):
				continue
			h["local"] = true
			h["travel"] = "walk"
			h["travel_hours"] = 0
			h["travel_text"] = "It's close: walk out of town in your mechs."
			if h.get("site") is Dictionary:
				h["site"]["near"] = true
			n -= 1
	return added


static func _has_template_from(story: StoryState, tid: String, patron: String) -> bool:
	for h: Dictionary in story.hooks:
		if str(h["template"]) == tid and str(h["patron_id"]) == patron:
			return true
	for done: Variant in story.flags.get("_hooks_done", []):
		if str(done) == tid + ":" + patron:
			return true
	return false


## A board job by weight; the hub's culture kit makes its own jobs likelier and keeps
## culture-only jobs (e.g. a train job) to the kits they belong to.
static func _weighted(story: StoryState, templates: Dictionary) -> String:
	var culture := str(story.hub.get("culture", ""))
	var liked: Array = NpcGen.cultures().get(culture, {}).get("hooks", [])
	var ids: Array = []
	var w := {}
	var total := 0
	for tid: String in templates:
		var t: Dictionary = templates[tid]
		if not bool(t.get("board", false)):
			continue
		if t.has("cultures") and not (t["cultures"] as Array).has(culture):
			continue
		ids.append(tid)
		w[tid] = int(t.get("weight", 1)) * (3 if liked.has(tid) else 1)
		total += int(w[tid])
	ids.sort()
	if ids.is_empty():
		return ""
	var roll := story.dice.die(maxi(total, 1))
	for tid: String in ids:
		roll -= int(w[tid])
		if roll <= 0:
			return tid
	return ids[0]


static func _pick_patron(story: StoryState, rng: RandomNumberGenerator, campaign: Campaign = null) -> String:
	var roles: Array = ["faction_agent", "local", "company_rep", "bartender"]
	# Session zero's patron ("who gives us orders?") decides who usually brings the work.
	if campaign != null and not (campaign.options.get("patron_roles", []) as Array).is_empty() and rng.randf() < 0.7:
		roles = campaign.options["patron_roles"]
	var ids: Array = (story.hub.get("npcs", []) as Array).filter(func(n: String) -> bool:
		return not bool(story.npcs.get(n, {}).get("dead", false)) and str(story.npcs.get(n, {}).get("role", "")) in roles)
	if ids.is_empty():
		ids = (story.hub.get("npcs", []) as Array).filter(func(n: String) -> bool: return not bool(story.npcs.get(n, {}).get("dead", false)))
	return str(ids[rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""


static func _pick(rng: RandomNumberGenerator, list: Variant) -> String:
	var arr: Array = list if list is Array else [list]
	return str(arr[rng.randi_range(0, arr.size() - 1)]) if not arr.is_empty() else ""
