class_name NpcGen
extends RefCounted
## Procedural hub NPCs and hubs from our tables (data/game/npcs/) plus COMP/CON's name lists
## (via NameGen). Seeded: the same campaign seed and hub number give the same people.

const ROLES_FILE := "res://data/game/npcs/roles.json"
const TABLES_FILE := "res://data/game/npcs/tables.json"
const CULTURES_FILE := "res://data/game/story/cultures.json"
const MANUFACTURER_NAMES := {"GMS": "General Massive Systems", "IPS-N": "IPS-Northstar", "SSC": "Smith-Shimano Corpro",
	"HORUS": "HORUS", "HA": "Harrison Armory"}

static var _cache: Dictionary = {}


static func roles() -> Dictionary:
	return _json(ROLES_FILE).get("roles", {})


static func tables() -> Dictionary:
	return _json(TABLES_FILE)


## A new hub with its people. kind: "town", "base" or "station"; culture: a kit id from
## data/game/story/cultures.json ("" = picked by weight). Adds the NPCs to story.npcs and
## returns the hub record (also set as story.hub).
static func make_hub(story: StoryState, campaign: Campaign, hub_seed: int, kind: String = "town", culture: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, hub_seed, "hub"])
	var names := NameGen.new(rng)
	var t := tables()
	if culture == "" or not cultures().has(culture):
		culture = pick_culture(rng, kind)
	var kit: Dictionary = cultures().get(culture, {})
	var hub_names: Dictionary = t.get("hub_names", {})
	var pattern := _pick(rng, hub_names.get(kind, ["{a}"]))
	var a_pool: Array = (hub_names.get("a", ["Haven"]) as Array) + (kit.get("hub_a", []) as Array) + (kit.get("hub_a", []) as Array)
	var hub := {
		"id": "hub_%d" % hub_seed, "kind": kind, "culture": culture, "culture_name": kit.get("name", culture),
		"name": pattern.replace("{a}", _pick(rng, a_pool)),
		"planet": Sector.fresh_name(names, {}), "faction": names.faction(), "seed": hub_seed, "npcs": [], "spots": [],
	}
	hub["spots"] = HubLayout.spots(kind, rng, kit.get("spots", {}), float(kit.get("door_gap", 1.6)))
	hub["conflict"] = _conflict(rng, names, hub)
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
	var kit: Dictionary = cultures().get(str(hub.get("culture", "")), {})
	var titles: Array = (r.get("titles", [r.get("name", role)]) as Array) + (kit.get("titles", {}).get(role, []) as Array) + (kit.get("titles", {}).get(role, []) as Array)
	var looks: Dictionary = t.get("looks", {})
	var faction := str(hub.get("faction", ""))
	match str(r.get("faction", "hub")):
		"manufacturer":
			faction = manufacturer_for(campaign, rng)
		"outside":
			# The first faction agent at a hub speaks for the other side of its conflict.
			var b := str(hub.get("conflict", {}).get("b", ""))
			if role == "faction_agent" and b != "" and not bool(hub.get("_b_taken", false)):
				faction = b
				hub["_b_taken"] = true
			else:
				faction = names.faction()
				if faction == hub.get("faction", ""):
					faction = names.faction()
	var want: Dictionary = _pick_any(rng, t.get("wants", [{}]))
	var npc := {
		"id": id, "name": names.pilot_name(), "role": role, "role_name": r.get("name", role),
		"title": _pick(rng, titles), "faction": faction,
		"personality": _pick(rng, t.get("personalities", ["warm"])), "quirk": _pick(rng, t.get("quirks", [""])),
		"want": want.get("text", ""), "want_hook": want.get("hook", ""),
		"offers": (r.get("offers", []) as Array).duplicate(), "trusted_offers": (r.get("trusted_offers", []) as Array).duplicate(),
		"scene": r.get("scene", "local"), "spot": r.get("spot", "plaza"), "tags": (r.get("tags", []) as Array).duplicate(),
		"look": {}, "dead": false,
	}
	var arch: Dictionary = _pick_any(rng, t.get("archetypes", [{}]))
	npc["archetype"] = arch.get("name", "")
	npc["secret"] = _pick(rng, arch.get("secrets", [""]))
	var offers: Array = npc["offers"]
	npc["deal_reward"] = offers[rng.randi_range(0, offers.size() - 1)] if not offers.is_empty() else "reserve_backing"
	for k: String in looks:
		npc["look"][k] = _pick(rng, looks[k])
	npc["look"]["seed"] = rng.randi()
	# A full portrait for the builder's parts (the visuals session draws them).
	npc["portrait"] = PortraitSpec.complete(npc["look"], rng)
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


## The hub's situation (data/game/story/conflicts.json): its own faction against an outside one.
static func _conflict(rng: RandomNumberGenerator, names: NameGen, hub: Dictionary) -> Dictionary:
	var culture := str(hub.get("culture", ""))
	var liked: Array = cultures().get(culture, {}).get("conflicts", [])
	var list: Array = (_json("res://data/game/story/conflicts.json").get("conflicts", []) as Array).filter(func(c: Dictionary) -> bool:
		return not c.has("cultures") or (c["cultures"] as Array).has(culture))
	if list.is_empty():
		return {}
	var total := 0
	for c: Dictionary in list:
		total += _culture_weight(c, liked)
	var roll := rng.randi_range(1, maxi(total, 1))
	var pick: Dictionary = list[0]
	for c: Dictionary in list:
		roll -= _culture_weight(c, liked)
		if roll <= 0:
			pick = c
			break
	var b := names.faction()
	for i in range(5):
		if b != str(hub["faction"]):
			break
		b = names.faction()
	var out := {"id": pick["id"], "a": hub["faction"], "b": b, "a_role": pick.get("a_role", ""), "b_role": pick.get("b_role", ""),
		"a_hooks": pick.get("a_hooks", []), "b_hooks": pick.get("b_hooks", [])}
	out["summary"] = _pick(rng, pick.get("summary", [""])).replace("{a}", str(out["a"])).replace("{b}", b).replace("{hub}", str(hub["name"])).replace("{planet}", str(hub["planet"])).replace("{hub_faction}", str(hub["faction"]))
	return out


## A conflict or job's weight at this hub: x3 when the culture kit lists it.
static func _culture_weight(entry: Dictionary, liked: Array) -> int:
	return int(entry.get("weight", 1)) * (3 if liked.has(entry.get("id", "")) else 1)


static func cultures() -> Dictionary:
	return _json(CULTURES_FILE).get("kits", {})


## A culture kit for a hub of this kind, by the weights in cultures.json.
static func pick_culture(rng: RandomNumberGenerator, kind: String) -> String:
	var data := _json(CULTURES_FILE)
	var weights: Dictionary = data.get("weights", {})
	var kinds: Dictionary = data.get("kinds", {})
	var ids: Array = cultures().keys().filter(func(k: String) -> bool: return (kinds.get(k, [kind]) as Array).has(kind))
	ids.sort()
	if ids.is_empty():
		return "frontier_colony"
	var total := 0
	for k: String in ids:
		total += int(weights.get(k, 1))
	var roll := rng.randi_range(1, maxi(total, 1))
	for k: String in ids:
		roll -= int(weights.get(k, 1))
		if roll <= 0:
			return k
	return ids[0]


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
