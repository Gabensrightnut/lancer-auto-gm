class_name GmActions
extends RefCounted
## Actions only the GM (host) sends, registered into the RulesEngine so they go through
## submit() like everything else. NetHost refuses actor-less actions from player seats.
##   gm_spawn        {"units": [Unit.to_dict(), ...], "reason": "reinforcements"}
##   gm_end_mission  {"outcome": "players" | "enemies" | "none", "reason": String, "scores": {}}
##   gm_narrate      {"kind": "twist" | "arrival" | "environment" | "narration", "text", "title", "question",
##                    "id", "speaker", "seen_by": [side, ...], "rule_ref"} (GmTwist)
## Events: units_arrived {units, reason}, mission_ended {outcome, reason, scores},
## twist_revealed {twist: {id, reveal, question}, title, speaker, seen_by, rule_ref} and
## gm_narration {kind, title, text, speaker, seen_by, rule_ref}. Narration changes nothing in
## the game state; `seen_by` limits who gets the event (ViewFilter.events_for).


static func register(engine: RulesEngine) -> void:
	for h: ActionHandler in [Spawn.new(), EndMission.new(), Narrate.new()]:
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


class Narrate:
	extends ActionHandler

	func type() -> String:
		return "gm_narrate"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var p: Dictionary = action.get("params", {})
		if state.phase == GameState.PHASE_ENDED:
			return RuleResult.deny("The mission is over.", "")
		if not str(p.get("kind", "")) in ["twist", "arrival", "environment", "narration"]:
			return RuleResult.deny("Narration kind must be twist, arrival, environment or narration.", "")
		if str(p.get("text", "")).strip_edges() == "":
			return RuleResult.deny("Narration needs some text.", "")
		if p.has("seen_by") and not p["seen_by"] is Array:
			return RuleResult.deny("seen_by must be a list of sides.", "")
		return RuleResult.allow()

	func resolve(_state: GameState, action: Dictionary) -> Array[Dictionary]:
		var p: Dictionary = action["params"]
		var e := {"title": str(p.get("title", "")), "speaker": str(p.get("speaker", "")), "rule_ref": str(p.get("rule_ref", ""))}
		if p.has("seen_by"):
			e["seen_by"] = (p["seen_by"] as Array).duplicate()
		if str(p["kind"]) == "twist":
			e["type"] = "twist_revealed"
			e["twist"] = {"id": str(p.get("id", "")), "reveal": str(p["text"]), "question": str(p.get("question", ""))}
		else:
			e["type"] = "gm_narration"
			e["kind"] = str(p["kind"])
			e["text"] = str(p["text"])
		return [e] as Array[Dictionary]
