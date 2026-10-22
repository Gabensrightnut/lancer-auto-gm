class_name NpcGen
extends RefCounted
## Procedural hub NPCs and hubs from our tables (data/game/npcs/) plus COMP/CON's name lists
## (via NameGen). Seeded: the same campaign seed and hub number give the same people.

const ROLES_FILE := "res://data/game/npcs/roles.json"
const TABLES_FILE := "res://data/game/npcs/tables.json"
const MANUFACTURER_NAMES := {"GMS": "General Massive Systems", "IPS-N": "IPS-Northstar", "SSC": "Smith-Shimano Corpro",
	"HORUS": "HORUS", "HA": "Harrison Armory"}

static var _cache: Dictionary = {}


static func roles() -> Dictionary:
	return _json(ROLES_FILE).get("roles", {})


static func tables() -> Dictionary:
	return _json(TABLES_FILE)


## A new hub with its people. kind: "town", "base" or "station". Adds the NPCs to story.npcs
## and returns the hub record (also set as story.hub).
static func make_hub(story: StoryState, campaign: Campaign, hub_seed: int, kind: String = "town") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, hub_seed, "hub"])
	var names := NameGen.new(rng)
	var t := tables()
	var hub_names: Dictionary = t.get("hub_names", {})
	var pattern := _pick(rng, hub_names.get(kind, ["{a}"]))
	var hub := {
		"id": "hub_%d" % hub_seed, "kind": kind, "name": pattern.replace("{a}", _pick(rng, hub_names.get("a", ["Haven"]))),
		"planet": names.planet(), "faction": names.faction(), "seed": hub_seed, "npcs": [], "spots": [],
	}
	hub["spots"] = HubLayout.spots(kind, rng)
	var plan: Dictionary = _json(ROLES_FILE).get("hub_roles", {}).get(kind, {})
	var role_list: Array = (plan.get("always", []) as Array).duplicate()
	var pool: Array = (plan.get("pool", []) as Array).duplicate()
	for i in range(int(plan.get("extra", 0))):
		if pool.is_empty():
			break
		role_list.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	var i := 0
	for role: String in role_list:
		var npc := make_npc(rng, names, campaign, hub, role, "%s_npc%d" % [hub["id"], i])
		story.npcs[npc["id"]] = npc
		(hub["npcs"] as Array).append(npc["id"])
		i += 1
	story.hub = hub
	return hub


static func make_npc(rng: RandomNumberGenerator, names: NameGen, campaign: Campaign, hub: Dictionary, role: String, id: String) -> Dictionary:
	var r: Dictionary = roles().get(role, {})
	var t := tables()
	var looks: Dictionary = t.get("looks", {})
	var faction := str(hub.get("faction", ""))
	match str(r.get("faction", "hub")):
		"manufacturer":
			faction = manufacturer_for(campaign, rng)
		"outside":
			faction = names.faction()
			if faction == hub.get("faction", ""):
				faction = names.faction()
	var want: Dictionary = _pick_any(rng, t.get("wants", [{}]))
	var npc := {
		"id": id, "name": names.pilot_name(), "role": role, "role_name": r.get("name", role),
		"title": _pick(rng, r.get("titles", [r.get("name", role)])), "faction": faction,
		"personality": _pick(rng, t.get("personalities", ["warm"])), "quirk": _pick(rng, t.get("quirks", [""])),
		"want": want.get("text", ""), "want_hook": want.get("hook", ""),
		"offers": (r.get("offers", []) as Array).duplicate(), "trusted_offers": (r.get("trusted_offers", []) as Array).duplicate(),
		"scene": r.get("scene", "local"), "spot": r.get("spot", "plaza"), "tags": (r.get("tags", []) as Array).duplicate(),
		"look": {}, "dead": false,
	}
	for k: String in looks:
		npc["look"][k] = _pick(rng, looks[k])
	npc["look"]["seed"] = rng.randi()
	return npc


## The manufacturer a company rep works for: one the squad holds a license from, else GMS
## (every pilot is licensed for GMS, Core p.18).
static func manufacturer_for(campaign: Campaign, rng: RandomNumberGenerator) -> String:
	var held: Array = []
	if campaign != null:
		var db_frames := _frames()
		for p: Dictionary in campaign.pilots.values():
			for frame_id: String in p.get("licenses", {}):
				var src := str(db_frames.get(frame_id, ""))
				if src != "" and not held.has(src):
					held.append(src)
	held.sort()
	if held.is_empty() or rng.randf() < 0.35:
		return MANUFACTURER_NAMES["GMS"]
	return str(MANUFACTURER_NAMES.get(held[rng.randi_range(0, held.size() - 1)], "General Massive Systems"))


## A pilot-side contact made by downtime (Get a Damn Drink's "friend"), stored like hub NPCs.
static func make_contact(story: StoryState, campaign: Campaign, role: String = "local") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, story.npcs.size(), "contact"])
	var npc := make_npc(rng, NameGen.new(rng), campaign, story.hub, role, "contact_%d" % story.npcs.size())
	story.npcs[npc["id"]] = npc
	return npc


static func _frames() -> Dictionary:
	if not _cache.has("frames"):
		var out := {}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lancer-data/frames.json"))
		for f: Dictionary in (data if data is Array else []):
			out[str(f["id"])] = str(f.get("source", ""))
		_cache["frames"] = out
	return _cache["frames"]


static func _pick(rng: RandomNumberGenerator, list: Variant) -> String:
	var arr: Array = list if list is Array else [list]
	return str(arr[rng.randi_range(0, arr.size() - 1)]) if not arr.is_empty() else ""


static func _pick_any(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)] if not arr.is_empty() else {}


static func _json(path: String) -> Dictionary:
	if not _cache.has(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_cache[path] = data if data is Dictionary else {}
	return _cache[path]
