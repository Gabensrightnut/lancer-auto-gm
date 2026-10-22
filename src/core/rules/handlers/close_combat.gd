class_name CloseCombat
extends RefCounted
## Ram, Grapple (and ending it), Jump.
##
## Book rules used: actions Ram, Grapple, Ram/Grapple (NPC: +1/2/3 by tier), Jumping and
## Climbing (glossary).
## PROVISIONAL (docs/RULES_TODO.md "Grapple", "Jump"): same-Size grapples immobilize nobody
## until the contested Hull check at the start of a turn is automated (not yet); a grappled smaller
## character is dragged by the same step when the larger one moves, and the grapple ends if
## it can't follow; a horizontal jump must keep its height (it can cross pits and lower
## ground but not anything taller) and lands at the highest ground at or below that height;
## a vertical jump rises max(1, Size) levels; Slowed characters can't jump (it isn't their
## standard move); multi-character grapples aren't supported.

const REF_RAM := "actions: Ram"
const REF_GRAPPLE := "actions: Grapple"
const REF_JUMP := "glossary: Jumping and Climbing"


## The attack "weapon" for Ram/Grapple: Grit for mechs, +tier for NPCs.
static func body_attack(u: Unit, name: String) -> Dictionary:
	var w := {"key": name.to_lower(), "name": name, "type": "Melee", "size": "", "damage": [],
		"range": [{"type": "Threat", "val": 1}], "tags": []}
	if u.kind == Unit.KIND_NPC:
		w["attack_bonus"] = int(u.loadout.get("tier", 1))
	return w


static func _hit(events: Array) -> bool:
	for e: Dictionary in events:
		if e["type"] == "attack_rolled":
			return e["result"] != "miss"
	return false


static func _adjacent_target(state: GameState, u: Unit, params: Dictionary, ref: String) -> RuleResult:
	var t := state.unit(String(params.get("target", "")))
	if t == null or not Combat.is_present(t) or t == u:
		return RuleResult.deny("Choose an adjacent character.", ref)
	if Sight.unit_distance(state, u, t) > 1:
		return RuleResult.deny("The target must be adjacent.", ref)
	return RuleResult.allow()


class Ram:
	extends TurnAction
	## Quick action: melee attack on an adjacent character of your Size or smaller; on a hit
	## it's knocked Prone and, if you choose, back 1 space. params: {"target", "knockback"}

	func type() -> String:
		return "ram"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := CloseCombat._adjacent_target(state, u, params, CloseCombat.REF_RAM)
		if not r.ok:
			return r
		var t := state.unit(String(params["target"]))
		if t.size > u.size:
			return RuleResult.deny("You can only Ram characters your Size or smaller.", CloseCombat.REF_RAM)
		var p := Attacks.preview(state, u, CloseCombat.body_attack(u, "Ram"), t, {"improvised": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		var events := Attacks.attack(state, u, CloseCombat.body_attack(u, "Ram"), t, {"improvised": true})
		if CloseCombat._hit(events) and Combat.is_present(t):
			if Effects.has(t, "heavy_frame") and u.size < t.size:
				events.append({"type": "no_effect", "target": t.id, "reason": "Heavy Frame: smaller characters can't knock it Prone or back.", "rule_ref": Effects.REF})
				return events
			events.append_array(Combat.add_status(state, t, "Prone", u.id))
			if params.get("knockback", false):
				events.append_array(Attacks.knock_back(state, t, u.cell, 1, u))
		return events


class Grapple:
	extends TurnAction
	## Quick action: melee attack on an adjacent character; on a hit you're grappling.
	## params: {"target"}

	func type() -> String:
		return "grapple"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := CloseCombat._adjacent_target(state, u, params, CloseCombat.REF_GRAPPLE)
		if not r.ok:
			return r
		if u.counters.has("grapple"):
			return RuleResult.deny("You're already in a grapple.", CloseCombat.REF_GRAPPLE)
		var t := state.unit(String(params["target"]))
		var p := Attacks.preview(state, u, CloseCombat.body_attack(u, "Grapple"), t, {"improvised": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		var events := Attacks.attack(state, u, CloseCombat.body_attack(u, "Grapple"), t, {"improvised": true})
		if not CloseCombat._hit(events) or not Combat.is_present(t) or t.counters.has("grapple"):
			return events
		u.counters["grapple"] = {"with": t.id, "attacker": true}
		t.counters["grapple"] = {"with": u.id, "attacker": false}
		events.append({"type": "grappled", "unit": u.id, "target": t.id, "rule_ref": CloseCombat.REF_GRAPPLE})
		var smaller: Unit = t if t.size < u.size else (u if u.size < t.size else null)
		if smaller != null:
			events.append_array(Combat.add_status(state, smaller, "Immobilized", "Grapple"))
		events.append_array(Combat.refresh_engagement(state))
		return events


## Ends a grapple involving `u`.
static func end_grapple(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not u.counters.has("grapple"):
		return events
	var other := state.unit(String(u.counters["grapple"]["with"]))
	for x: Unit in [u, other]:
		if x == null:
			continue
		x.counters.erase("grapple")
		if x.has_status("Immobilized") and x.statuses["Immobilized"].get("source", "") == "Grapple":
			events.append_array(Combat.remove_status(x, "Immobilized", why))
	events.append({"type": "grapple_ended", "unit": u.id, "other": other.id if other else "", "reason": why, "rule_ref": REF_GRAPPLE})
	return events


## A grapple ends when either character breaks adjacency (actions: Grapple).
static func check_grapples(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if not u.counters.has("grapple"):
			continue
		var other := state.unit(String(u.counters["grapple"]["with"]))
		if other == null or not Combat.is_present(u) or not Combat.is_present(other) or Sight.unit_distance(state, u, other) > 1:
			events.append_array(end_grapple(state, u, "adjacency broken"))
	return events


## The smaller grappled character moves when the larger one does (same step).
static func drag_partner(state: GameState, u: Unit, from_cell: Vector2i, from_level: int) -> Array[Dictionary]:
	if not u.counters.has("grapple"):
		return [] as Array[Dictionary]
	var other := state.unit(String(u.counters["grapple"]["with"]))
	if other == null or not other.has_status("Immobilized") or other.statuses["Immobilized"].get("source", "") != "Grapple":
		return [] as Array[Dictionary]
	var to := other.cell + (u.cell - from_cell)
	var lv := other.level + (u.level - from_level)
	var place := Movement.placement(state, other.size, to, lv)
	var body := Sight.make_body(state, to, lv, other.size)
	var blocked: bool = not place["ok"]
	for o: Unit in state.units.values():
		if o != other and Combat.is_present(o) and Movement._overlaps(body, Sight.body_of(state, o)):
			blocked = true
	if blocked:
		return end_grapple(state, u, "couldn't follow")
	var path := [[other.cell.x, other.cell.y, other.level], [to.x, to.y, lv]]
	other.cell = to
	other.level = lv
	return [{"type": "moved", "unit": other.id, "path": path, "mode": "dragged", "cost": 0, "rule_ref": REF_GRAPPLE}] as Array[Dictionary]


class EndGrapple:
	extends TurnAction
	## Free action for the grappler: let go.

	func type() -> String:
		return "end_grapple"

	func cost() -> String:
		return TurnRules.FREE

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.get("grapple", {}).get("attacker", false):
			return RuleResult.deny("Only the grappler can end the grapple as a free action.", CloseCombat.REF_GRAPPLE)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		return CloseCombat.end_grapple(state, u, "let go")


class BreakFree:
	extends TurnAction
	## Quick action for the grappled: contested Hull check.

	func type() -> String:
		return "break_free"

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.has("grapple") or u.counters["grapple"].get("attacker", false):
			return RuleResult.deny("You aren't being grappled.", CloseCombat.REF_GRAPPLE)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var other := state.unit(String(u.counters["grapple"]["with"]))
		var mine := Combat.skill_check(state, u, "hull", "Break free: Hull", 0)
		var theirs := Combat.skill_check(state, other, "hull", "Hold on: Hull", 0)
		var free: bool = int(mine["total"]) >= int(theirs["total"])  # the one breaking free started the contest: ties win (Core p.13)
		var events: Array[Dictionary] = [{"type": "contested_check", "unit": u.id, "against": other.id, "check": mine, "contest": theirs, "success": free, "rule_ref": CloseCombat.REF_GRAPPLE}]
		if free:
			events.append_array(CloseCombat.end_grapple(state, u, "broke free"))
		return events


## Where a jump would land. Returns {ok, reason, path, land_level, air_level}.
static func plan_jump(state: GameState, u: Unit, dest: Vector2i, vertical: bool) -> Dictionary:
	var out := {"ok": false, "reason": "", "path": [], "land_level": u.level, "air_level": u.level}
	var grid := state.map.grid
	var dist := grid.distance(u.cell, dest)
	var others := Movement._others(state, u)
	var air := u.level
	if vertical:
		if dist != 1:
			out["reason"] = "A vertical jump goes 1 space over."
			return out
		air = u.level + maxi(1, int(u.size))
		# Room to rise in your own column first.
		for c in grid.footprint(u.cell, u.size):
			for lv in range(u.level, air + GridLayout.spaces_per_side(u.size)):
				if Sight.is_solid(state.map, c, lv):
					out["reason"] = "No room to jump up here."
					return out
	else:
		if dist < 1 or dist > u.speed / 2:
			out["reason"] = "A horizontal jump goes up to half your Speed (%d) in a straight line." % (u.speed / 2)
			return out
	var line := grid.line(u.cell, dest)
	var path: Array = [[u.cell.x, u.cell.y, u.level]]
	for i in range(1, line.size()):
		var c: Vector2i = line[i]
		var place := Movement.placement(state, u.size, c, air)
		if not place["ok"]:
			out["reason"] = "Something too tall is in the way: " + String(place["reason"])
			return out
		if Movement._blocked_by_unit(Sight.make_body(state, c, air, u.size), others, false):
			out["reason"] = "A character is in the way."
			return out
		path.append([c.x, c.y, air])
	var land := air
	while land > 0 and Movement.placement(state, u.size, dest, land - 1)["ok"] and Movement.placement(state, u.size, dest, land)["airborne"]:
		land -= 1
	if not Movement.placement(state, u.size, dest, land)["ok"]:
		out["reason"] = "Nowhere to land there."
		return out
	if Movement._blocked_by_unit(Sight.make_body(state, dest, land, u.size), others, true):
		out["reason"] = "That space is occupied."
		return out
	out["ok"] = true
	out["path"] = path
	out["air_level"] = air
	out["land_level"] = land
	return out


class Jump:
	extends TurnAction
	## Instead of the standard move: jump horizontally (half Speed, straight line, over pits
	## and gaps) or vertically (1 space over, up by your Size). Ending in mid-air means
	## falling at the end of the move. params: {"to": [x, y], "vertical": bool}

	func type() -> String:
		return "jump"

	func cost() -> String:
		return "move"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.has_status("Slowed") or u.has_status("Prone"):
			return RuleResult.deny("Slowed: your only movement is your standard move.", "statuses: Slowed")
		if u.turn.get("braced", false) or u.turn.get("prepared_lock", false):
			return RuleResult.deny("You can't move this turn.", TurnRules.REF_BRACE)
		if int(u.turn.get("move_spent", 0)) > 0 or u.turn.get("stood_up", false):
			return RuleResult.deny("Jumping replaces your standard move, and you've already moved.", CloseCombat.REF_JUMP)
		var to: Variant = TurnAction.cell_param(params, "to")
		if to == null:
			return RuleResult.deny("Say where to jump (params.to).", CloseCombat.REF_JUMP)
		var plan := CloseCombat.plan_jump(state, u, to, bool(params.get("vertical", false)))
		return RuleResult.allow() if plan["ok"] else RuleResult.deny(plan["reason"], CloseCombat.REF_JUMP)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var events := Reactions.overwatch(state, u)
		var to: Vector2i = TurnAction.cell_param(params, "to")
		var plan := CloseCombat.plan_jump(state, u, to, bool(params.get("vertical", false)))
		if not Combat.is_present(u) or not plan["ok"] or not MoveActions._can_move_voluntarily(u).ok:
			events.append({"type": "movement_cancelled", "unit": u.id, "reason": plan.get("reason", "Can't jump now."), "rule_ref": CloseCombat.REF_JUMP})
			return events
		var from := u.cell
		var from_level := u.level
		u.turn["move_spent"] = u.speed
		u.turn["moved"] = true
		u.cell = to
		u.level = int(plan["air_level"])
		events.append({"type": "moved", "unit": u.id, "path": plan["path"], "mode": "jump", "cost": u.speed, "rule_ref": CloseCombat.REF_JUMP})
		if int(plan["land_level"]) < u.level:
			# Characters that end a jump in mid-air fall at the end of the move.
			events.append_array(Combat.fall_unit(state, u))
		events.append_array(CloseCombat.drag_partner(state, u, from, from_level))
		events.append_array(Combat.after_movement(state))
		events.append_array(Reactions.prepared_triggers(state, u))
		return events
