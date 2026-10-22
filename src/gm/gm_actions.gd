class_name GmActions
extends RefCounted
## Actions only the GM (host) sends, registered into the RulesEngine so they go through
## submit() like everything else. NetHost refuses actor-less actions from player seats.
##   gm_spawn        {"units": [Unit.to_dict(), ...], "reason": "reinforcements"}
##   gm_end_mission  {"outcome": "players" | "enemies" | "none", "reason": String, "scores": {}}
## Events: units_arrived {units, reason}, mission_ended {outcome, reason, scores}.


static func register(engine: RulesEngine) -> void:
	for h: ActionHandler in [Spawn.new(), EndMission.new()]:
		if not engine.has_action(h.type()):
			engine.register(h)


class Spawn:
	extends ActionHandler

	func type() -> String:
		return "gm_spawn"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase == GameState.PHASE_ENDED:
			return RuleResult.deny("The mission is over.", "")
		var taken := {}
		for u: Unit in state.units.values():
			if not u.destroyed:
				for c in state.map.grid.footprint(u.cell, u.size):
					taken[c] = true
		for d: Variant in action.get("params", {}).get("units", []):
			if not d is Dictionary or str(d.get("id", "")) == "" or state.units.has(str(d["id"])):
				return RuleResult.deny("Each arriving unit needs a new, unique id.", "")
			var u := Unit.from_dict(d)
			for c in state.map.grid.footprint(u.cell, u.size):
				if not state.map.has_cell(c) or taken.has(c):
					return RuleResult.deny("%s has no free space to arrive in." % u.id, "")
				taken[c] = true
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var ids: Array = []
		for d: Dictionary in action["params"]["units"]:
			var u := Unit.from_dict(d)
			state.add_unit(u)
			ids.append(u.id)
		var events: Array[Dictionary] = [{"type": "units_arrived", "units": ids, "reason": str(action["params"].get("reason", ""))}]
		events.append_array(Combat.refresh_engagement(state))
		return events


class EndMission:
	extends ActionHandler

	func type() -> String:
		return "gm_end_mission"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase == GameState.PHASE_ENDED:
			return RuleResult.deny("The mission is already over.", "")
		if not str(action.get("params", {}).get("outcome", "")) in ["players", "enemies", "none"]:
			return RuleResult.deny("Outcome must be players, enemies or none.", "")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var p: Dictionary = action["params"]
		state.phase = GameState.PHASE_ENDED
		state.active_unit = ""
		return [{"type": "mission_ended", "outcome": p["outcome"], "reason": str(p.get("reason", "")),
			"scores": p.get("scores", {})}] as Array[Dictionary]
