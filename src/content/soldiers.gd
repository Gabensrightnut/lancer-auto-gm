class_name Soldiers
extends RefCounted
## Soldiers on mech-scale maps, on the book's special classes (Core p.322-323): the Squad (a
## group of soldiers as one Size 4 character, 1/2 individually) and the Human (one person,
## Size 1/2). Both are Biological NPCs: no Heat Cap, immune to tech actions other than Scan and
## Lock On, and they can't take tech actions (Core p.282 Types of NPCs). Humans are unmounted
## people (Core p.74: they don't Engage or block mechs, and attack with Fight); Squads follow
## their own traits instead (Spread Out, Undersize, Strength in Numbers...), see the effect
## kinds in npc_feature_effects.json.
##
## Builds: data/game/soldiers.json. Numbers: the official local pack when it's there
## (local/content/core_npcs.json, docs/NPC_PACK.md), else our placeholders.
##
## Nobody gives soldiers orders: every soldier, on either side, belongs to its side's soldier
## seat, which only the AI plays (NetHost.is_ai_seat). On the players' side the players still
## choose when an allied soldier takes its turn, as with any allied NPC (Core p.60); what it
## does on that turn is its own AI's choice, explained in the combat log.

const DATA := "res://data/game/soldiers.json"
const SEAT_PREFIX := "soldiers_"
const REF_SQUAD := "Core p.322 Squad"
const REF_HUMAN := "Core p.322 Human"

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
	return u != null and Effects.has(u, "squad_members")


## Spread Out (Core p.322): its members move freely within its spaces.
static func spreads(u: Unit) -> bool:
	return u != null and Effects.has(u, "spread_out")


## The side's soldier seat (made if missing). Only the AI plays it.
static func seat_for(state: GameState, side: String) -> String:
	var seat := SEAT_PREFIX + side
	if not state.seats.has(seat):
		state.seats[seat] = {"name": "Soldiers", "side": side, "ai_only": true}
	return seat


static func is_soldier_seat(state: GameState, seat: String) -> bool:
	return bool(state.seats.get(seat, {}).get("ai_only", false))


## Builds a soldier of `kind_id` (soldiers.json) at tier 1-3, controlled by its side's
## soldier seat when `state` is given.
static func build(db: ContentDB, id: String, kind_id: String, side: String, tier: int = 1, state: GameState = null) -> Unit:
	var k: Dictionary = kinds().get(kind_id, {})
	if k.is_empty():
		return null
	var controller := seat_for(state, side) if state != null else SEAT_PREFIX + side
	var u := NPCBuilder.build(db, id, String(k.get("class", "npcc_squad")), tier,
		{"name": k.get("name", kind_id), "optional": k.get("optional", []), "side": side, "controller": controller})
	if u == null:
		return null
	# The damage type the book leaves to when the squad is made.
	var picks: Dictionary = k.get("damage_type", {})
	for w: Dictionary in u.loadout.get("weapons", []):
		if picks.has(String(w.get("id", ""))):
			for d: Dictionary in w.get("damage", []):
				d["type"] = String(picks[w["id"]])
	u.loadout["soldier"] = kind_id
	u.loadout["ai_role"] = String(k.get("role", "striker"))
	u.loadout["job"] = String(k.get("job", ""))
	u.loadout["form"] = "squad" if is_squad(u) else "human"
	if not is_squad(u):
		u.loadout["on_foot"] = true  # a person out of a mech (Core p.74)
	return u


## How many of a squad's members are still standing (Core p.322 Soldiers: 10 members by
## default): for the look; the attacks it makes follow its weapons (see multi_attacks).
static func men_left(u: Unit) -> int:
	return int(u._soldier_fields().get("men_left", 0))


## Main Rifle: two attacks at a time; one once the Squad has lost more than half its HP,
## unless it's Disciplined (Core p.322).
static func attacks_with(u: Unit, w: Dictionary) -> int:
	var n := int(w.get("multi_attack", 1))
	if n > 1 and not Effects.has(u, "disciplined") and u.hp * 2 < u.max_hp:
		return 1
	return maxi(1, n)


## Spread Out (Core p.322): can the squad end its move with its footprint at `anchor`? It
## may overlap obstructions, cover and characters as long as at least 2 of its spaces are
## free (open ground it can stand on, nobody else in it).
static func spread_ok(state: GameState, u: Unit, anchor: Vector2i, level: int, size: float) -> bool:
	var free := 0
	var body := Sight.make_body(state, anchor, level, size)
	for c in body.cells:
		var col := state.map.column(c)
		if col == null or Sight.is_solid(state.map, c, level) or not (level == 0 or Sight.is_solid(state.map, c, level - 1)):
			continue
		var taken := false
		for o: Unit in state.units.values():
			if o != u and Combat.is_present(o) and state.map.grid.footprint(o.cell, o.size).has(c):
				taken = true
				break
		if not taken:
			free += 1
	return free >= 2
