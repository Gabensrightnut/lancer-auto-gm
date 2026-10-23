class_name Unit
extends RefCounted
## A character or object on the battlefield: player mech, pilot on foot, NPC, deployable.
## Plain data only. Rules live in src/core/rules/, visuals in src/render/.

const KIND_MECH := "mech"
const KIND_PILOT := "pilot"
const KIND_NPC := "npc"
const KIND_DEPLOYABLE := "deployable"

var id: String = ""
var name: String = ""
var kind: String = KIND_MECH
## Team id, e.g. "players", "enemies". Allies share a side.
var side: String = "players"
## Seat that controls this unit: a player seat id, or "gm".
var controller: String = "gm"
## Content id from lancer-data (frame id for mechs, NPC class id for NPCs).
var content_id: String = ""

var size: float = 1.0
## Anchor cell of the footprint (see GridLayout.footprint).
var cell: Vector2i = Vector2i.ZERO
## Height level of the unit's base. Above the ground under it means flying or falling.
var level: int = 0
var flying: bool = false

var hp: int = 0
var max_hp: int = 0
var overshield: int = 0
var armor: int = 0
var heat: int = 0
var heat_cap: int = 0
var structure: int = 4
var max_structure: int = 4
var stress: int = 4
var max_stress: int = 4
var evasion: int = 8
var edef: int = 8
var speed: int = 4
var sensors: int = 10
var save_target: int = 10
var tech_attack: int = 0
var grit: int = 0
var repairs: int = 0
## Mech skills (HASE), added to checks and saves.
var hull: int = 0
var agility: int = 0
var systems: int = 0
var engineering: int = 0
## Damage types this unit resists ("Kinetic", "Energy", "Explosive", "Burn", "Heat" or "All").
var resistances: Array = []
## "" (walks), "flight" or "hover" (glossary: Flight/Hover).
var flight: String = ""
var burn: int = 0
## Times overcharged since the last Full Repair (actions: Overcharge).
var overcharge_count: int = 0
var destroyed: bool = false

## Status name (as in lancer-data statuses.json) -> extra data (source, duration...).
var statuses: Dictionary = {}

## Equipped gear, as built by UnitFactory. Mechs: {"frame": id, "mounts": [{"mount": "Main",
## "weapons": ["mw_assault_rifle"], "mod": ""}], "weapons": [weapon profiles, see Weapons],
## "systems": [{"key", "id", "name", "tags"}]}. NPCs: {"weapons": [...], "systems": []}.
var loadout: Dictionary = {}

## Rules-engine bookkeeping for the current turn (actions taken, movement spent). Reset at
## the start of each of this unit's turns. See src/core/rules/turn_rules.gd.
var turn: Dictionary = {}
## Rules-engine bookkeeping that lasts longer than a turn (weapon loading and uses, reactions
## this round, falling, reactor meltdown countdown...).
var counters: Dictionary = {}


func has_status(status: String) -> bool:
	return statuses.has(status)


## Unmounted characters (Core p.74 Fighting on the Ground): pilots out of their mechs, and
## soldiers (Soldiers: NPC squads and single humans, loadout["on_foot"]). They add Grit to
## attacks and saves, are Biological, attack with Fight and don't Engage or block mechs.
func on_foot() -> bool:
	return kind == KIND_PILOT or bool(loadout.get("on_foot", false))


## Biological (Core p.282 NPC types, p.74 unmounted characters): no Heat Cap, immune to tech
## actions other than Scan and Lock On, and (NPCs) can't take tech actions.
func biological() -> bool:
	return on_foot() or bool(loadout.get("biological", false))


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "kind": kind, "side": side, "controller": controller,
		"content_id": content_id, "size": size, "cell": [cell.x, cell.y], "level": level,
		"flying": flying, "hp": hp, "max_hp": max_hp, "overshield": overshield,
		"armor": armor, "heat": heat, "heat_cap": heat_cap, "structure": structure,
		"max_structure": max_structure, "stress": stress, "max_stress": max_stress,
		"evasion": evasion, "edef": edef, "speed": speed, "sensors": sensors,
		"save_target": save_target, "tech_attack": tech_attack, "grit": grit,
		"repairs": repairs, "hull": hull, "agility": agility, "systems": systems,
		"engineering": engineering, "resistances": resistances.duplicate(), "flight": flight,
		"burn": burn, "overcharge_count": overcharge_count, "destroyed": destroyed,
		"statuses": statuses.duplicate(true), "loadout": loadout.duplicate(true),
		"turn": turn.duplicate(true), "counters": counters.duplicate(true),
	}.merged(_soldier_fields())


## Soldiers' kind and, for squads, how many of the squad's people are still standing (for
## the look only: ceil(hp / max_hp * squad size); no rules effect).
func _soldier_fields() -> Dictionary:
	if counters.has("idol_of"):
		# H0R_OS II False Idol, for its own side's view: what it copies, and whether any
		# hostile side has seen through it (ViewFilter.disguise shows the others a copy).
		return {"illusion_of": String(counters["idol_of"]), "revealed": not (counters.get("idol_seen_through", []) as Array).is_empty()}
	if not loadout.has("soldier"):
		return {}
	var out := {"soldier": String(loadout["soldier"])}
	var men := int(loadout.get("squad_men", 0))  # a set member count (older saves, tests)
	for e: Dictionary in loadout.get("effects", []):
		if e.get("kind", "") == "squad_members":
			men = int(e.get("members", 10))
	if men > 0:
		out["men_left"] = 0 if hp <= 0 or destroyed else ceili(float(hp) / maxf(1.0, max_hp) * men)
	return out


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	for key: String in d:
		match key:
			"cell":
				u.cell = Vector2i(int(d[key][0]), int(d[key][1]))
			"statuses", "loadout", "turn", "counters":
				u.set(key, (d[key] as Dictionary).duplicate(true))
			"resistances":
				u.resistances = (d[key] as Array).duplicate()
			_:
				if key in u:
					u.set(key, _coerce(u.get(key), d[key]))
	return u


## JSON turns every number into a float; match the type of the property being set.
static func _coerce(current: Variant, value: Variant) -> Variant:
	match typeof(current):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
	return value
