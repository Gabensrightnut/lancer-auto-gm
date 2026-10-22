class_name PortraitSpec
extends RefCounted
## Data hooks for the portrait builder (data/game/story/portraits.json): the list of parts with
## options and color slots, palettes, randomize-with-locks, and the expression set dialogue uses.
## A portrait is {version: 2, parts: {part id: {option, primary, secondary}}}. Pilots keep it in
## pilot["portrait"]; NPCs in npc["look"] (older flat looks are read too). Until the real
## builder art exists, flatten() turns it into what the placeholder Portrait draws.

const FILE := "res://data/game/story/portraits.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"parts": [], "expressions": []}
	return _data


static func parts() -> Array:
	return data().get("parts", [])


static func expression_ids() -> Array:
	return (data().get("expressions", []) as Array).map(func(e: Dictionary) -> String: return str(e["id"]))


## The placeholder face for an expression id (unknown ids are neutral).
static func draw_as(expr: String) -> String:
	for e: Dictionary in data().get("expressions", []):
		if str(e["id"]) == expr:
			return str(e.get("draw_as", "neutral"))
	return "neutral"


## A full random portrait. `locks` = {part id: true} keeps those parts from `keep`.
static func randomize(rng: RandomNumberGenerator, keep: Dictionary = {}, locks: Dictionary = {}) -> Dictionary:
	var pal: Dictionary = data().get("palettes", {})
	var out := {"version": 2, "parts": {}}
	var kept: Dictionary = normalize(keep).get("parts", {}) if not keep.is_empty() else {}
	for p: Dictionary in parts():
		var pid := str(p["id"])
		if locks.has(pid) and kept.has(pid):
			out["parts"][pid] = (kept[pid] as Dictionary).duplicate()
			continue
		var opts: Array = p.get("options", ["none"])
		var colors: Array = pal.get(str(p.get("palette", "")), ["#808080"])
		var entry := {"option": str(opts[rng.randi_range(0, opts.size() - 1)])}
		for slot: String in p.get("colors", []):
			entry[slot] = str(colors[rng.randi_range(0, colors.size() - 1)])
		out["parts"][pid] = entry
	# Faces and bodies share a skin tone.
	if out["parts"].has("face") and out["parts"].has("body") and not locks.has("body"):
		out["parts"]["body"]["primary"] = out["parts"]["face"].get("primary", "#c68d66")
	return out


## A portrait with every part filled in: the given parts kept, the rest picked by `rng`.
static func complete(spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var base := normalize(spec)
	var full := PortraitSpec.randomize(rng, base, _all_locked(base))
	full["seed"] = base.get("seed", 0)
	return full


static func _all_locked(spec: Dictionary) -> Dictionary:
	var locks := {}
	for pid: String in spec.get("parts", {}):
		locks[pid] = true
	return locks


## The complete portrait for an NPC record (its own, or one made from its look).
static func for_npc(npc: Dictionary) -> Dictionary:
	if npc.get("portrait") is Dictionary and not (npc["portrait"] as Dictionary).is_empty():
		return npc["portrait"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([str(npc.get("id", "")), "portrait"])
	return complete(npc.get("look", {}), rng)


## The complete portrait for a pilot (pilot["portrait"], else one made from their id).
static func for_pilot(p: Dictionary) -> Dictionary:
	if p.get("portrait") is Dictionary and int((p["portrait"] as Dictionary).get("version", 1)) >= 2:
		return p["portrait"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([str(p.get("id", p.get("name", ""))), "portrait"])
	return complete(Portrait.look_for_pilot(p), rng)


## Who's talking, for any UI: {"portrait": v2 spec, "expression": id}, or {} for the narrator.
static func of_speaker(story: StoryState, campaign: Campaign, ctx: Dictionary, speaker: String, expression: String = "neutral") -> Dictionary:
	match speaker:
		"npc":
			var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
			return {} if npc.is_empty() else {"portrait": for_npc(npc), "expression": expression}
		"pilot":
			var p: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {}) if campaign != null else {}
			return {} if p.is_empty() else {"portrait": for_pilot(p), "expression": expression}
	return {}


## Any look (v2 portrait or an older flat look) as a v2 portrait.
static func normalize(look: Dictionary) -> Dictionary:
	if int(look.get("version", 1)) >= 2 and look.has("parts"):
		return look
	var p := {}
	var skin := str(look.get("skin", "#c68d66"))
	p["face"] = {"option": "oval", "primary": skin}
	p["body"] = {"option": "average", "primary": skin}
	p["hair"] = {"option": str(look.get("hair_style", "short")), "primary": str(look.get("hair", "#3a2518")), "secondary": str(look.get("hair", "#3a2518"))}
	p["eyes"] = {"option": "round", "primary": str(look.get("eyes", "#3b2a1a"))}
	p["outer_outfit"] = {"option": "jacket", "primary": str(look.get("outfit", "#4a5a6a")), "secondary": str(look.get("accent", "#3a8ac8"))}
	var extra := str(look.get("extra", "none"))
	p["glasses"] = {"option": extra if extra in ["glasses", "visor", "eyepatch"] else "none", "primary": str(look.get("accent", "#3a8ac8"))}
	p["hats"] = {"option": extra if extra in ["cap", "headset"] else "none", "primary": str(look.get("accent", "#3a8ac8"))}
	p["scarves"] = {"option": "scarf" if extra == "scarf" else "none", "primary": str(look.get("accent", "#3a8ac8"))}
	p["beard"] = {"option": "full" if extra == "beard" else "none", "primary": str(look.get("hair", "#3a2518"))}
	return {"version": 2, "parts": p, "seed": look.get("seed", 0)}


## A v2 portrait as the flat look the placeholder Portrait and PilotFigure draw.
static func flatten(spec: Dictionary) -> Dictionary:
	if int(spec.get("version", 1)) < 2:
		return spec
	var parts_: Dictionary = spec.get("parts", {})
	var out := {}
	var map: Dictionary = data().get("placeholder", {})
	for k: String in map:
		if k.begins_with("_"):
			continue
		var path: Array = map[k]
		var part: Dictionary = parts_.get(str(path[0]), {})
		if part.has(str(path[1])):
			out[k] = part[str(path[1])]
	var extra := "none"
	for pid in ["glasses", "hats", "scarves"]:
		var opt := str(parts_.get(pid, {}).get("option", "none"))
		if opt in ["glasses", "visor", "eyepatch", "cap", "headset", "scarf"]:
			extra = opt
	if str(parts_.get("beard", {}).get("option", "none")) not in ["none", "stubble"]:
		extra = "beard"
	out["extra"] = extra
	return out


# --- Expressions in dialogue -------------------------------------------------------------

## The NPC's face when a scene line doesn't say: standing first, then personality.
static func npc_expression(story: StoryState, npc: Dictionary) -> String:
	var auto: Dictionary = data().get("auto", {})
	if int(npc.get("temper", 0)) >= int(Tones.data().get("warn_at", 7)):
		return "angry"
	var st := story.get_standing(str(npc.get("faction", "")))
	if st <= -1:
		return str(auto.get("standing", {}).get("hostile", "angry"))
	if st >= 2:
		return str(auto.get("standing", {}).get("friendly", "smiling"))
	return str(auto.get("personality", {}).get(str(npc.get("personality", "")), "neutral"))


## The pilot's face after picking a reply with these tags.
static func pilot_expression(tags: Array) -> String:
	var map: Dictionary = data().get("auto", {}).get("pilot_tags", {})
	for t: Variant in tags:
		if map.has(str(t)):
			return str(map[str(t)])
	return "neutral"


static func check_expression(outcome: String) -> String:
	return str(data().get("auto", {}).get("check", {}).get(outcome, "neutral"))
