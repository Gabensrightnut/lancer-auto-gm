class_name Origin
extends RefCounted
## A pilot's origin (data/game/story/origins.json): homeworld, upbringing, former employer,
## specialty and up to five small perks. Stored as pilot["origin"] =
##   {homeworld, upbringing, employer, specialty, perks: [perk ids]}.
## By the book a background can be invoked for +1 Accuracy on a relevant skill check (Core
## p.20); the origin only widens what's relevant (NarrativeCheck.background_invoke reads
## tags()), so it never stacks a second bonus, and it never grants License Levels or gear.
## Perks with kind "combat" (e.g. weak_spots: +1 Accuracy against the former employer's frames)
## are data for the rules engine's "Origin perks" house rule (off by default).

const FILE := "res://data/game/story/origins.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func _entry(list: String, id: String) -> Dictionary:
	for e: Dictionary in data().get(list, []):
		if str(e["id"]) == id:
			return e
	return {}


## Why this origin can't be used ("" if it can).
static func refusal(origin: Dictionary) -> String:
	for k: String in ["homeworld", "upbringing", "employer", "specialty"]:
		if origin.has(k) and _entry(k, str(origin[k])).is_empty():
			return "Unknown %s." % k
	var perks: Array = origin.get("perks", [])
	if perks.size() > int(data().get("max_perks", 5)):
		return "At most %d perks." % int(data().get("max_perks", 5))
	for p: Variant in perks:
		var def := _entry("perks", str(p))
		if def.is_empty():
			return "Unknown perk %s." % p
		if bool(def.get("needs_employer", false)) and str(origin.get("employer", "none")) in ["", "none"]:
			return "%s needs a former employer." % def["name"]
	return ""


## Everything the origin makes relevant, for the background's +1 Accuracy (Core p.20).
static func tags(pilot: Dictionary) -> Array:
	var o: Dictionary = pilot.get("origin", {})
	var out: Array = []
	for k: String in ["homeworld", "upbringing", "employer", "specialty"]:
		for t: Variant in _entry(k, str(o.get(k, ""))).get("tags", []):
			if not out.has(t):
				out.append(t)
	for p: Variant in o.get("perks", []):
		var def := _entry("perks", str(p))
		if str(def.get("kind", "")) == "knowledge":
			for t: Variant in def.get("tags", []):
				if not out.has(t):
					out.append(t)
	return out


## What food sits well with them (the food-and-water house rule).
static func food_likes(pilot: Dictionary) -> Array:
	return _entry("homeworld", str(pilot.get("origin", {}).get("homeworld", ""))).get("food", [])


## Combat perks for the rules engine (only with its Origin perks house rule on):
## [{id, effect, manufacturer}].
static func combat_perks(pilot: Dictionary) -> Array:
	var o: Dictionary = pilot.get("origin", {})
	var out: Array = []
	for p: Variant in o.get("perks", []):
		var def := _entry("perks", str(p))
		if str(def.get("kind", "")) == "combat":
			out.append({"id": def["id"], "effect": def.get("effect", {}), "manufacturer": str(_entry("employer", str(o.get("employer", ""))).get("manufacturer", ""))})
	return out


static func describe(pilot: Dictionary) -> String:
	var o: Dictionary = pilot.get("origin", {})
	if o.is_empty():
		return ""
	var parts := PackedStringArray()
	for k: String in ["homeworld", "upbringing", "specialty"]:
		var e := _entry(k, str(o.get(k, "")))
		if not e.is_empty():
			parts.append(str(e["name"]))
	var emp := _entry("employer", str(o.get("employer", "")))
	if not emp.is_empty() and str(emp["id"]) != "none":
		parts.append("ex-%s" % emp["name"])
	return ", ".join(parts)
