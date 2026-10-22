class_name Riders
extends RefCounted
## Characters carried by or tied to a mech:
##   MULE Harness: adjacent, non-Immobilized characters climb on as a quick action (combined
##     Size up to the mech's Size minus 1/2); riders share its space, move with it (even if
##     Slowed), have soft cover; if the mech or a rider is knocked Prone, Stunned, Immobilized
##     or destroyed, riders land Prone in adjacent spaces; riders climb down by moving away.
##   Expanded Compartment: one non-mech Size 1/2 passenger rides inside, untouchable, as if a
##     pilot; control can pass to them as a protocol (the mech is then Impaired and Slowed).
##   Cable Winch: a cable to an adjacent character (automatic if Stunned or willing, otherwise
##     a Hull save resists); neither can then move more than 5 spaces from the other; a hit
##     with a melee or Improvised Attack against Evasion 10 cuts it.

const REF_MULE := "systems: MULE Harness"
const REF_COMPARTMENT := "systems: Expanded Compartment"
const REF_WINCH := "systems: Cable Winch"


static func host_of(state: GameState, u: Unit) -> Unit:
	return state.unit(String(u.counters.get("riding", "")))


static func riders_of(state: GameState, host: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if String(o.counters.get("riding", "")) == host.id:
			out.append(o)
	return out


static func check_climb(state: GameState, u: Unit, host: Unit) -> RuleResult:
	if host == null or not Effects.has(host, "mule_harness") or not Combat.is_present(host) or host == u:
		return RuleResult.deny("Climb onto an adjacent mech with a MULE Harness.", REF_MULE)
	if Sight.unit_distance(state, u, host) > 1:
		return RuleResult.deny("It must be adjacent.", REF_MULE)
	if u.has_status("Immobilized"):
		return RuleResult.deny("Immobilized characters can't climb on.", REF_MULE)
	var load := u.size
	for r in riders_of(state, host):
		load += r.size
	if load > host.size - 0.5:
		return RuleResult.deny("Too heavy: riders can total at most Size %s." % str(host.size - 0.5), REF_MULE)
	return RuleResult.allow()


static func climb(state: GameState, u: Unit, host: Unit) -> Array[Dictionary]:
	u.counters["riding"] = host.id
	var from := [u.cell.x, u.cell.y, u.level]
	u.cell = host.cell
	u.level = host.level
	return [{"type": "climbed_on", "unit": u.id, "host": host.id, "rule_ref": REF_MULE},
		{"type": "moved", "unit": u.id, "path": [from, [u.cell.x, u.cell.y, u.level]], "mode": "climb", "cost": 0}] as Array[Dictionary]


## Riders land Prone in adjacent spaces (or the rider climbs down by moving: no Prone).
static func drop(state: GameState, rider: Unit, prone: bool, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var host := host_of(state, rider)
	rider.counters.erase("riding")
	if host == null:
		return events
	events.append({"type": "climbed_off", "unit": rider.id, "host": host.id, "reason": why, "rule_ref": REF_MULE})
	if prone:
		var spot: Variant = _free_next_to(state, host, rider)
		if spot != null:
			var from := [rider.cell.x, rider.cell.y, rider.level]
			rider.cell = spot[0]
			rider.level = spot[1]
			events.append({"type": "moved", "unit": rider.id, "path": [from, [rider.cell.x, rider.cell.y, rider.level]], "mode": "fall", "cost": 0})
		events.append_array(Combat.add_status(state, rider, "Prone", why))
	return events


static func _free_next_to(state: GameState, host: Unit, u: Unit) -> Variant:
	var others := Movement._others(state, u)
	for c in Sight.body_of(state, host).cells:
		for n: Vector2i in state.map.grid.neighbors(c):
			var lv := Movement.surface_levels(state, u.size, n)
			if lv.is_empty():
				continue
			var body := Sight.make_body(state, n, lv[0], u.size)
			if Movement._overlaps(body, Sight.body_of(state, host)) or Movement._blocked_by_unit(body, others, true):
				continue
			return [n, lv[0]]
	return null


## A status on the host or a rider that throws riders off.
static func on_status(state: GameState, u: Unit, status: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not status in ["Prone", "Stunned", "Immobilized"]:
		return events
	if u.counters.has("riding"):
		events.append_array(drop(state, u, status != "Prone", "rider " + status))
	for r in riders_of(state, u):
		events.append_array(drop(state, r, true, "mount " + status))
	return events


static func on_destroyed(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for r in riders_of(state, u):
		events.append_array(drop(state, r, true, "mount destroyed"))
	for p: Unit in state.units.values():
		if String(p.counters.get("passenger_in", "")) == u.id:
			p.counters.erase("passenger_in")  # the wreck can be left like a pilot leaves it
	return events


static func follow(state: GameState) -> void:
	for u: Unit in state.units.values():
		var host := host_of(state, u)
		if host != null:
			u.cell = host.cell
			u.level = host.level


# --- Expanded Compartment -------------------------------------------------------------

static func check_board(state: GameState, u: Unit, mech: Unit) -> RuleResult:
	if mech == null or not Effects.has(mech, "compartment") or not Combat.is_present(mech):
		return RuleResult.deny("Board an adjacent mech with an Expanded Compartment.", REF_COMPARTMENT)
	if u.kind == Unit.KIND_MECH or u.size > 0.5:
		return RuleResult.deny("Only a non-mech character of Size 1/2 fits.", REF_COMPARTMENT)
	if Sight.unit_distance(state, u, mech) > 1:
		return RuleResult.deny("It must be adjacent.", REF_COMPARTMENT)
	for o: Unit in state.units.values():
		if String(o.counters.get("passenger_in", "")) == mech.id:
			return RuleResult.deny("There's room for one passenger.", REF_COMPARTMENT)
	return RuleResult.allow()


static func passenger_of(state: GameState, mech: Unit) -> Unit:
	for o: Unit in state.units.values():
		if String(o.counters.get("passenger_in", "")) == mech.id:
			return o
	return null


## Transfer Control: the passenger takes (or gives back) the controls.
static func transfer(state: GameState, mech: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var p := passenger_of(state, mech)
	if mech.counters.has("passenger_control"):
		mech.controller = String(mech.counters["passenger_control"])
		mech.counters.erase("passenger_control")
		for st in ["Impaired", "Slowed"]:
			if mech.has_status(st) and mech.statuses[st].get("source", "") == "Expanded Compartment":
				events.append_array(Combat.remove_status(mech, st, "pilot back at the controls"))
		events.append({"type": "control_transferred", "unit": mech.id, "to": "pilot", "rule_ref": REF_COMPARTMENT})
		return events
	mech.counters["passenger_control"] = mech.controller
	mech.controller = p.controller
	events.append_array(Combat.add_status(state, mech, "Impaired", "Expanded Compartment"))
	events.append_array(Combat.add_status(state, mech, "Slowed", "Expanded Compartment"))
	events.append({"type": "control_transferred", "unit": mech.id, "to": p.id, "rule_ref": REF_COMPARTMENT})
	return events


# --- Cable Winch ----------------------------------------------------------------------

static func attach_cable(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not t.has_status("Stunned") and t.side != u.side:
		var save := Combat.skill_check(state, t, "hull", "Resist the cable", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": REF_WINCH})
		if save["success"]:
			return events
	for x: Unit in [u, t]:
		x.counters["cable"] = (t if x == u else u).id
	events.append({"type": "cable_attached", "unit": u.id, "target": t.id, "rule_ref": REF_WINCH})
	return events


static func cut(state: GameState, u: Unit) -> Array[Dictionary]:
	var other := state.unit(String(u.counters.get("cable", "")))
	u.counters.erase("cable")
	if other != null:
		other.counters.erase("cable")
	return [{"type": "cable_cut", "unit": u.id, "other": other.id if other else "", "rule_ref": REF_WINCH}] as Array[Dictionary]


## A planned move must end within 5 spaces of the other end of the cable.
static func tether_ok(state: GameState, u: Unit, dest: Vector2i, level: int) -> bool:
	var other := state.unit(String(u.counters.get("cable", "")))
	if other == null or not Combat.is_present(other):
		return true
	return Sight.distance(state, Sight.make_body(state, dest, level, u.size), Sight.body_of(state, other)) <= 5
