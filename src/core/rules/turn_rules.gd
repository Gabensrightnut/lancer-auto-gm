class_name TurnRules
extends RefCounted
## Turn structure and the action economy (who acts next, what a unit may still do this turn).
##
## Each turn a character gets a standard move plus two quick actions or one full action, free
## actions, and can OVERCHARGE once for one more quick action (actions: Overcharge, Quick Tech).
## Quick actions can't be repeated in a turn except Quick Tech with a different option, or
## through Overcharge (actions: Overcharge, "even actions you have already taken this turn").
##
## Turn order (Core p.60): players act first; sides alternate (one hostile, one allied...)
## until everyone has acted; if one side has nobody left, the rest act in turn. The order
## keeps alternating across rounds: the side that didn't take the last turn starts the next
## round. Who picks within a side is the players' / GM's choice (start_turn).

const REF_TURN_ORDER := "Core p.60 Turns and Rounds"
const REF_ACTIONS := "actions: Overcharge / Quick Tech (2 quick or 1 full per turn)"
const REF_STUNNED := "statuses: Stunned"
const REF_BRACE := "actions: Brace"
const REF_OVERCHARGE := "actions: Overcharge"

## Action costs.
const QUICK := "quick"
const FULL := "full"
const FREE := "free"
const REACTION := "reaction"


## Units that take turns: not destroyed, not deployables.
static func takes_turns(u: Unit) -> bool:
	if u.kind == Unit.KIND_PILOT and not u.destroyed and u.counters.has("mounted_in"):
		return Combat.is_present(u)  # acts through its mech, unless the mech was destroyed
	if u.counters.has("passenger_in") and not u.destroyed:
		return true  # a passenger still takes its turns (to climb out)
	if u.counters.has("folded") and not u.destroyed:
		return true  # Fold Space: it comes back at the start of its next turn
	var st := state_of(u)
	if st != null and FrameSystems.riding(st, u):
		return false  # Goblin Symbiosis: acts during its host's turn instead
	return Combat.is_present(u) and u.kind != Unit.KIND_DEPLOYABLE and not u.counters.get("empty", false)


static func sides(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for u: Unit in state.units.values():
		if takes_turns(u) and not out.has(u.side):
			out.append(u.side)
	out.sort()
	if state.first_side != "" and out.has(state.first_side):
		out.erase(state.first_side)
		out.push_front(state.first_side)
	return out


static func waiting(state: GameState, side: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in state.units.values():
		if u.side == side and takes_turns(u) and not state.acted.has(u.id) and u.id != state.active_unit:
			out.append(u)
	return out


static func start_combat(state: GameState, first_side: String) -> Array[Dictionary]:
	state.phase = GameState.PHASE_COMBAT
	state.first_side = first_side
	state.round_number = 0
	var events: Array[Dictionary] = [{"type": "combat_started", "first_side": first_side}]
	events.append_array(Combat.refresh_engagement(state))
	events.append_array(_start_round(state, ""))
	return events


## `last_side`: the side that took the last turn of the previous round ("" at combat start).
static func _start_round(state: GameState, last_side: String) -> Array[Dictionary]:
	state.round_number += 1
	state.acted = PackedStringArray()
	state.active_unit = ""
	if last_side == "":
		state.turn_side = state.first_side if not waiting(state, state.first_side).is_empty() else _next_side(state, state.first_side)
	else:
		state.turn_side = _next_side(state, last_side)
	for u: Unit in state.units.values():
		# "Each character only needs to make one such check per round" (glossary: Dangerous Terrain).
		u.counters.erase("dangerous_checked")
		u.counters.erase("round_grants_used")
	return [{"type": "round_started", "round": state.round_number, "side": state.turn_side}] as Array[Dictionary]


## The side after `after` (in turn order) that still has units waiting, or "" if none.
static func _next_side(state: GameState, after: String) -> String:
	var order := sides(state)
	if order.is_empty():
		return ""
	var start := order.find(after)
	for i in range(1, order.size() + 1):
		var side: String = order[(start + i) % order.size()]
		if not waiting(state, side).is_empty():
			return side
	return ""


static func begin_turn(state: GameState, u: Unit) -> Array[Dictionary]:
	state.active_unit = u.id
	u.turn = {"quick": 0, "full": false, "taken": [], "quick_tech": [], "move_spent": 0,
		"moved": false, "acted": false, "overcharged": false, "free_quick": 0}
	if u.counters.get("brace_next_turn", false):
		u.counters.erase("brace_next_turn")
		u.turn["braced"] = true
		if Effects.has(u, "fortress_brace"):
			u.turn["braced_full"] = true  # Drake Fortress: a full action instead of a quick one
	# Reactions refresh at the start of the unit's turn (tags: X/Round counts from turn start).
	u.counters.erase("reactions")
	var events: Array[Dictionary] = []
	if u.counters.has("prepared"):
		# A prepared action lasts until the start of your next turn (actions: Prepare).
		u.counters.erase("prepared")
		events.append({"type": "prepared_lost", "unit": u.id, "rule_ref": "actions: Prepare"})
	events.append({"type": "turn_started", "unit": u.id, "round": state.round_number})
	u.counters.erase("ability_round_uses")  # X/round: from the start of your turn (tags: Round)
	events.append_array(Combat.expire_at_turn_start(state, u))
	events.append_array(Abilities.expire(state, u, "start"))
	events.append_array(Abilities.recharge_roll(state, u))
	u.counters.erase("no_holograms")  # Dusk Wing: new holograms again from the start of its turn
	for ws: Variant in (u.counters.get("weapons", {}) as Dictionary).values():
		(ws as Dictionary).erase("uncle_lock")
	events.append_array(Effects.turn_started(state, u))
	events.append_array(Zones.turn_started(state, u))
	events.append_array(FrameSystems.host_turn_started(state, u))
	events.append_array(CoreBonuses.turn_started(state, u))
	return events


## End-of-turn bookkeeping for `u`, then hand the activation to the next side.
static func finish_turn(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not u.destroyed:
		events.append_array(FrameSystems.host_turn_ending(state, u))
		events.append_array(Effects.turn_ending(state, u))
		events.append_array(Combat.end_of_turn_checks(state, u))
	events.append_array(Combat.fall_all(state, u))
	events.append_array(Combat.expire_statuses(state, u))
	events.append_array(Abilities.expire(state, u, "end"))
	events.append_array(Zones.turn_ended(state, u))
	Abilities.arm_mines(state, u)
	events.append_array(Combat.tick_meltdown(state, u))
	var wreck := state.unit(String(u.counters.get("mounted_in", "")))
	if wreck != null and wreck.counters.has("unstable_explosion"):
		wreck.counters["unstable_explosion"] = int(wreck.counters["unstable_explosion"]) - 1
		if int(wreck.counters["unstable_explosion"]) <= 0:
			wreck.counters.erase("unstable_explosion")
			events.append_array(Pilots.explode(state, wreck, "Unstable System: the wreck explodes."))
	state.acted.append(u.id)
	state.active_unit = ""
	events.append({"type": "turn_ended", "unit": u.id})
	var next := _next_side(state, u.side)
	if next == "":
		events.append_array(_start_round(state, u.side))
	else:
		state.turn_side = next
		events.append({"type": "next_side", "side": next})
	return events


## Can `u` spend an action of `cost` named `action` right now? Doesn't change anything.
static func can_spend(u: Unit, cost: String, action: String) -> RuleResult:
	if u.has_status("Shut Down"):
		if action == "boot_up":
			return RuleResult.allow()
		return RuleResult.deny("A Shut Down mech is Stunned until it Boots Up.", "statuses: Shut Down")
	if u.has_status("Stunned"):
		if action == "eject" or action == "dismount":
			return RuleResult.allow()  # pilots can still Eject or Dismount from Stunned mechs
		return RuleResult.deny("Stunned mechs can't take any actions, free actions or reactions.", REF_STUNNED)
	if Movement.above_ceiling(state_of(u), u) and action != "boost" and cost != REACTION:
		return RuleResult.deny("More than 10 spaces above the battlefield you can only move and Boost.", "Core p.63 Flight")
	if u.turn.get("prepared_lock", false):
		return RuleResult.deny("After Preparing an action you can't move or act until it triggers or your next turn starts.", "actions: Prepare")
	var t := u.turn
	var braced: bool = t.get("braced", false)
	match cost:
		QUICK:
			if braced and (int(t.get("quick", 0)) >= 1 or t.get("full", false)):
				return RuleResult.deny("After Bracing you can only take one quick action this turn.", REF_BRACE)
			var repeat: bool = (t.get("taken", []) as Array).has(action) and action != "quick_tech"
			if (int(t.get("quick", 0)) < 2 and not repeat) or int(t.get("free_quick", 0)) > 0:
				return RuleResult.allow()
			if repeat:
				return RuleResult.deny("You've already taken that action this turn (Overcharge lets you repeat it).", REF_ACTIONS)
			return RuleResult.deny("You've used both quick actions this turn.", REF_ACTIONS)
		FULL:
			if braced and not t.get("braced_full", false):
				return RuleResult.deny("After Bracing you can't take full actions this turn.", REF_BRACE)
			if int(t.get("quick", 0)) > 0:
				return RuleResult.deny("A full action takes your whole turn: you've already taken a quick action.", REF_ACTIONS)
			return RuleResult.allow()
		FREE:
			if braced:
				return RuleResult.deny("After Bracing you can't take free actions this turn.", REF_BRACE)
	return RuleResult.allow()


## The GameState a unit belongs to, for checks that need the map (set by RulesEngine).
static var _state_ref: WeakRef = null


static func state_of(_u: Unit) -> GameState:
	return _state_ref.get_ref() if _state_ref != null else null


## Marks the action as taken. Call only after can_spend() allowed it.
static func spend(u: Unit, cost: String, action: String) -> void:
	var t := u.turn
	match cost:
		QUICK:
			var taken: Array = t.get("taken", [])
			var repeat: bool = taken.has(action) and action != "quick_tech"
			if (int(t.get("quick", 0)) < 2 and not repeat):
				t["quick"] = int(t.get("quick", 0)) + 1
			else:
				t["free_quick"] = int(t.get("free_quick", 0)) - 1
			taken.append(action)
			t["taken"] = taken
		FULL:
			t["quick"] = 2
			t["full"] = true
			(t.get("taken", []) as Array).append(action)
	if action != "move" and cost != REACTION:
		t["acted"] = true


## Checks shared by everything a unit does on its own turn.
static func check_own_turn(state: GameState, u: Unit) -> RuleResult:
	if state.phase != GameState.PHASE_COMBAT:
		return RuleResult.deny("Combat hasn't started.", REF_TURN_ORDER)
	if state.active_unit != u.id and not (FrameSystems.riding(state, u) and FrameSystems.host_of(state, u).id == state.active_unit):
		return RuleResult.deny("It isn't this unit's turn.", REF_TURN_ORDER)
	if u.destroyed:
		return RuleResult.deny("This mech has been destroyed.", "glossary: Structure")
	return RuleResult.allow()
