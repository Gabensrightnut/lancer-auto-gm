class_name HouseRuleSwitches
extends RefCounted
## House rules the rules engine knows (DESIGN.md "House rules"): on/off switches kept in
## state.house_rules = {id: bool}; a missing id uses the rule's default. They can be flipped
## between actions with {"type": "set_house_rule", "params": {"id", "on"}} (who may flip them is
## the host's call). The catalog (names, sources, text, defaults) is
## data/game/house_rules_engine.json; the house rules registry and its page list it.
## Everything here is labeled a house rule or a Lancer Tactics option: none of it is a book rule.

const DATA := "res://data/game/house_rules_engine.json"

static var _catalog: Array = []


static func catalog() -> Array:
	if _catalog.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_catalog = d if d is Array else []
	return _catalog


static func entry(id: String) -> Dictionary:
	for e: Dictionary in catalog():
		if e.get("id", "") == id:
			return e
	return {}


## Is the house rule `id` switched on?
static func on(state: GameState, id: String) -> bool:
	if state != null and state.house_rules.has(id):
		return bool(state.house_rules[id])
	return bool(entry(id).get("default", false))


## Every rule with its current setting, for the House Rules page.
static func listing(state: GameState) -> Array:
	var out: Array = []
	for e: Dictionary in catalog():
		var x := e.duplicate()
		x["on"] = on(state, String(e["id"]))
		out.append(x)
	return out


class SetHouseRule:
	extends ActionHandler
	## {"type": "set_house_rule", "params": {"id", "on": bool}}: between actions, any time.

	func type() -> String:
		return "set_house_rule"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var p: Variant = action.get("params", {})
		if not p is Dictionary or HouseRuleSwitches.entry(String((p as Dictionary).get("id", ""))).is_empty():
			return RuleResult.deny("No such house rule.", "")
		if not (p as Dictionary).get("on") is bool:
			return RuleResult.deny("Say on: true or false.", "")
		if not state.pending.is_empty():
			return RuleResult.deny("Finish the current action first.", "")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var id := String(action["params"]["id"])
		var value := bool(action["params"]["on"])
		state.house_rules[id] = value
		var e := HouseRuleSwitches.entry(id)
		return [{"type": "house_rule_changed", "id": id, "on": value, "name": e.get("name", id), "source": e.get("source", "")}] as Array[Dictionary]
