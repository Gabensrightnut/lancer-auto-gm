class_name Soldiers
extends RefCounted
## Soldiers on mech-scale maps: squads (several people sharing one HP pool in one space) and
## single humans. They are unmounted characters (Core p.74 Fighting on the Ground): Grit to
## attacks and saves, Biological, they attack with Fight using pilot weapons, and they don't
## Engage or block mechs (Unit.on_foot). Kinds and placeholder numbers: data/game/soldiers.json.
##
## Nobody gives soldiers orders: every soldier, on either side, belongs to its side's soldier
## seat, which only the AI plays (NetHost.is_ai_seat). On the players' side the players still
## choose when an allied soldier takes its turn, as with any allied NPC (Core p.60); what it
## does on that turn is its own AI's choice, explained in the combat log.

const DATA := "res://data/game/soldiers.json"
const SEAT_PREFIX := "soldiers_"
const REF := "Core p.74 Fighting on the Ground"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = d if d is Dictionary else {}
	return _data


static func kinds() -> Dictionary:
	return data().get("kinds", {})


static func is_soldier(u: Unit) -> bool:
	return u != null and u.loadout.has("soldier")


static func is_squad(u: Unit) -> bool:
	return is_soldier(u) and String(u.loadout.get("form", "")) == "squad"


## The side's soldier seat (made if missing). Only the AI plays it.
static func seat_for(state: GameState, side: String) -> String:
	var seat := SEAT_PREFIX + side
	if not state.seats.has(seat):
		state.seats[seat] = {"name": "Soldiers", "side": side, "ai_only": true}
	return seat


static func is_soldier_seat(state: GameState, seat: String) -> bool:
	return bool(state.seats.get(seat, {}).get("ai_only", false))


## Builds a soldier of `kind_id` (soldiers.json) at tier 1-3, controlled by its side's
## soldier seat when `state` is given. Weapons and gear come from the book's pilot gear.
static func build(db: ContentDB, id: String, kind_id: String, side: String, tier: int = 1, state: GameState = null) -> Unit:
	var k: Dictionary = kinds().get(kind_id, {})
	if k.is_empty():
		return null
	tier = clampi(tier, 1, 3)
	var sig := {}
	for w: String in k.get("weapons", []):
		if w.contains("signature"):
			sig[w] = String(k.get("damage_type", "Kinetic"))
	var controller := seat_for(state, side) if state != null else SEAT_PREFIX + side
	var u := UnitFactory.build_pilot(db, id, {"name": k.get("name", kind_id), "weapons": k.get("weapons", []), "gear": k.get("gear", []),
		"signature_damage": sig}, side, controller)
	u.kind = Unit.KIND_NPC
	u.content_id = kind_id
	u.size = float(k.get("size", 0.5))
	var grit: Variant = k.get("grit", 0)
	u.grit = int(grit[tier - 1]) if grit is Array else int(grit)
	u.max_hp = int(k.get("hp", 6))
	u.hp = u.max_hp
	for key in ["evasion", "edef", "speed", "sensors"]:
		u.set(key, int(k.get(key, u.get(key))))
	u.save_target = int(k.get("save_target", 10)) + u.grit
	u.heat_cap = 0  # Biological: heat becomes energy damage (Core p.74)
	u.max_structure = 0  # at 0 HP the soldiers are out of the fight
	u.structure = 0
	u.max_stress = 0
	u.stress = 0
	u.loadout["on_foot"] = true
	u.loadout["soldier"] = kind_id
	u.loadout["form"] = String(k.get("form", "human"))
	u.loadout["ai_role"] = String(k.get("role", "striker"))
	u.loadout["role"] = String(k.get("role", "striker")).capitalize()
	u.loadout["tier"] = tier
	u.loadout["placeholder"] = true
	u.loadout["job"] = String(k.get("job", ""))
	if u.loadout["form"] == "squad":
		u.loadout["squad_men"] = int(data().get("squad_men", 10))
	return u


## How many of a squad's people are still standing: for the look only, no rules effect.
static func men_left(u: Unit) -> int:
	return int(u._soldier_fields().get("men_left", 0))
