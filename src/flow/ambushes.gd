class_name Ambushes
extends RefCounted
## Ambushes on the world map (DESIGN.md "Exploring vs. fighting", the user's request): only in a
## region at war (world flags it, story sets the war state), never a random pop-up from nowhere.
## Ambushers sit in real cover on the map (the region's cover spots: tree lines, ruins, ridges,
## wrecks). They stay hidden until a pilot spots them (a skill check, Core p.30: the Spot trigger
## is noticing what's hidden) or until they spring. Come close and they jump out and charge,
## visibly; you get a short window to run. Out of their reach before they close in: no fight.
## Caught: the fight starts there, with them where they caught you. Rarer than jobs, and never
## right after a fight (a cooldown on the clock). Whoever is caught starts the fight; the others
## can travel to it and join where they arrive.
##
## Region: {war: {factions: [...]} or null, ambush_spots: [{id, at: [x, y], cover: "tree line" |
##   "ruins" | "ridge" | "wreck", faction, force: [{template, count}]}]} (world provides the spots).
## Ambush: {id, at: Vector2, home: Vector2, cover, state: "hidden" | "spotted" | "charging" |
##   "gone" | "sprung", target: seat, enemies: [{template, count}]}.

signal spotted(seat: String, ambush: Dictionary, text: String)
signal charged(ambush: Dictionary, text: String)
signal escaped(seat: String, ambush: Dictionary, text: String)
## The fight starts where they caught `seat` (`at`, tiles), the ambushers right there.
signal caught(seat: String, ambush: Dictionary, at: Vector2)

## About one ambush spot in this many is manned (rarer than jobs).
const ONE_IN := 3
## Tiles: a pilot can try to spot them from here; they spring from here; they give up past here.
const SPOT_RANGE := 3.5
const SPRING_RANGE := 2.0
const BREAK_OFF := 4.5
## Tiles per second while charging (faster than walking the map: a short window to run).
const CHARGE_SPEED := 3.2
const CAUGHT := 0.6
## Hours on the clock after a fight before another ambush springs.
const COOLDOWN_HOURS := 6.0

var list: Array = []
var hours_since_fight := COOLDOWN_HOURS


## Hides ambushers in some of a region's cover spots (story's dice; nothing unless at war).
static func place(region: Dictionary, dice: Dice) -> Ambushes:
	var a := Ambushes.new()
	if not region.get("war") is Dictionary:
		return a
	for spot: Dictionary in region.get("ambush_spots", []):
		if dice.die(ONE_IN) != 1:
			continue
		var at := Vector2(float(spot["at"][0]), float(spot["at"][1]))
		var force: Array = spot["force"] if spot.get("force") is Array else [{"template": "ph_grunt", "count": 2}, {"template": "ph_assault", "count": 1}]
		a.list.append({"id": str(spot.get("id", "ambush%d" % a.list.size())), "at": at, "home": at, "cover": str(spot.get("cover", "cover")),
			"faction": str(spot.get("faction", "")), "state": "hidden", "target": "", "enemies": force.duplicate(true)})
	return a


## One step of real time. `seats`: {seat: {at: Vector2, in_area, spot: skill bonus}} (the map's
## positions); `dice`: the story's. Charging ambushers close in; someone caught starts a fight.
func tick(seats: Dictionary, dice: Dice, delta: float) -> void:
	for amb: Dictionary in list:
		match str(amb["state"]):
			"hidden", "spotted":
				for seat: String in seats:
					var s: Dictionary = seats[seat]
					if str(s.get("in_area", "")) != "":
						continue
					var d := (s["at"] as Vector2).distance_to(amb["at"])
					if amb["state"] == "hidden" and d <= SPOT_RANGE and not (amb.get("tried", {}) as Dictionary).has(seat):
						_try_spot(amb, seat, int(s.get("spot", 0)), dice)
					if d <= SPRING_RANGE and hours_since_fight >= COOLDOWN_HOURS:
						amb["state"] = "charging"
						amb["target"] = seat
						charged.emit(amb, "They break cover from the %s and charge!" % amb["cover"])
						break
			"charging":
				var t: Dictionary = seats.get(str(amb["target"]), {})
				if t.is_empty() or str(t.get("in_area", "")) != "":
					amb["state"] = "gone"
					continue
				var to: Vector2 = t["at"]
				var from: Vector2 = amb["at"]
				amb["at"] = from + (to - from).normalized() * minf(CHARGE_SPEED * delta, from.distance_to(to))
				var d := (amb["at"] as Vector2).distance_to(to)
				if d <= CAUGHT:
					amb["state"] = "sprung"
					caught.emit(str(amb["target"]), amb, amb["at"])
				elif (to - amb["home"]).length() > BREAK_OFF:  # outran them: far enough from their cover
					amb["state"] = "gone"
					escaped.emit(str(amb["target"]), amb, "You got away: they fall back into the %s." % amb["cover"])


## Spotting (Core p.30, skill triggers: Spot): 1d20 + the pilot's Spot bonus, 10 or more.
func _try_spot(amb: Dictionary, seat: String, bonus: int, dice: Dice) -> void:
	var tried: Dictionary = amb.get("tried", {})
	tried[seat] = true
	amb["tried"] = tried
	if dice.die(20) + bonus >= 10:
		amb["state"] = "spotted"
		spotted.emit(seat, amb, "Movement in the %s ahead." % amb["cover"])


## What to show when an ambush springs (the map view's spring_ambush): one entry per enemy in
## its force, rising out of its cover and charging toward `toward`.
static func spring_units(amb: Dictionary, toward: Vector2) -> Array:
	var out: Array = []
	var n := 0
	for g: Dictionary in amb.get("enemies", []):
		for i in range(int(g.get("count", 1))):
			n += 1
			out.append({"id": "%s_%d" % [amb["id"], n], "kind": "npc", "template": str(g.get("template", "")),
				"at": [(amb["at"] as Vector2).x, (amb["at"] as Vector2).y], "toward": [toward.x, toward.y]})
	return out


## Travel time passing (WorldMapSession.travelled): the cooldown after a fight runs on it.
func pass_time(hours: float) -> void:
	hours_since_fight += hours


func fight_over() -> void:
	hours_since_fight = 0.0


## What a seat may know: ambushes it has spotted, or that are charging (visible to all).
func view_for(seat: String) -> Array:
	var out: Array = []
	for amb: Dictionary in list:
		if amb["state"] in ["charging", "sprung"] or (amb["state"] == "spotted" and (amb.get("tried", {}) as Dictionary).has(seat)):
			out.append({"id": amb["id"], "at": [snappedf((amb["at"] as Vector2).x, 0.01), snappedf((amb["at"] as Vector2).y, 0.01)], "state": amb["state"], "cover": amb["cover"]})
	return out
