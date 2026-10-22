class_name DemoAI
extends RefCounted
## A stand-in enemy for the demo until the procedural GM exists: shoot the nearest player it
## can, otherwise move toward the nearest player and try again, then end the turn.
## One action at a time (next_action), so reactions the rules offer to players can be asked
## between steps. Every step goes through the rules engine.


## The next action for `uid` this turn, judged from the current state.
static func next_action(state: GameState, engine: RulesEngine, uid: String) -> Dictionary:
	var u := state.unit(uid)
	if not bool(u.turn.get("acted", false)):
		var shot := _attack(state, engine, u)
		if not shot.is_empty():
			return shot
		if not bool(u.turn.get("moved", false)):
			var move := _approach(state, engine, u)
			if not move.is_empty():
				return move
	return {"type": "end_turn", "actor": uid}


static func _targets(state: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if o.side != u.side and not o.destroyed:
			out.append(o)
	out.sort_custom(func(a: Unit, b: Unit) -> bool: return Sight.unit_distance(state, u, a) < Sight.unit_distance(state, u, b))
	return out


static func _attack(state: GameState, engine: RulesEngine, u: Unit) -> Dictionary:
	for t in _targets(state, u):
		for w: Dictionary in u.loadout.get("weapons", []):
			var action := {"type": "skirmish", "actor": u.id, "params": {"weapon": w["key"], "target": t.id}}
			if engine.validate(state, action).ok:
				return action
	return {}


static func _approach(state: GameState, engine: RulesEngine, u: Unit) -> Dictionary:
	var targets := _targets(state, u)
	if targets.is_empty():
		return {}
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
		return {}
	var action := {"type": "move", "actor": u.id, "params": {"to": best["cell"]}}
	return action if engine.validate(state, action).ok else {}
