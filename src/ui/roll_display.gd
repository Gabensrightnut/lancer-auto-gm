class_name RollDisplay
extends RefCounted
## Text for roll breakdowns (pop-up hover and combat log). No dice graphics: rolls are shown
## as numbers by RollPopups (DESIGN "Roll visuals").
## Input: the `check` record from Dice.check() with optional `sources`
## ([{label, kind/type: "accuracy"/"difficulty", value}]), `bonus_sources`/`bonuses`
## ([{label, value}]) and `target_label`.

const BLUE := Color(0.32, 0.62, 1.0)
const RED := Color(1.0, 0.32, 0.28)
const GOLD := Color(1.0, 0.82, 0.3)
const HIT := Color(0.35, 1.0, 0.6)
const MISS := Color(0.7, 0.7, 0.74)


## Expands sources into one entry per point: {"accuracy": [labels], "difficulty": [labels]}.
static func expand_sources(check: Dictionary) -> Dictionary:
	var acc: Array = []
	var diff: Array = []
	for s: Variant in check.get("sources", []):
		var e: Dictionary = s if s is Dictionary else {"label": str(s), "type": "accuracy"}
		var n := int(e.get("value", 1))
		for i in range(absi(n)):
			if String(e.get("kind", e.get("type", "accuracy"))) == "difficulty":
				diff.append(e.get("label", "Difficulty"))
			else:
				acc.append(e.get("label", "Accuracy"))
	var ar: Dictionary = check.get("accuracy_roll", {})
	while acc.size() < int(ar.get("accuracy", 0)):
		acc.append("Accuracy")
	while diff.size() < int(ar.get("difficulty", 0)):
		diff.append("Difficulty")
	return {"accuracy": acc, "difficulty": diff}


## The breakdown in the design's format, e.g.
## "6 +4 (Accuracy: Lock On) +2 Grit = 12 vs Evasion 8: HIT".
static func formula_bbcode(check: Dictionary, result: String) -> String:
	var ar: Dictionary = check.get("accuracy_roll", {})
	var out := "%d" % int(check.get("d20", 0))
	var v := int(ar.get("value", 0))
	var src := expand_sources(check)
	if v > 0:
		out += " [color=#%s][b]+%d[/b] (Accuracy: %s)[/color]" % [BLUE.to_html(false), v, ", ".join(_unique(src["accuracy"]))]
	elif v < 0:
		out += " [color=#%s][b]−%d[/b] (Difficulty: %s)[/color]" % [RED.to_html(false), -v, ", ".join(_unique(src["difficulty"]))]
	for b: Dictionary in _bonuses(check):
		var n := int(b["value"])
		out += " %s%d %s" % ["+" if n >= 0 else "−", absi(n), b["label"]]
	out += " = %d" % int(check.get("total", 0))
	if check.has("target"):
		out += " vs %s %d" % [check.get("target_label", "Evasion"), int(check["target"])]
	if result != "":
		out += ": [b]%s[/b]" % result.to_upper()
	var cancelled := mini(src["accuracy"].size(), src["difficulty"].size())
	if cancelled > 0:
		out += "\n[color=#8899aa]%d Accuracy and %d Difficulty cancelled out.[/color]" % [cancelled, cancelled]
	return out


## Damage breakdown: dice, bonus, Armor, resistance, final.
static func damage_bbcode(e: Dictionary) -> String:
	var roll: Dictionary = e.get("roll", {})
	var parts: Array = []
	var dice: Array = []
	for r: Variant in roll.get("rolls", roll.get("dice", [])):
		dice.append(str(absi(int((r as Dictionary).get("value", 0)) if r is Dictionary else int(r))))
	if not dice.is_empty():
		parts.append("%s (%s)" % [roll.get("expr", "dice"), " + ".join(dice)])
	if int(roll.get("bonus", 0)) != 0:
		parts.append("+%d" % int(roll["bonus"]))
	var out := " ".join(parts)
	if int(e.get("armor_reduced", 0)) > 0:
		out += " [color=#%s]−%d Armor[/color]" % [RED.to_html(false), int(e["armor_reduced"])]
	if bool(e.get("resisted", false)):
		out += " [color=#%s]halved (resistance)[/color]" % RED.to_html(false)
	out += " = %d %s" % [int(e.get("amount", 0)), String(e.get("damage_type", "")).to_lower()]
	return out.strip_edges()


static func _unique(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		if not out.has(x):
			out.append(x)
	return out


static func _bonuses(check: Dictionary) -> Array:
	if check.has("bonuses"):
		return check["bonuses"]
	if check.has("bonus_sources"):
		return check["bonus_sources"]
	var b := int(check.get("bonus", 0))
	return [] if b == 0 else [{"label": "Bonus", "value": b}]


static func damage_color(dtype: String) -> Color:
	match dtype:
		"Energy":
			return Color(0.4, 0.85, 1.0)
		"Explosive":
			return Color(1.0, 0.6, 0.2)
		"Burn":
			return Color(1.0, 0.4, 0.15)
		"Heat":
			return Color(1.0, 0.5, 0.1)
	return Color(0.95, 0.92, 0.85)
