class_name DemoAI
extends RefCounted
## A stand-in enemy for the demo until the procedural GM exists: shoot the nearest player it
## can, otherwise move toward the nearest player and try again, then end the turn. Every step
## goes through the rules engine. Returns all events in order.


static func take_turn(state: GameState, engine: RulesEngine, uid: String) -> Array:
	var events: Array = []
	var u := state.unit(uid)
	if _attack(state, engine, u, events):
		pass
	else:
		_approach(state, engine, u, events)
		_attack(state, engine, u, events)
	events.append_array(engine.submit(state, {"type": "end_turn", "actor": uid})["events"])
	return events


static func _targets(state: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if o.side != u.side and not o.destroyed:
			out.append(o)
	out.sort_custom(func(a: Unit, b: Unit) -> bool: return Sight.unit_distance(state, u, a) < Sight.unit_distance(state, u, b))
	return out


static func _attack(state: GameState, engine: RulesEngine, u: Unit, events: Array) -> bool:
	for t in _targets(state, u):
		for w: Dictionary in u.loadout.get("weapons", []):
			var action := {"type": "skirmish", "actor": u.id, "params": {"weapon": w["key"], "target": t.id}}
			if engine.validate(state, action).ok:
				events.append_array(engine.submit(state, action)["events"])
				return true
	return false


static func _approach(state: GameState, engine: RulesEngine, u: Unit, events: Array) -> void:
	var targets := _targets(state, u)
	if targets.is_empty():
		return
	var goal := targets[0]
	var reach := RulesQueries.reachable(state, u.id)
	var best: Dictionary = {}
	var best_d := Sight.unit_distance(state, u, goal)
	for s: Dictionary in reach.get("spaces", []):
		var c := Vector2i(int(s["cell"][0]), int(s["cell"][1]))
		var d := state.map.grid.distance(c, goal.cell)
		if d < best_d and d >= 2:
			best_d = d
			best = s
	if best.is_empty():
		return
	var action := {"type": "move", "actor": u.id, "params": {"to": best["cell"]}}
	var out := engine.submit(state, action)
	if (out["result"] as RuleResult).ok:
		events.append_array(out["events"])
