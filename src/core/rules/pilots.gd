class_name Pilots
extends RefCounted
## Pilots on foot, mounting and dismounting, and reactor explosions.
##
## A mech's pilot is its own Unit (kind "pilot"). While mounted it has
## counters["mounted_in"] = mech id and isn't on the field (no turns, can't be targeted);
## the mech has counters["pilot"] = pilot id. A mech whose pilot has left has
## counters["empty"] = true and takes no turns.
##
## Book rules used: base pilot stats (rules.json base_pilot_*), Down and Out (statuses),
## Mount, Dismount, Eject, Self Destruct (actions), Size 1/2.
## PROVISIONAL (docs/RULES_TODO.md "Pilots"): pilots have no heat cap (heat becomes energy
## damage, per glossary: Heat Capacity); a destroyed mech's pilot stays inside but takes
## turns and may Dismount; the self-destruct/meltdown explosion's Agility save is against
## the exploding mech's Save Target and "half damage" rounds up.

## rules.json base pilot numbers (copied so the core needs no ContentDB).
const BASE := {"hp": 6, "evasion": 10, "edef": 10, "speed": 4, "sensors": 5, "save_target": 10}
const REF_EXPLOSION := "actions: Self Destruct (Burst 2, 4d6 explosive, Agility save for half)"


static func make_pilot(id: String, name: String, side: String, controller: String, grit: int = 0, base: Dictionary = BASE) -> Unit:
	var p := Unit.new()
	p.id = id
	p.name = name
	p.kind = Unit.KIND_PILOT
	p.side = side
	p.controller = controller
	p.size = 0.5
	p.max_hp = int(base.get("hp", 6)) + grit
	p.hp = p.max_hp
	p.evasion = int(base.get("evasion", 10))
	p.edef = int(base.get("edef", 10))
	p.speed = int(base.get("speed", 4))
	p.sensors = int(base.get("sensors", 5))
	p.save_target = int(base.get("save_target", 10)) + grit
	p.grit = grit
	p.heat_cap = 0
	p.max_structure = 0
	p.structure = 0
	p.max_stress = 0
	p.stress = 0
	p.loadout = {"weapons": [], "systems": []}
	return p


## Puts `pilot` inside `mech` (used by mission setup and the Mount action).
static func seat(state: GameState, pilot: Unit, mech: Unit) -> void:
	pilot.counters["mounted_in"] = mech.id
	pilot.cell = mech.cell
	pilot.level = mech.level
	mech.counters["pilot"] = pilot.id
	mech.counters.erase("empty")
	if not state.units.has(pilot.id):
		state.add_unit(pilot)


static func pilot_of(state: GameState, mech: Unit) -> Unit:
	return state.unit(String(mech.counters.get("pilot", "")))


## The pilot of `mech`, created if the mission didn't set one up.
static func ensure_pilot(state: GameState, mech: Unit) -> Unit:
	var p := pilot_of(state, mech)
	if p == null:
		p = make_pilot(mech.id + "_pilot", "Pilot of " + (mech.name if mech.name != "" else mech.id), mech.side, mech.controller, mech.grit)
		seat(state, p, mech)
	return p


## Takes the pilot out of its mech and puts it at `cell`.
static func unseat(state: GameState, pilot: Unit, mech: Unit, cell: Vector2i, level: int) -> Array[Dictionary]:
	pilot.counters.erase("mounted_in")
	pilot.cell = cell
	pilot.level = level
	mech.counters["empty"] = true
	var events: Array[Dictionary] = [{"type": "pilot_left_mech", "unit": pilot.id, "mech": mech.id, "cell": [cell.x, cell.y, level]}]
	events.append_array(Combat.after_movement(state))
	return events


## A free space a Size 1/2 character could stand in next to `mech`, or null.
static func free_adjacent(state: GameState, mech: Unit, prefer: Variant = null) -> Variant:
	var me := Sight.body_of(state, mech)
	var options: Array[Vector2i] = []
	for c in me.cells:
		for n in state.map.grid.neighbors(c):
			if not me.cells.has(n) and not options.has(n):
				options.append(n)
	if prefer is Vector2i:
		var only: Array[Vector2i] = []
		if options.has(prefer):
			only.append(prefer)
		options = only
	for c in options:
		var lv := state.map.ground_height(c)
		if _free_for_pilot(state, c, lv):
			return [c, lv]
	return null


static func _free_for_pilot(state: GameState, c: Vector2i, lv: int) -> bool:
	var place := Movement.placement(state, 0.5, c, lv)
	if not place["ok"] or not place["standing"]:
		return false
	var body := Sight.make_body(state, c, lv, 0.5)
	for o: Unit in state.units.values():
		if Combat.is_present(o) and Movement._overlaps(body, Sight.body_of(state, o)):
			return false
	return true


## A reactor explosion (Self Destruct, reactor meltdown): BURST 2, 4d6 explosive damage,
## Agility save for half; destroys the mech and kills anyone inside.
static func explode(state: GameState, mech: Unit, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var roll := state.dice.roll("4d6")
	var me := Sight.body_of(state, mech)
	var hit: Array = []
	for u: Unit in state.units.values():
		if u != mech and Combat.is_present(u) and Sight.distance(state, me, Sight.body_of(state, u)) <= 2:
			hit.append(u)
	events.append({"type": "reactor_explosion", "unit": mech.id, "reason": why, "roll": roll,
		"targets": hit.map(func(x: Unit) -> String: return x.id), "rule_ref": REF_EXPLOSION})
	for u: Unit in hit:
		var save := Combat.skill_check(state, u, "agility", "Agility save vs reactor explosion", mech.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": REF_EXPLOSION})
		var amount := int(roll["total"])
		if save["success"]:
			amount -= amount / 2
		events.append_array(Combat.deal_damage(state, u, [{"type": "Explosive", "amount": amount}], {"source": mech.id}))
	var pilot := pilot_of(state, mech)
	if pilot != null and pilot.counters.get("mounted_in", "") == mech.id:
		pilot.destroyed = true
		events.append({"type": "unit_destroyed", "unit": pilot.id, "reason": "Inside the mech when its reactor exploded."})
	events.append_array(Combat.destroy(state, mech, why))
	return events


## Pilots at 0 HP are DOWN AND OUT (unconscious and Stunned); more damage kills them
## (statuses: Down and Out).
static func pilot_hit_zero(state: GameState, p: Unit, source: String) -> Array[Dictionary]:
	if p.has_status("Down and Out"):
		return Combat.destroy(state, p, "Took damage while Down and Out.")
	p.hp = 0
	var events := Combat.add_status(state, p, "Down and Out", source)
	events.append_array(Combat.add_status(state, p, "Stunned", "Down and Out"))
	return events
