class_name RoadEvents
extends RefCounted
## Road events (DESIGN.md "Exploring vs. fighting"): the few encounters on the world map that
## aren't scripted, from the procedural GM's tables (data/game/gm/road_events.json: a patrol,
## bandits, a broken-down convoy). Rolled per hour of travel on the story's dice, so they're
## seeded and saved like everything else. Each becomes an encounter on a "road" area, where any
## fight starts in place; the ones without a fight are something to stop for.

const FILE := "res://data/game/gm/road_events.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


## After `hours` of travel: an event ({id, name, text, fight, enemies}) or {}. One d100 per
## whole hour against chance_per_hour; at most one event per trip.
static func roll(dice: Dice, hours: float) -> Dictionary:
	var chance := int(data().get("chance_per_hour", 0))
	for i in range(int(floor(hours))):
		if dice.die(100) <= chance:
			return _pick(dice)
	return {}


static func _pick(dice: Dice) -> Dictionary:
	var events: Array = data().get("events", [])
	var total := 0
	for e: Dictionary in events:
		total += int(e.get("weight", 1))
	if total <= 0:
		return {}
	var n := dice.die(total)
	for e: Dictionary in events:
		n -= int(e.get("weight", 1))
		if n <= 0:
			return (e as Dictionary).duplicate(true)
	return {}


## The encounter's enemies as units for an area (MissionGenerator.build_enemy), ids prefixed
## so several encounters never clash.
static func enemies(event: Dictionary, prefix: String) -> Array:
	var templates := UnitFactory.npc_templates()
	var out: Array = []
	var n := 0
	for g: Dictionary in event.get("enemies", []):
		if not templates.has(str(g.get("template", ""))):
			continue
		for i in range(int(g.get("count", 1))):
			n += 1
			var u := MissionGenerator.build_enemy({"template": str(g["template"])}, templates, "%s%d" % [prefix, n], n)
			u.controller = NetHost.GM_SEAT
			out.append(u)
	return out
