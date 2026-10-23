class_name MapTraffic
extends RefCounted
## Other people's mechs on the world map (DESIGN.md "Exploring vs. fighting", the user's
## request): convoys with escort mechs, militia patrols, merc lances, corp security and haulers
## walking the roads between sites in real time. In a region at war some of them are the
## factions fighting it. Players see the traffic near them (secrets stay on the host: groups
## further off aren't in their view). You can meet a group (a mech-to-mech talk, which story
## runs: jobs, warnings), follow it, or keep away. A fight with one starts in place like any
## encounter. Their pilots and frames come from story's NPC pilot data; until it's wired in, a
## group carries a force [{template, count}] like the GM's tables.
##
## Group: {id, kind, name, faction, route: [site ids], leg (index of the site it's heading
##   to), at: Vector2 (tiles), hostile: bool, force: [...], pilots: [...]}.

## A group met someone (they talk; story takes it from here).
signal met(seat: String, group: Dictionary)
## A fight with a group starts where it is.
signal engaged(seat: String, group: Dictionary, at: Vector2)

const KINDS := {
	"convoy": {"name": "Convoy", "weight": 3, "force": [{"template": "ph_grunt", "count": 2}]},
	"patrol": {"name": "Militia patrol", "weight": 3, "force": [{"template": "ph_grunt", "count": 2}]},
	"merc": {"name": "Merc lance", "weight": 2, "force": [{"template": "ph_assault", "count": 2}]},
	"security": {"name": "Corp security", "weight": 2, "force": [{"template": "ph_grunt", "count": 1}, {"template": "ph_assault", "count": 1}]},
	"hauler": {"name": "Hauler", "weight": 2, "force": [{"template": "ph_grunt", "count": 1}]},
}
## Tiles per second on the map (a little slower than the squad: you can catch them up).
const SPEED := 1.6
## Tiles: how far a player sees traffic; how close to meet or start a fight.
const SIGHT := 6.0
const MEET := 1.5

var groups: Array = []


## Puts some traffic on a region's roads between its sites (story's dice): a few groups per
## region, some of them the warring factions when it's at war.
static func place(region: Dictionary, dice: Dice) -> MapTraffic:
	var t := MapTraffic.new()
	var sites: Array = region.get("sites", [])
	if sites.size() < 2:
		return t
	var war: Variant = region.get("war")
	var factions: Array = (war as Dictionary).get("factions", []) if war is Dictionary else []
	var count := 2 + dice.die(3)
	for i in range(count):
		var kind := _pick_kind(dice)
		var from := dice.die(sites.size()) - 1
		var to := (from + dice.die(sites.size() - 1)) % sites.size()
		var start: Dictionary = sites[from]
		var g := {"id": "traffic%d" % (i + 1), "kind": kind, "name": str(KINDS[kind]["name"]), "faction": "",
			"route": [str(start["id"]), str(sites[to]["id"])], "leg": 1, "at": Vector2(float(start["at"][0]), float(start["at"][1])),
			"hostile": false, "force": (KINDS[kind]["force"] as Array).duplicate(true), "pilots": []}
		if not factions.is_empty() and kind in ["patrol", "security", "merc"] and dice.die(2) == 1:
			g["faction"] = str(factions[dice.die(factions.size()) - 1])
			g["name"] = "%s %s" % [g["faction"], g["name"].to_lower()]
			g["hostile"] = true  # at war: they may well shoot first
		t.groups.append(g)
	return t


static func _pick_kind(dice: Dice) -> String:
	var total := 0
	for k: String in KINDS:
		total += int(KINDS[k]["weight"])
	var n := dice.die(total)
	for k: String in KINDS:
		n -= int(KINDS[k]["weight"])
		if n <= 0:
			return k
	return "convoy"


## Real time: each group walks to the next site on its route and turns round at the end.
func tick(region: Dictionary, delta: float) -> void:
	var sites := {}
	for s: Dictionary in region.get("sites", []):
		sites[str(s["id"])] = Vector2(float(s["at"][0]), float(s["at"][1]))
	for g: Dictionary in groups:
		var route: Array = g["route"]
		var to: Vector2 = sites.get(str(route[int(g["leg"])]), g["at"])
		var from: Vector2 = g["at"]
		g["at"] = from + (to - from).normalized() * minf(SPEED * delta, from.distance_to(to))
		if (g["at"] as Vector2).distance_to(to) < 0.01:
			g["leg"] = (int(g["leg"]) + 1) % route.size()


func group(id: String) -> Dictionary:
	for g: Dictionary in groups:
		if str(g["id"]) == id:
			return g
	return {}


## Talk to a group you're next to (story runs the conversation). "" or why not.
func meet(seat: String, at: Vector2, id: String) -> String:
	var g := group(id)
	if g.is_empty():
		return "Nobody like that here."
	if (g["at"] as Vector2).distance_to(at) > MEET:
		return "Get closer first."
	met.emit(seat, g)
	return ""


## Start a fight with a group you're next to (it starts where they are). "" or why not.
func engage(seat: String, at: Vector2, id: String) -> String:
	var g := group(id)
	if g.is_empty():
		return "Nobody like that here."
	if (g["at"] as Vector2).distance_to(at) > MEET:
		return "Get closer first."
	engaged.emit(seat, g, g["at"])
	return ""


## The traffic a player at `at` can see (within SIGHT).
func view_for(at: Vector2) -> Array:
	var out: Array = []
	for g: Dictionary in groups:
		if (g["at"] as Vector2).distance_to(at) <= SIGHT:
			out.append({"id": g["id"], "kind": g["kind"], "name": g["name"], "faction": g["faction"], "hostile": g["hostile"],
				"at": [snappedf((g["at"] as Vector2).x, 0.01), snappedf((g["at"] as Vector2).y, 0.01)], "mechs": (g["force"] as Array).reduce(func(n: int, f: Dictionary) -> int: return n + int(f.get("count", 1)), 0)})
	return out
