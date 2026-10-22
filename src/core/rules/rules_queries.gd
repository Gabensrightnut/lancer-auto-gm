class_name RulesQueries
extends RefCounted
## Read-only questions the renderer, UI and GM AI can ask while a player plans. Nothing here
## changes the GameState or rolls dice, and the answers are exactly what the rules will
## apply when the action is submitted. Results are plain Dictionaries (network-friendly).
## Run them on the host (they see the full state, including Hidden units).


## Movement arrow: the path to `cell` (optionally a height `level`), its cost, the movement
## left, and warnings (difficult/dangerous terrain, climbing, Engaged stop, provoking,
## needs a Boost, flight, table ruling). `mode` "move" or "boost". See Movement.plan().
static func preview_move(state: GameState, unit_id: String, cell: Vector2i, level: int = -1, mode: String = "move", fly: bool = false) -> Dictionary:
	var u := state.unit(unit_id)
	if u == null:
		return {"ok": false, "reason": "No such unit."}
	return Movement.plan(state, u, cell, level, mode, fly)


## Every space the unit can reach with its remaining move (or a Boost), for greying out the
## rest. {"budget", "spaces": [{"cell": [x, y], "level", "cost", "stops"}]}
static func reachable(state: GameState, unit_id: String, mode: String = "move", fly: bool = false) -> Dictionary:
	var u := state.unit(unit_id)
	if u == null:
		return {"budget": 0, "spaces": []}
	return Movement.reachable(state, u, mode, fly)


## Can `from_id` see `to_id`?
static func line_of_sight(state: GameState, from_id: String, to_id: String) -> bool:
	return Sight.unit_line_of_sight(state, state.unit(from_id), state.unit(to_id))


## Cover the target has against a ranged attack from the attacker:
## {los, cover: "none"/"soft"/"hard", difficulty, cover_cells: [[x, y]], reason, rule_ref}.
static func cover(state: GameState, attacker_id: String, target_id: String) -> Dictionary:
	return Sight.unit_cover(state, state.unit(attacker_id), state.unit(target_id))


## Cover the unit would have at a destination, against each enemy: {enemy_id: cover dict}.
static func cover_at(state: GameState, unit_id: String, cell: Vector2i, level: int) -> Dictionary:
	return Sight.cover_at(state, state.unit(unit_id), cell, level)


## Hit-chance breakdown for an attack with a weapon (key from loadout.weapons): every
## Accuracy/Difficulty source with its label and rule, the flat bonus, the target number,
## and `hit_chance` (0..1). See Attacks.preview().
static func attack_preview(state: GameState, attacker_id: String, weapon_key: String, target_id: String, use_lock_on: bool = true) -> Dictionary:
	var a := state.unit(attacker_id)
	var p := Attacks.preview(state, a, Weapons.find(a, weapon_key), state.unit(target_id), {"use_lock_on": use_lock_on})
	if p["ok"]:
		p["hit_chance"] = hit_chance(p["bonus"], p["accuracy"] - p["difficulty"], p["target_number"])
		if state.unit(target_id).has_status("Invisible"):
			p["hit_chance"] = float(p["hit_chance"]) * 0.5
	return p


## Same for a tech attack (Invade).
static func tech_preview(state: GameState, attacker_id: String, target_id: String) -> Dictionary:
	var p := Attacks.tech_preview(state, state.unit(attacker_id), state.unit(target_id))
	if p["ok"]:
		p["hit_chance"] = hit_chance(p["bonus"], p["accuracy"] - p["difficulty"], p["target_number"])
	return p


## Hostiles that could react (Overwatch) if the unit starts moving now.
static func threatened_by(state: GameState, unit_id: String) -> Array[String]:
	return Movement.threatened_by(state, state.unit(unit_id))


## Exact chance that d20 + bonus + (net Accuracy d6s, highest kept) >= target.
static func hit_chance(bonus: int, net: int, target: int) -> float:
	var outcomes := {0: 1.0}  # modifier -> probability
	if net != 0:
		outcomes = {}
		var n := absi(net)
		for high in range(1, 7):
			# P(max of n d6 == high)
			var p := pow(high / 6.0, n) - pow((high - 1) / 6.0, n)
			outcomes[high * signi(net)] = p
	var chance := 0.0
	for mod: int in outcomes:
		var need := target - bonus - mod
		var p_d20 := clampf((21 - need) / 20.0, 0.0, 1.0)
		chance += outcomes[mod] * p_d20
	return chance
