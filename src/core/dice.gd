class_name Dice
extends RefCounted
## All randomness in a game goes through one seeded Dice, so a game seed replays exactly
## and the host is the only machine that rolls. Every roll returns a record the UI can
## animate (base d20, blue Accuracy / red Difficulty d6s, flat bonuses).

var _rng := RandomNumberGenerator.new()


func _init(game_seed: int = 0) -> void:
	_rng.seed = game_seed


func get_state() -> int:
	return _rng.state


func set_state(state: int) -> void:
	_rng.state = state


func die(sides: int) -> int:
	return _rng.randi_range(1, sides)


## Rolls an expression like "1d6", "2d6+2", "1d3", "4" or "1d6+4".
## Returns {expr, rolls: [{sides, value}], bonus, total}.
func roll(expr: String) -> Dictionary:
	var clean := expr.replace(" ", "").to_lower()
	var rolls: Array = []
	var bonus := 0
	for term in clean.replace("-", "+-").split("+", false):
		var term_sign := 1
		if term.begins_with("-"):
			term_sign = -1
			term = term.substr(1)
		if "d" in term:
			var parts := term.split("d")
			var count := int(parts[0]) if parts[0] != "" else 1
			var sides := int(parts[1])
			for i in range(count):
				var v := die(sides)
				rolls.append({"sides": sides, "value": v * term_sign})
		else:
			bonus += int(term) * term_sign
	var total := bonus
	for r in rolls:
		total += int(r["value"])
	return {"expr": expr, "rolls": rolls, "bonus": bonus, "total": total}


## Accuracy and Difficulty cancel one for one; roll d6s for what's left and keep the
## highest, added for Accuracy and subtracted for Difficulty.
## Returns {accuracy, difficulty, net, color: "blue"/"red"/"", dice: [int], kept, value}.
func accuracy_roll(accuracy: int, difficulty: int) -> Dictionary:
	var net := accuracy - difficulty
	var dice: Array[int] = []
	for i in range(absi(net)):
		dice.append(die(6))
	var kept := 0
	for v in dice:
		kept = maxi(kept, v)
	var color := ""
	if net > 0:
		color = "blue"
	elif net < 0:
		color = "red"
	return {
		"accuracy": accuracy, "difficulty": difficulty, "net": net, "color": color,
		"dice": dice, "kept": kept, "value": kept * signi(net),
	}


## A full d20 check: d20 + flat bonus + Accuracy/Difficulty, compared to a target number.
## `sources` lists what caused each point of Accuracy/Difficulty, for the roll display.
## Returns {d20, accuracy_roll, bonus, total, target, success, crit, sources}.
func check(bonus: int, accuracy: int, difficulty: int, target: int, sources: Array = []) -> Dictionary:
	var d20 := die(20)
	var acc := accuracy_roll(accuracy, difficulty)
	var total := d20 + bonus + int(acc["value"])
	return {
		"d20": d20, "accuracy_roll": acc, "bonus": bonus, "total": total,
		"target": target, "success": total >= target, "crit": total >= 20,
		"sources": sources,
	}
