class_name NPCBuilder
extends RefCounted
## NPCs from NPC data in the lancer-data / COMP/CON format: npc_classes, npc_features and
## npc_templates, from a loaded content pack (the official NPC pack or community packs), or
## from our own placeholder pack (data/game/npc_placeholder_pack.json, not official) when no
## pack provides NPCs. Field meanings follow the lancer-data repo:
##   class: {id, name, role, stats: {activations, hp, armor, evade, edef, heatcap, speed,
##           sensor, save, hull, agility, systems, engineering, size, structure?, stress?} each a
##           [tier 1, tier 2, tier 3] array (size: [[n], [n], [n]]), base_features,
##           optional_features}
##   feature: {id, name, type: Weapon|Tech|System|Trait|Reaction, weapon_type "Main Rifle",
##           damage [{type, damage: [t1, t2, t3]}], range, attack_bonus [..], accuracy [..],
##           tags, on_hit, effect, trigger, tech_type Quick|Full, bonus {stat: n}, override}
##   template: {id, name, base_features, optional_features} (Elite, Ultra...; their features'
##           "bonus" raise structure, stress, activations and other stats)
## What the engine does with a feature is in data/game/npc_feature_effects.json (by feature
## id); weapons, Recharge/Limited tags, tech attacks and stat bonuses work for any feature.

const PLACEHOLDER := "res://data/game/npc_placeholder_pack.json"
const EFFECTS := "res://data/game/npc_feature_effects.json"
const STAT_KEYS := {"hp": "hp", "armor": "armor", "evade": "evasion", "evasion": "evasion", "edef": "edef",
	"heatcap": "heat_cap", "heat_cap": "heat_cap", "speed": "speed", "sensor": "sensors", "sensors": "sensors",
	"save": "save_target", "save_target": "save_target", "hull": "hull", "agility": "agility", "systems": "systems",
	"engineering": "engineering", "structure": "structure", "stress": "stress", "activations": "activations",
	"size": "size", "tech_attack": "tech_attack"}

static var _placeholder: Dictionary = {}
static var _effects: Dictionary = {}


static func placeholder_pack() -> Dictionary:
	if _placeholder.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACEHOLDER))
		_placeholder = d if d is Dictionary else {}
	return _placeholder


static func feature_effects() -> Dictionary:
	if _effects.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS))
		_effects = d if d is Dictionary else {}
	return _effects


## The NPC data in use: our placeholders, with every class, feature and template a loaded pack
## has on top (same id: the pack's wins, e.g. the official Squad and Human from the local
## pack). Returns {"classes", "features", "templates": {id: entry}, "placeholder": bool (no pack
## has NPCs), "official": {class id: true} for classes a pack provides}.
static func source(db: ContentDB) -> Dictionary:
	var p := placeholder_pack()
	var out := {"classes": _index(p.get("npc_classes", [])), "features": _index(p.get("npc_features", [])),
		"templates": _index(p.get("npc_templates", [])), "placeholder": true, "official": {}}
	if db != null and db.count("npc_classes") > 0:
		var pc := _index(db.all("npc_classes"))
		out["classes"].merge(pc, true)
		out["features"].merge(_index(db.all("npc_features")), true)
		out["templates"].merge(_index(db.all("npc_templates")), true)
		out["placeholder"] = false
		for id: String in pc:
			out["official"][id] = true
	return out


static func _index(list: Array) -> Dictionary:
	var out := {}
	for e: Variant in list:
		if e is Dictionary and (e as Dictionary).has("id"):
			out[e["id"]] = e
	return out


static func _tiered(v: Variant, tier: int) -> Variant:
	if v is Array and not (v as Array).is_empty():
		return v[clampi(tier - 1, 0, (v as Array).size() - 1)]
	return v


## Builds an NPC. opts: {"name", "templates": [template ids], "optional": [feature ids],
## "side", "controller"}.
static func build(db: ContentDB, id: String, class_id: String, tier: int = 1, opts: Dictionary = {}) -> Unit:
	var src := source(db)
	var cls: Dictionary = src["classes"].get(class_id, {})
	if cls.is_empty():
		return null
	tier = clampi(tier, 1, 3)
	var u := Unit.new()
	u.id = id
	u.kind = Unit.KIND_NPC
	u.side = String(opts.get("side", "enemies"))
	u.controller = String(opts.get("controller", "gm"))
	u.name = String(opts.get("name", cls.get("name", id)))
	u.content_id = class_id
	var stats := {"structure": 1, "stress": 1, "activations": 1}
	for k: String in cls.get("stats", {}):
		if STAT_KEYS.has(k):
			var v: Variant = _tiered(cls["stats"][k], tier)
			if k == "size" and v is Array:
				v = (v as Array)[0] if not (v as Array).is_empty() else 1
			stats[STAT_KEYS[k]] = v
	var feature_ids: Array = (cls.get("base_features", []) as Array).duplicate()
	feature_ids.append_array(opts.get("optional", []))
	var template_names: Array = []
	for tid: Variant in opts.get("templates", []):
		var t: Dictionary = src["templates"].get(String(tid), {})
		if t.is_empty():
			continue
		template_names.append(t.get("name", tid))
		feature_ids.append_array(t.get("base_features", []))
	var features: Array = []
	for fid: Variant in feature_ids:
		var f: Dictionary = src["features"].get(String(fid), {})
		if f.is_empty():
			continue
		features.append(f)
		for k: String in f.get("bonus", {}):
			if STAT_KEYS.has(k):
				stats[STAT_KEYS[k]] = _num(stats.get(STAT_KEYS[k], 0)) + _num(_tiered(f["bonus"][k], tier))
		for k: String in f.get("override", {}):
			if STAT_KEYS.has(k):
				stats[STAT_KEYS[k]] = _tiered(f["override"][k], tier)
	u.size = float(_num(stats.get("size", 1)))
	u.max_hp = int(_num(stats.get("hp", 10)))
	u.hp = u.max_hp
	u.armor = int(_num(stats.get("armor", 0)))
	u.evasion = int(_num(stats.get("evasion", 8)))
	u.edef = int(_num(stats.get("edef", 8)))
	u.heat_cap = int(_num(stats.get("heat_cap", 0)))
	u.speed = int(_num(stats.get("speed", 4)))
	u.sensors = int(_num(stats.get("sensors", 10)))
	u.save_target = int(_num(stats.get("save_target", 10)))
	u.hull = int(_num(stats.get("hull", 0)))
	u.agility = int(_num(stats.get("agility", 0)))
	u.systems = int(_num(stats.get("systems", 0)))
	u.engineering = int(_num(stats.get("engineering", 0)))
	u.tech_attack = int(_num(stats.get("tech_attack", 0)))
	u.max_structure = int(_num(stats["structure"]))
	u.structure = u.max_structure
	u.max_stress = int(_num(stats["stress"]))
	u.stress = u.max_stress
	u.counters["activations"] = maxi(1, int(_num(stats["activations"])))
	var weapons: Array = []
	var effects: Array = []
	var traits: Array = []
	var abilities: Array = []
	var encoded := feature_effects()
	for i in range(features.size()):
		var f: Dictionary = features[i]
		var fkey := "f%d" % i
		var enc: Variant = encoded.get(String(f.get("id", "")))
		var text := _text(f.get("effect", ""))
		match String(f.get("type", "Trait")):
			"Weapon":
				weapons.append(_weapon(f, fkey, tier))
			"Tech":
				var act := "Full Tech" if String(f.get("tech_type", "Quick")) == "Full" else "Quick Tech"
				abilities.append({"key": fkey + "/a0", "name": f.get("name", ""), "source_key": fkey, "source_name": f.get("name", ""),
					"kind": "action", "activation": act, "frequency": "", "detail": text,
					"ops": [{"op": "npc_tech", "tech_attack": true, "attack_bonus": int(_num(_tiered(f.get("attack_bonus", 0), tier))),
						"accuracy": int(_num(_tiered(f.get("accuracy", 0), tier)))}] + ((enc as Array) if enc is Array else []),
					"automated": enc is Array, "tech_rolled": true, "tags": (f.get("tags", []) as Array).duplicate(true)})
			"System", "Reaction":
				var act := _activation(f)
				if act != "":
					abilities.append({"key": fkey + "/a0", "name": f.get("name", ""), "source_key": fkey, "source_name": f.get("name", ""),
						"kind": "action", "activation": act, "frequency": _frequency(f), "detail": text, "trigger": _text(f.get("trigger", "")),
						"ops": enc if enc is Array else [], "automated": enc is Array, "tags": (f.get("tags", []) as Array).duplicate(true)})
				else:
					traits.append({"name": f.get("name", ""), "text": text, "automated": enc is Array, "feature": f.get("id", "")})
			_:
				traits.append({"name": f.get("name", ""), "text": text, "automated": enc is Array or not f.get("bonus", {}).is_empty() and text == "", "feature": f.get("id", "")})
		if enc is Array and String(f.get("type", "")) in ["Trait", "System", "Reaction"] and _activation(f) == "":
			for e: Dictionary in enc:
				var copy := e.duplicate(true)
				copy["label"] = f.get("name", "")
				copy["rule_ref"] = "NPC feature: " + String(f.get("name", ""))
				effects.append(copy)
	u.loadout = {"weapons": weapons, "systems": [], "effects": effects, "traits": traits, "abilities": abilities, "tier": tier,
		"role": cls.get("role", ""), "class": class_id, "templates": template_names,
		"placeholder": not (src["official"] as Dictionary).has(class_id)}
	# NPC types (Core p.282): Biological NPCs have no Heat Cap, are immune to tech actions other
	# than Scan and Lock On, and can't take tech actions.
	var types: Array = cls.get("npc_type", [])
	if not types.is_empty():
		u.loadout["npc_type"] = types.duplicate()
	if types.has("Biological"):
		u.loadout["biological"] = true
		u.heat_cap = 0
	return u


static func _num(v: Variant) -> float:
	if v is int or v is float:
		return float(v)
	if v is String and (v as String).is_valid_float():
		return float(v)
	return 0.0


static func _text(v: Variant) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(str(v) if v != null else "", "", true)


static func _activation(f: Dictionary) -> String:
	if String(f.get("type", "")) == "Reaction":
		return "Reaction"
	for t: Dictionary in f.get("tags", []):
		match String(t.get("id", "")):
			"tg_quick_action":
				return "Quick"
			"tg_full_action":
				return "Full"
			"tg_protocol":
				return "Protocol"
			"tg_free_action":
				return "Free"
	return ""


static func _frequency(f: Dictionary) -> String:
	for t: Dictionary in f.get("tags", []):
		if t.get("id", "") == "tg_round":
			return "%s/round" % str(t.get("val", 1))
		if t.get("id", "") == "tg_turn":
			return "%s/turn" % str(t.get("val", 1))
	return ""


## An NPC weapon feature as an engine weapon: "Main Rifle" -> size Main, type Rifle; tiered
## damage, attack bonus and accuracy.
static func _weapon(f: Dictionary, key: String, tier: int) -> Dictionary:
	var wt := String(f.get("weapon_type", "Main Rifle")).split(" ", false)
	var size := String(wt[0]) if wt.size() > 1 else "Main"
	var wtype := String(wt[wt.size() - 1]) if not wt.is_empty() else "Rifle"
	var damage: Array = []
	for d: Dictionary in f.get("damage", []):
		var val: Variant = _tiered(d.get("damage", d.get("val", 0)), tier)
		damage.append({"type": String(d.get("type", "Kinetic")).capitalize(), "val": val})
	return {"key": key, "id": f.get("id", ""), "name": f.get("name", ""), "mount": -1, "size": size, "type": wtype,
		"damage": damage, "range": (f.get("range", []) as Array).duplicate(true), "tags": (f.get("tags", []) as Array).duplicate(true),
		"attack_bonus": int(_num(_tiered(f.get("attack_bonus", 0), tier))), "accuracy": int(_num(_tiered(f.get("accuracy", 0), tier))),
		"npc_on_hit": _text(f.get("on_hit", "")), "npc_effect": _text(f.get("effect", "")), "multi_attack": int(f.get("attacks", 1))}
