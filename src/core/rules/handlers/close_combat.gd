class_name CloseCombat
extends RefCounted
## Ram, Grapple (and ending it), Jump.
##
## Book rules used: actions Ram, Grapple, Ram/Grapple (NPC: +1/2/3 by tier), Jumping and
## Climbing (glossary).
## Same-Size grapples immobilize nobody until someone wins the start-of-turn contest
## (GrappleContest). PROVISIONAL (docs/RULES_TODO.md "Jump"): a grappled smaller
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


## The Grapple attack, with a longer reach for grapple cables (Blackbeard: Range 5).
static func grapple_attack(u: Unit) -> Dictionary:
	var w := body_attack(u, "Grapple")
	var reach := Effects.value(u, "grapple_reach")
	if reach > 1:
		w["range"] = [{"type": "Threat", "val": reach}]
	return w


static func _hit(events: Array) -> bool:
	for e: Dictionary in events:
		if e["type"] == "attack_rolled":
			return e["result"] != "miss"
	return false


## Squads (Core p.322): Strength in Numbers makes them immune to Grapple and Ram; Spread Out
## means they can't Grapple or Ram either.
static func squad_refusal(u: Unit, t: Unit, what: String) -> RuleResult:
	if Effects.has(u, "spread_out"):
		return RuleResult.deny("A squad can't %s: its size doesn't reflect its mass." % what, Soldiers.REF_SQUAD)
	if t != null and Effects.has(t, "no_grapple_ram_target"):
		return RuleResult.deny("Squads are immune to %s." % what, Soldiers.REF_SQUAD)
	return RuleResult.allow()


static func _adjacent_target(state: GameState, u: Unit, params: Dictionary, ref: String) -> RuleResult:
	var t := state.unit(String(params.get("target", "")))
	if t == null or not Combat.is_present(t) or t == u:
		return RuleResult.deny("Choose an adjacent character.", ref)
	if Sight.unit_distance(state, u, t) > 1:
		return RuleResult.deny("The target must be adjacent.", ref)
	return RuleResult.allow()


## An adjacent character, with a Blademaster Die to spend.
static func _blademaster_target(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	if int(u.counters.get("blademaster", 0)) <= 0:
		return RuleResult.deny("No Blademaster Dice left.", "talents: Duelist")
	var t := state.unit(String(params.get("target", "")))
	if t == null or t == u or not Combat.is_present(t) or t.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, u, t) > 1:
		return RuleResult.deny("Choose an adjacent character.", "talents: Duelist")
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
		var sq := CloseCombat.squad_refusal(u, t, "Ram")
		if not sq.ok:
			return sq
		if t.size > GearSystems.grapple_size(u, t):
			return RuleResult.deny("You can only Ram characters your Size or smaller.", CloseCombat.REF_RAM)
		var p := Attacks.preview(state, u, CloseCombat.body_attack(u, "Ram"), t, {"improvised": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		var momentum: bool = u.counters.get("ram_momentum", false)
		var events := Attacks.attack(state, u, CloseCombat.body_attack(u, "Ram"), t, {"improvised": true})
		CoreBonuses.after_hit_ram_grapple(state, u, t, CloseCombat._hit(events))
		for e: Dictionary in Effects.of(u, "ram_damage"):
			if CloseCombat._hit(events) and Combat.is_present(t):
				# Siege Ram: 2 kinetic on a hit; 10 AP against objects.
				var obj := t.kind == Unit.KIND_DEPLOYABLE
				events.append_array(Combat.deal_damage(state, t, [{"type": "Kinetic", "amount": int(e.get("objects", 10) if obj else e.get("value", 2))}], {"source": u.id, "ap": obj}))
			break
		if CloseCombat._hit(events) and Combat.is_present(t):
			if Effects.has(t, "heavy_frame") and GearSystems.grapple_size(u, t) < t.size:
				events.append({"type": "no_effect", "target": t.id, "reason": "Heavy Frame: smaller characters can't knock it Prone or back.", "rule_ref": Effects.REF})
				return events
			events.append_array(Combat.add_status(state, t, "Prone", u.id))
			if params.get("knockback", false) or momentum:
				# Juggernaut Momentum: knocked back 2 more spaces.
				var extra := 1 if Effects.has(u, "titanomachy") and params.get("knockback", false) else 0  # Titanomachy Mesh
				var spaces := (1 if params.get("knockback", false) else 0) + (2 if momentum else 0) + extra
				var from := t.cell
				events.append_array(Attacks.knock_back(state, t, u.cell, spaces, u))
				events.append_array(TalentRules.kinetic_mass_transfer(state, u, t, u.cell, from, spaces))
		return events


class Feint:
	extends TurnAction
	## Duelist 2, Feint (free, 1 Blademaster Die): an adjacent character; until the start of your
	## next turn you ignore engagement with it and it can't react to your moves. params: {"target"}

	func type() -> String:
		return "feint"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		return CloseCombat._blademaster_target(state, u, params)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		u.counters["blademaster"] = int(u.counters["blademaster"]) - 1
		u.counters["feint"] = String(params["target"])
		var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Blademaster: Feint", "target": params["target"], "rule_ref": "talents: Duelist"}]
		events.append_array(Combat.refresh_engagement(state))
		return events


class Trip:
	extends TurnAction
	## Duelist 2, Trip (quick, 1 Blademaster Die): an adjacent character makes an Agility save or
	## falls Prone; either way you may pass through its space this turn. params: {"target"}

	func type() -> String:
		return "trip"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		return CloseCombat._blademaster_target(state, u, params)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		u.counters["blademaster"] = int(u.counters["blademaster"]) - 1
		u.turn["trip_through"] = t.id
		var save := Combat.skill_check(state, t, "agility", "Save vs Trip", u.save_target, 0, 0, GearSystems.prone_save_sources(t), true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "talents: Duelist"}]
		if not save["success"]:
			events.append_array(Combat.add_status(state, t, "Prone", u.id))
		return events


class DuelistStrike:
	extends TurnAction
	## Duelist 3: after a melee hit on your turn, spend a Blademaster Die to Grapple or Ram that
	## target as a free action. params: {"what": "grapple" | "ram", plus that action's params}

	func type() -> String:
		return "duelist_strike"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var id := String(u.turn.get("duelist_strike", ""))
		if id == "" or int(u.counters.get("blademaster", 0)) <= 0:
			return RuleResult.deny("Only right after a melee hit, with a Blademaster Die.", "talents: Duelist")
		var h: Variant = RulesEngine.registry.get(String(params.get("what", "")))
		if not String(params.get("what", "")) in ["grapple", "ram"] or h == null:
			return RuleResult.deny("Grapple or Ram (params.what).", "talents: Duelist")
		var p := params.duplicate()
		p["target"] = id
		return (h as TurnAction).check(state, u, p)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var p := params.duplicate()
		p["target"] = String(u.turn["duelist_strike"])
		u.turn.erase("duelist_strike")
		u.counters["blademaster"] = int(u.counters["blademaster"]) - 1
		TalentRules._use_round(state, u, "blademaster_strike")
		return (RulesEngine.registry[String(params["what"])] as TurnAction).apply(state, u, p)


class Grapple:
	extends TurnAction
	## Quick action: melee attack on an adjacent character; on a hit you're grappling.
	## params: {"target"}

	func type() -> String:
		return "grapple"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var cable := Effects.value(u, "grapple_reach")
		var r := CloseCombat._adjacent_target(state, u, params, CloseCombat.REF_GRAPPLE)
		if not r.ok and cable > 0:
			var t0 := state.unit(String(params.get("target", "")))
			r = RuleResult.allow() if t0 != null and t0 != u and Combat.is_present(t0) else r
		if not r.ok:
			return r
		if u.counters.has("grapple"):
			return RuleResult.deny("You're already in a grapple.", CloseCombat.REF_GRAPPLE)
		var t := state.unit(String(params["target"]))
		var sq := CloseCombat.squad_refusal(u, t, "Grapple")
		if not sq.ok:
			return sq
		if Effects.has(t, "immune_grapple"):
			return RuleResult.deny("It's immune to Grapple right now.", Effects.REF)
		var p := Attacks.preview(state, u, CloseCombat.grapple_attack(u), t, {"improvised": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		var events := Attacks.attack(state, u, CloseCombat.grapple_attack(u), t, {"improvised": true})
		CoreBonuses.after_hit_ram_grapple(state, u, t, CloseCombat._hit(events))
		if not CloseCombat._hit(events) or not Combat.is_present(t):
			return events
		if t.counters.has("grapple"):
			# Joining a grapple (actions: Grapple): add the Sizes on each side together.
			var g: Dictionary = t.counters["grapple"]
			u.counters["grapple"] = {"with": t.id, "attacker": true, "group": String(g.get("group", t.id)),
				"team": "b" if String(g.get("team", "a")) == "a" else "a"}
			events.append({"type": "grappled", "unit": u.id, "target": t.id, "joined": true, "rule_ref": CloseCombat.REF_GRAPPLE})
			events.append_array(CloseCombat.regroup(state, String(u.counters["grapple"]["group"])))
			events.append_array(Combat.refresh_engagement(state))
			return events
		if Sight.unit_distance(state, u, t) > 1:
			# Blackbeard Grapple Cable: pulled adjacent by the most direct path, or the grapple
			# breaks and it doesn't move.
			var path := Movement.pull_path(state, u, t)
			var end: Array = path.back()
			if Sight.distance(state, Sight.make_body(state, Vector2i(end[0], end[1]), int(end[2]), u.size), Sight.body_of(state, t)) > 1:
				events.append({"type": "grapple_ended", "unit": u.id, "other": t.id, "reason": "No space next to the target: the cable breaks.", "rule_ref": "frames: Blackbeard, Grapple Cable"})
				return events
			u.cell = Vector2i(end[0], end[1])
			u.level = int(end[2])
			events.append({"type": "moved", "unit": u.id, "path": path, "mode": "dragged", "cost": 0, "rule_ref": "frames: Blackbeard, Grapple Cable"})
			events.append_array(Abilities.check_mines(state, u, path))
			events.append_array(Zones.check_path(state, u, path))
			events.append_array(Combat.after_movement(state))
		var gid := u.id + ">" + t.id
		u.counters["grapple"] = {"with": t.id, "attacker": true, "group": gid, "team": "a"}
		t.counters["grapple"] = {"with": u.id, "attacker": false, "group": gid, "team": "b"}
		events.append({"type": "grappled", "unit": u.id, "target": t.id, "rule_ref": CloseCombat.REF_GRAPPLE})
		var us := GearSystems.grapple_size(u, t)
		var ts := GearSystems.grapple_size(t, u)
		var smaller: Unit = t if ts < us else (u if us < ts else null)
		if smaller != null:
			events.append_array(Combat.add_status(state, smaller, "Immobilized", "Grapple"))
		events.append_array(Combat.refresh_engagement(state))
		return events


## Everyone in grapple `gid`.
static func group_members(state: GameState, gid: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for x: Unit in state.units.values():
		if x.counters.has("grapple") and String(x.counters["grapple"].get("group", "")) == gid:
			out.append(x)
	return out


## A grapple with more than two characters: the Sizes on each side add together; the smaller
## side is Immobilized (actions: Grapple). Equal sides: nobody (a contest decides).
static func regroup(state: GameState, gid: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var members := group_members(state, gid)
	var totals := {"a": 0.0, "b": 0.0}
	for x in members:
		var foe := state.unit(String(x.counters["grapple"]["with"]))
		totals[String(x.counters["grapple"].get("team", "a"))] += GearSystems.grapple_size(x, foe) if foe != null else x.size
	var smaller := "a" if totals["a"] < totals["b"] else ("b" if totals["b"] < totals["a"] else "")
	for x in members:
		var held: bool = x.has_status("Immobilized") and x.statuses["Immobilized"].get("source", "") == "Grapple"
		var should := String(x.counters["grapple"].get("team", "a")) == smaller
		if should and not held:
			events.append_array(Combat.add_status(state, x, "Immobilized", "Grapple"))
		elif held and not should and members.size() > 2:
			events.append_array(Combat.remove_status(x, "Immobilized", "the grapple's sides changed"))
	return events


## Ends `u`'s part in a grapple. Two characters: the grapple ends. More: `u` lets go (or is
## let go) and the rest keep grappling if both sides still have someone.
static func end_grapple(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not u.counters.has("grapple"):
		return events
	var gid := String(u.counters["grapple"].get("group", ""))
	var other := state.unit(String(u.counters["grapple"]["with"]))
	var members := group_members(state, gid) if gid != "" else ([] as Array[Unit])
	var leaving: Array[Unit] = [u]
	if members.size() <= 2:
		leaving = [u, other]
	else:
		# Anyone tied only to `u` lets go too.
		for x in members:
			if x != u and String(x.counters["grapple"]["with"]) == u.id:
				var foe_left := false
				for y in members:
					if y != u and y != x and String(y.counters["grapple"].get("team", "")) != String(x.counters["grapple"].get("team", "")):
						foe_left = true
						x.counters["grapple"]["with"] = y.id
						break
				if not foe_left:
					leaving.append(x)
	for x: Unit in leaving:
		if x == null:
			continue
		x.counters.erase("grapple")
		if x.has_status("Immobilized") and x.statuses["Immobilized"].get("source", "") == "Grapple":
			events.append_array(Combat.remove_status(x, "Immobilized", why))
	events.append({"type": "grapple_ended", "unit": u.id, "other": other.id if other else "", "reason": why, "rule_ref": REF_GRAPPLE})
	var rest := group_members(state, gid) if gid != "" else ([] as Array[Unit])
	var teams := {}
	for x in rest:
		teams[String(x.counters["grapple"].get("team", ""))] = true
	if teams.size() < 2:
		for x in rest:
			x.counters.erase("grapple")
			if x.has_status("Immobilized") and x.statuses["Immobilized"].get("source", "") == "Grapple":
				events.append_array(Combat.remove_status(x, "Immobilized", why))
	elif not rest.is_empty():
		events.append_array(regroup(state, gid))
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


class GrappleContest:
	extends TurnAction
	## Same-Size grapples: at the start of your turn you can make a contested Hull check; the
	## winner counts as larger (the loser is Immobilized and dragged) until the next contest
	## (Core p.69). You started the contest, so you win ties (Core p.13).

	func type() -> String:
		return "grapple_contest"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.has("grapple"):
			return RuleResult.deny("You aren't in a grapple.", CloseCombat.REF_GRAPPLE)
		var other := state.unit(String(u.counters["grapple"]["with"]))
		if other == null or other.size != u.size:
			return RuleResult.deny("Only same-Size grapples are contested this way.", CloseCombat.REF_GRAPPLE)
		if u.turn.get("acted", false) or u.turn.get("moved", false) or u.turn.get("grapple_contest", false):
			return RuleResult.deny("Only at the start of your turn.", CloseCombat.REF_GRAPPLE)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		u.turn["grapple_contest"] = true
		var other := state.unit(String(u.counters["grapple"]["with"]))
		var mine := Combat.skill_check(state, u, "hull", "Grapple contest: Hull", 0)
		var theirs := Combat.skill_check(state, other, "hull", "Grapple contest: Hull", 0)
		var won: bool = int(mine["total"]) >= int(theirs["total"])
		var winner: Unit = u if won else other
		var loser: Unit = other if won else u
		var events: Array[Dictionary] = [{"type": "contested_check", "unit": u.id, "against": other.id, "check": mine, "contest": theirs, "success": won, "rule_ref": CloseCombat.REF_GRAPPLE}]
		if winner.has_status("Immobilized") and winner.statuses["Immobilized"].get("source", "") == "Grapple":
			events.append_array(Combat.remove_status(winner, "Immobilized", "won the grapple contest"))
		events.append_array(Combat.add_status(state, loser, "Immobilized", "Grapple"))
		return events


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
		if Effects.has(u, "jump_plus"):
			air = u.level + maxi(maxi(1, int(u.size)), ceili(u.speed / 2.0))  # Kai Bioplating: up to half Speed
		# Room to rise in your own column first.
		for c in grid.footprint(u.cell, u.size):
			for lv in range(u.level, air + GridLayout.spaces_per_side(u.size)):
				if Sight.is_solid(state.map, c, lv):
					out["reason"] = "No room to jump up here."
					return out
	else:
		var reach := u.speed if Effects.has(u, "jump_plus") else u.speed / 2  # Kai Bioplating: full Speed
		if dist < 1 or dist > reach:
			out["reason"] = "A horizontal jump goes up to %d spaces in a straight line." % reach
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
			match Rulings.choice(state, "slowed_jump"):
				"":
					return Rulings.needed("slowed_jump")
				"no":
					return RuleResult.deny("Slowed: your only movement is your standard move (table ruling: no jumping).", "Core p.78 Slowed")
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
