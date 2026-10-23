class_name WorldMapSession
extends RefCounted
## The region map you walk around in real time (DESIGN.md "Exploring vs. fighting": the Final
## Fantasy VII / X feel), host side and headless. Each seat's player is somewhere on it, in
## their mech or on foot, or inside one of its sites (a town, outpost, job site, safe point or
## landmark: an ExploreRegion area, entered seamlessly). Walking costs travel time on the
## clock: a tile's cost (hours per space at Speed 1) over the Speed used, which is the slowest
## mech's while the squad moves together and each one's own when they split up. Players roam
## on their own until a major story event gathers them (gather()).
##
## Region (from world): {id, size: [w, h], tiles: {"x,y": {terrain, cost, mech: bool, foot: bool}},
##   sites: [{id, kind, at: [x, y], area: {place, at: [x, y]}, name}]}.
## Seat: {at: Vector2 (tiles), target: Vector2i or null, on: "mech"/"foot", speed, in_area,
##   site, hours (this seat's travel time not yet passed on)}.

## Travel time to pass to the story's clock (the host submits it there).
signal travelled(seats: Array, hours: float)
signal entered(seat: String, site_id: String, area_key: String)
signal left(seat: String, site_id: String)

## Tiles per second on screen while walking the map (pacing only: the clock uses the cost).
const MAP_SPEED := 2.5
## Seats within this many tiles of each other, heading to the same tile, travel together.
const TOGETHER := 1.6

var region: Dictionary = {}
var explore: ExploreRegion
var seats: Dictionary = {}
## Ambushers hidden in cover in a region at war (Ambushes), and the story's dice for them.
var ambushes := Ambushes.new()
## Other people's mechs walking the roads (MapTraffic).
var traffic := MapTraffic.new()
var dice: Dice


func _init(region_map: Dictionary, explore_region: ExploreRegion = null, story_dice: Dice = null) -> void:
	region = region_map
	explore = explore_region
	dice = story_dice if story_dice != null else Dice.new(int(hash([region.get("id", ""), "map"])))
	ambushes = Ambushes.place(region, dice)
	traffic = MapTraffic.place(region, dice)
	travelled.connect(func(_g: Array, h: float) -> void: ambushes.pass_time(h))


func add_seat(seat: String, at: Vector2, speed: int, on: String = "mech", spot: int = 0) -> void:
	seats[seat] = {"at": at, "target": null, "dir": Vector2.ZERO, "on": on, "speed": maxi(1, speed), "in_area": "", "site": "", "hours": 0.0, "spot": spot}


## Follow a traffic group (a convoy, a patrol...): walk after it until told otherwise.
func follow(seat: String, group_id: String) -> String:
	var s: Dictionary = seats.get(seat, {})
	if s.is_empty() or traffic.group(group_id).is_empty():
		return "Nobody like that here."
	s["follow"] = group_id
	return ""


## WASD / stick (the explore keybinds): walk in a direction for as long as it's held
## (Vector2.ZERO stops). Clears a click-to-walk target.
func move(seat: String, dir: Vector2) -> String:
	var s: Dictionary = seats.get(seat, {})
	if s.is_empty():
		return "Nobody there."
	if str(s["in_area"]) != "":
		return "Leave %s first." % str(_site(str(s["site"])).get("name", "here"))
	s["dir"] = dir.normalized() if dir.length() > 0.05 else Vector2.ZERO
	s["target"] = null
	s.erase("follow")
	return ""


func tile(t: Vector2i) -> Dictionary:
	return region.get("tiles", {}).get("%d,%d" % [t.x, t.y], {})


static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.y))


func walkable(t: Vector2i, on: String) -> bool:
	var d := tile(t)
	return not d.is_empty() and bool(d.get(on, d.get("mech", true)))


## Head for a tile. "" or why not (off the map, ground a mech or a pilot can't cross, or the
## player is inside a site).
func walk_to(seat: String, t: Vector2i) -> String:
	var s: Dictionary = seats.get(seat, {})
	if s.is_empty():
		return "Nobody there."
	if str(s["in_area"]) != "":
		return "Leave %s first." % str(_site(str(s["site"])).get("name", "here"))
	if not walkable(t, str(s["on"])):
		return "You can't go there %s." % ("in a mech" if s["on"] == "mech" else "on foot")
	s["target"] = t
	s["dir"] = Vector2.ZERO
	s.erase("follow")
	return ""


## Moves everyone walking the map (`delta` seconds of real time); travel time builds up per tile.
func tick(delta: float) -> void:
	traffic.tick(region, delta)
	for seat: String in seats:
		var f := traffic.group(str(seats[seat].get("follow", "")))
		if not f.is_empty() and (f["at"] as Vector2).distance_to(seats[seat]["at"]) > 1.2:
			seats[seat]["target"] = tile_of(f["at"])  # keep a little way behind
	var moving: Array = seats.keys().filter(func(k: String) -> bool: return (seats[k]["target"] != null or seats[k]["dir"] != Vector2.ZERO) and str(seats[k]["in_area"]) == "")
	for seat: String in moving:
		var s: Dictionary = seats[seat]
		var from: Vector2 = s["at"]
		var to: Vector2 = Vector2(s["target"]) if s["target"] != null else from + (s["dir"] as Vector2) * MAP_SPEED * delta
		var step := minf(MAP_SPEED * delta, from.distance_to(to))
		var next := from + (to - from).normalized() * step if step > 0.0 else from
		if not walkable(tile_of(next), str(s["on"])):
			s["target"] = null
			s["dir"] = Vector2.ZERO
			continue
		if tile_of(next) != tile_of(from):
			s["hours"] = float(s["hours"]) + float(tile(tile_of(next)).get("cost", 1.0)) / float(speed_of(seat))
		s["at"] = next
		if s["target"] != null and next.distance_to(to) < 0.01:
			s["target"] = null
	_pass_time()
	ambushes.tick(seats, dice, delta)


## The Speed a seat travels at: the slowest of those moving with it, else its own.
func speed_of(seat: String) -> int:
	var group := group_of(seat)
	var slowest: int = seats[seat]["speed"]
	for other: String in group:
		slowest = mini(slowest, int(seats[other]["speed"]))
	return slowest


## Who travels with `seat`: near it and heading to the same tile (or both standing).
func group_of(seat: String) -> Array:
	var s: Dictionary = seats[seat]
	var out: Array = []
	for other: String in seats:
		var o: Dictionary = seats[other]
		if str(o["in_area"]) == "" and (o["at"] as Vector2).distance_to(s["at"]) <= TOGETHER and o["target"] == s["target"] and o["dir"] == s["dir"]:
			out.append(other)
	return out


func _pass_time() -> void:
	# A group's time passes once (they travel together); a lone traveller's on its own.
	var done := {}
	for seat: String in seats:
		if done.has(seat) or float(seats[seat]["hours"]) < 0.25:
			continue
		var group := group_of(seat)
		var hours := 0.0
		for g: String in group:
			hours = maxf(hours, float(seats[g]["hours"]))
			seats[g]["hours"] = 0.0
			done[g] = true
		travelled.emit(group, hours)


func _site(id: String) -> Dictionary:
	for site: Dictionary in region.get("sites", []):
		if str(site["id"]) == id:
			return site
	return {}


## The site on a tile ({} if none).
func site_at(t: Vector2i) -> Dictionary:
	for site: Dictionary in region.get("sites", []):
		if Vector2i(int(site["at"][0]), int(site["at"][1])) == t:
			return site
	return {}


## Go into the site the seat is standing on: its area (ExploreRegion), seamlessly. Returns the
## area's key, or "" (no site here).
func enter(seat: String) -> String:
	var s: Dictionary = seats.get(seat, {})
	if s.is_empty() or str(s["in_area"]) != "":
		return ""
	var site := site_at(tile_of(s["at"]))
	if site.is_empty():
		return ""
	var area: Dictionary = site.get("area", {})
	var at := Vector2i(int(area.get("at", [0, 0])[0]), int(area.get("at", [0, 0])[1]))
	var key := ExploreRegion.key_of(at)
	if explore != null:
		explore.area_at(at)
	s["in_area"] = key
	s["site"] = str(site["id"])
	s["target"] = null
	entered.emit(seat, str(site["id"]), key)
	return key


## Out of a site's area (its edge) and back on the map, beside the site.
func leave(seat: String) -> void:
	var s: Dictionary = seats.get(seat, {})
	if s.is_empty() or str(s["in_area"]) == "":
		return
	var site := _site(str(s["site"]))
	var at := Vector2(int(site["at"][0]), int(site["at"][1]))
	for d: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		if walkable(tile_of(at + d), str(s["on"])):
			at += d
			break
	s["at"] = at
	s["in_area"] = ""
	left.emit(seat, str(s["site"]))
	s["site"] = ""


## Everyone to the lead (a major story event): onto the lead's tile, or into the lead's site.
func gather(lead: String) -> void:
	var l: Dictionary = seats.get(lead, {})
	if l.is_empty():
		return
	for seat: String in seats:
		if seat == lead:
			continue
		var s: Dictionary = seats[seat]
		s["target"] = null
		s["at"] = l["at"]
		s["in_area"] = l["in_area"]
		s["site"] = l["site"]
	if str(l["in_area"]) != "" and explore != null:
		explore.gather(lead)


## What one seat sees: the squad's positions (everyone on the map is on the same side), the
## sites, and each traveller's group.
func view_for(_seat: String) -> Dictionary:
	var squad := {}
	for seat: String in seats:
		var s: Dictionary = seats[seat]
		squad[seat] = {"at": [snappedf((s["at"] as Vector2).x, 0.01), snappedf((s["at"] as Vector2).y, 0.01)], "on": s["on"], "in_area": s["in_area"], "site": s["site"]}
	return {"region": str(region.get("id", "")), "size": region.get("size", [0, 0]), "squad": squad, "ambushers": ambushes.view_for(_seat), "traffic": traffic.view_for(seats.get(_seat, {}).get("at", Vector2(-999, -999))),
		"sites": (region.get("sites", []) as Array).map(func(site: Dictionary) -> Dictionary: return {"id": site["id"], "kind": site.get("kind", ""), "at": site["at"], "name": site.get("name", "")})}
