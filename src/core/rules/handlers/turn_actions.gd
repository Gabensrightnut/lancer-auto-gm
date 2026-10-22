class_name TurnActions
extends RefCounted
## Starting combat, activating a unit, ending a turn. See TurnRules for the turn order.


class StartCombat:
	extends ActionHandler
	## {"type": "start_combat", "params": {"first_side": "players", "units": [ids] | "center": [x, y],
	## "radius": n, "mode": "combat" | "explore"}} (no actor; sent by the host). Only the units
	## listed (or within the radius) take part; the rest keep exploring and can join_combat.
	## mode "explore": turn-based exploring (same turns, for stealth; nobody needs to be hostile).

	func type() -> String:
		return "start_combat"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase == GameState.PHASE_COMBAT:
			return RuleResult.deny("Combat has already started.", TurnRules.REF_TURN_ORDER)
		var params: Dictionary = action.get("params", {})
		var first: String = params.get("first_side", "")
		var inside := TurnRules.participants(state, params)
		var found := false
		for u: Unit in inside:
			found = found or (u.side == first and TurnRules.takes_turns(u))
		if not found:
			return RuleResult.deny("Pick a side with units to go first.", TurnRules.REF_TURN_ORDER)
		var players_here := false
		for u: Unit in inside:
			players_here = players_here or (state.player_sides.has(u.side) and TurnRules.takes_turns(u))
		if players_here and not state.player_sides.has(first):
			return RuleResult.deny("Players always get to act first.", "Core p.60")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.start_combat(state, action["params"]["first_side"], action["params"])


class JoinCombat:
	extends ActionHandler
	## {"type": "join_combat", "actor": unit, "params": {"to": [x, y], "level"}}: a unit that was
	## exploring arrives at a fight in progress, in any free space (behind the enemy is fine).
	## It joins the alternating activations from the next round. Arriving isn't movement in
	## the fight, so it provokes nothing. PROVISIONAL: the free core book gives no timing for
	## arrivals (RULES_TODO).

	func type() -> String:
		return "join_combat"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(String(action.get("actor", "")))
		if state.phase != GameState.PHASE_COMBAT:
			return RuleResult.deny("There's no fight to join.", TurnRules.REF_TURN_ORDER)
		if u == null or u.destroyed or not u.counters.get("exploring", false):
			return RuleResult.deny("Only someone who isn't in the fight yet can join it.", TurnRules.REF_TURN_ORDER)
		var to: Variant = TurnAction.cell_param(action.get("params", {}), "to")
		if to == null or not state.map.has_cell(to):
			return RuleResult.deny("Say where it arrives (params.to).", TurnRules.REF_TURN_ORDER)
		var lv := int(action["params"].get("level", state.map.ground_height(to)))
		var place := Movement.placement(state, u.size, to, lv)
		if not place["ok"] or not (place["standing"] or u.flying):
			return RuleResult.deny("It can't stand there: %s" % place.get("reason", "no footing"), place.get("rule_ref", ""))
		var body := Sight.make_body(state, to, lv, u.size)
		for o: Unit in state.units.values():
			if o != u and Combat.is_present(o) and Movement._overlaps(body, Sight.body_of(state, o)):
				return RuleResult.deny("That space is taken.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(String(action["actor"]))
		var to: Vector2i = TurnAction.cell_param(action["params"], "to")
		var from := [u.cell.x, u.cell.y, u.level]
		u.cell = to
		u.level = int(action["params"].get("level", state.map.ground_height(to)))
		u.counters.erase("exploring")
		u.counters["joins_round"] = state.round_number + 1
		var events: Array[Dictionary] = [{"type": "joined_combat", "unit": u.id, "cell": [to.x, to.y, u.level], "from": from,
			"round": state.round_number + 1, "rule_ref": TurnRules.REF_TURN_ORDER}]
		events.append_array(Combat.refresh_engagement(state))
		return events


class ExploreMove:
	extends ActionHandler
	## {"type": "explore_move", "actor": unit, "params": {"to": [x, y], "level"}}: real-time
	## exploring movement, outside a fight (or for a unit not in the current one). One step of up
	## to its Speed per action; the flow sends them as the player walks.

	func type() -> String:
		return "explore_move"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(String(action.get("actor", "")))
		if u == null or u.destroyed:
			return RuleResult.deny("No such unit.", "")
		if state.phase == GameState.PHASE_COMBAT and not u.counters.get("exploring", false):
			return RuleResult.deny("It's in the fight: move on its turn.", TurnRules.REF_TURN_ORDER)
		var saved := u.turn
		u.turn = {"move_spent": 0}
		var plan := MoveActions._plan(state, u, action.get("params", {}), Movement.MODE_MOVE)
		u.turn = saved
		return MoveActions._plan_result(plan)

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(String(action["actor"]))
		var saved := u.turn
		u.turn = {"move_spent": 0}
		var plan := MoveActions._plan(state, u, action.get("params", {}), Movement.MODE_MOVE)
		var events := MoveActions._do_move(state, u, plan, "walk", bool(action.get("params", {}).get("fly", false)))
		u.turn = saved
		return events


class EndCombat:
	extends ActionHandler
	## {"type": "end_combat"} (host): the fight is over and everyone is back to exploring. Units
	## still exploring elsewhere simply carry on. RulesQueries.combat_over(state) says when only
	## one side is left fighting.

	func type() -> String:
		return "end_combat"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, _action: Dictionary) -> RuleResult:
		if state.phase != GameState.PHASE_COMBAT:
			return RuleResult.deny("There's no fight going on.", TurnRules.REF_TURN_ORDER)
		if not state.pending.is_empty() or state.active_unit != "":
			return RuleResult.deny("Finish the current turn first.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, _action: Dictionary) -> Array[Dictionary]:
		var mode := state.turn_mode
		state.phase = GameState.PHASE_SETUP
		state.turn_mode = "combat"
		state.round_number = 0
		state.active_unit = ""
		state.acted = PackedStringArray()
		state.turn_side = ""
		for u: Unit in state.units.values():
			u.counters.erase("exploring")
			u.counters.erase("joins_round")
			u.counters.erase("activations_used")
		return [{"type": "combat_ended", "mode": mode, "rule_ref": TurnRules.REF_TURN_ORDER}] as Array[Dictionary]


class StartTurn:
	extends ActionHandler
	## {"type": "start_turn", "actor": unit} — the side whose pick it is chooses who acts.

	func type() -> String:
		return "start_turn"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		if state.phase != GameState.PHASE_COMBAT:
			return RuleResult.deny("Combat hasn't started.", TurnRules.REF_TURN_ORDER)
		if state.active_unit != "":
			return RuleResult.deny("Another unit is still taking its turn.", TurnRules.REF_TURN_ORDER)
		if not TurnRules.takes_turns(u):
			return RuleResult.deny("This unit doesn't take turns.", TurnRules.REF_TURN_ORDER)
		if state.acted.has(u.id):
			return RuleResult.deny("This unit has already acted this round.", TurnRules.REF_TURN_ORDER)
		if u.side != state.turn_side:
			return RuleResult.deny("It's the other side's pick: sides take turns activating units.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.begin_turn(state, state.unit(action["actor"]))


class EndTurn:
	extends ActionHandler

	func type() -> String:
		return "end_turn"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.active_unit != action.get("actor", ""):
			return RuleResult.deny("It isn't this unit's turn.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.finish_turn(state, state.unit(action["actor"]))
