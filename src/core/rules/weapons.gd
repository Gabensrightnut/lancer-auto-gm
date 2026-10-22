class_name Weapons
extends RefCounted
## Reading weapon profiles as UnitFactory copies them into Unit.loadout["weapons"]:
## {"key": "0:0", "id", "name", "mount": int, "size": "Main", "type": "Rifle",
##  "damage": [{"type", "val"}], "range": [{"type", "val"}], "tags": [{"id", "val"}],
##  "attack_bonus": int (NPC weapons only), "accuracy": int (NPC weapons only)}
## Per-battle weapon state (loaded, uses left, destroyed) lives in Unit.counters["weapons"].

const AREA_TYPES := ["Blast", "Burst", "Cone", "Line"]


static func find(u: Unit, key: String) -> Dictionary:
	for w: Dictionary in u.loadout.get("weapons", []):
		if String(w.get("key", "")) == key:
			return w
	return {}


static func has_tag(w: Dictionary, tag_id: String) -> bool:
	for t: Dictionary in w.get("tags", []):
		if t.get("id", "") == tag_id:
			return true
	return false


## The tag's value, 1 for tags with no value, 0 if the weapon doesn't have it.
static func tag_value(w: Dictionary, tag_id: String) -> int:
	for t: Dictionary in w.get("tags", []):
		if t.get("id", "") == tag_id:
			var v: Variant = t.get("val", 1)
			if v is int or v is float:
				return int(v)
			return int(v) if str(v).is_valid_int() else 1
	return 0


static func range_value(w: Dictionary, range_type: String) -> int:
	for r: Dictionary in w.get("range", []):
		if r.get("type", "") == range_type:
			return int(r.get("val", 0))
	return 0


static func is_melee(w: Dictionary) -> bool:
	return w.get("type", "") == "Melee"


## Overwatch/melee reach. All weapons have THREAT 1 unless specified (glossary: Threat).
static func threat(w: Dictionary) -> int:
	return maxi(1, maxi(range_value(w, "Threat"), tag_value(w, "tg_threat")))


## THREAT for this unit: some effects raise ranged weapons' THREAT (Tortuga core: at least 3)
## or melee THREAT (Tokugawa Limit Break and Radiance).
static func threat_for(u: Unit, w: Dictionary) -> int:
	var t := threat(w)
	if not is_melee(w):
		t = maxi(t, Effects.value(u, "min_threat"))
	else:
		t += reach_bonus(u, w, "threat")
	return t


## RANGE for this unit: the listed Range plus effects (Tokugawa Limit Break and Radiance).
static func range_for(u: Unit, w: Dictionary) -> int:
	var r := range_value(w, "Range")
	if r > 0 and not is_melee(w):
		r += reach_bonus(u, w, "range")
	return r


## Sum of reach_bonus effects that apply to this weapon ("range" or "threat").
## {kind: reach_bonus, range, threat, when?: exposed, damage_type?: only weapons dealing it}
static func reach_bonus(u: Unit, w: Dictionary, which: String) -> int:
	var total := 0
	for e: Dictionary in Effects.of(u, "reach_bonus"):
		if e.get("when", "") == "exposed" and not u.has_status("Exposed"):
			continue
		if e.has("damage_type") and not damage_types(u, w).has(e["damage_type"]):
			continue
		total += int(e.get(which, 0))
	return total


## Damage types this weapon deals for this unit, after swaps (Tokugawa Limit Break: kinetic
## and explosive become energy while Exposed).
static func damage_types(u: Unit, w: Dictionary) -> Array:
	var out: Array = []
	for d: Dictionary in w.get("damage", []):
		var t := swapped_type(u, String(d.get("type", "Kinetic")))
		if not out.has(t):
			out.append(t)
	return out


static func swapped_type(u: Unit, dtype: String) -> String:
	if u == null:
		return dtype
	for e: Dictionary in Effects.of(u, "damage_type_swap"):
		if e.get("when", "") == "exposed" and not u.has_status("Exposed"):
			continue
		if (e.get("from", []) as Array).has(dtype):
			return String(e.get("to", dtype))
	return dtype


## Weapons whose profile depends on a counter (ZF4 SOLIDCORE charges, Apocalypse Rail die)
## keep every profile in "profiles"; this switches the live one.
static func set_profile(w: Dictionary, index: int) -> void:
	var profiles: Array = w.get("profiles", [])
	if profiles.is_empty():
		return
	var p: Dictionary = profiles[clampi(index, 0, profiles.size() - 1)]
	w["profile"] = clampi(index, 0, profiles.size() - 1)
	w["profile_name"] = p.get("name", "")
	for k in ["damage", "range", "tags"]:
		w[k] = (p.get(k, []) as Array).duplicate(true)


## The area pattern ("Blast", "Burst", "Cone", "Line") or "" for single-target weapons.
static func area(w: Dictionary) -> String:
	for r: Dictionary in w.get("range", []):
		if AREA_TYPES.has(r.get("type", "")):
			return r["type"]
	return ""


## Per-battle state for a weapon, created on first use.
static func state_of(u: Unit, w: Dictionary) -> Dictionary:
	if not u.counters.has("weapons"):
		u.counters["weapons"] = {}
	var all: Dictionary = u.counters["weapons"]
	var key := String(w.get("key", ""))
	if not all.has(key):
		var uses := -1
		if has_tag(w, "tg_limited"):
			# +1 use of Limited gear per 2 Engineering (Core p.34).
			uses = tag_value(w, "tg_limited") + u.engineering / 2 + Effects.value(u, "limited_bonus")  # Integrated Ammo Feeds
		all[key] = {"loaded": true, "uses": uses, "destroyed": false}
		if has_tag(w, "tg_recharge"):
			all[key]["recharge"] = tag_value(w, "tg_recharge")
			all[key]["charged"] = true
	return all[key]
