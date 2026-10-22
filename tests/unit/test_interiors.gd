extends TestCase
## Interiors: data story can use (rooms matching TownLife, doors, locks, containers, sleep and
## NPC points) and a buildable room that holds up at eye height.


func test_every_interior_lays_out_and_builds() -> void:
	for kind: String in Interiors.kinds():
		var lay := Interiors.layout(kind, "old_west", 1)
		expect(not (lay["rooms"] as Dictionary).is_empty(), "%s has rooms" % kind)
		expect((lay["doors"] as Array).any(func(d: Dictionary) -> bool: return "outside" in d["rooms"]), "%s has a way in" % kind)
		for d: Dictionary in lay["doors"]:
			for r: String in d["rooms"]:
				expect(r == "outside" or (lay["rooms"] as Dictionary).has(r), "%s door to a real room: %s" % [kind, r])
		for c: Dictionary in lay["containers"]:
			expect((lay["rooms"] as Dictionary).has(c["room"]) and c.has("lock") and c["contents"] is Array, "%s container %s" % [kind, c["id"]])
		# Nothing stands in a doorway.
		for f: Dictionary in lay["furniture"]:
			for d: Dictionary in lay["doors"]:
				var fp := Vector3(float(f["pos"][0]), float(f["pos"][1]), float(f["pos"][2]))
				var dp := Vector3(float(d["pos"][0]), float(d["pos"][1]), float(d["pos"][2]))
				expect(absf(fp.y - dp.y) > 0.1 or Vector2(fp.x - dp.x, fp.z - dp.z).length() > 0.5, "%s: %s blocks %s" % [kind, f["kind"], d["id"]])
		var node := Interiors.build(lay)
		expect(node.get_node_or_null("Ceiling") != null, "%s ceiling can be hidden" % kind)
		node.free()


func test_the_saloon_matches_story_rooms_and_keeps_a_safe() -> void:
	var lay := Interiors.layout("bar", "old_west", 2)
	for id: String in ["main", "back", "upstairs"]:
		expect((lay["rooms"] as Dictionary).has(id), "story's bar room %s" % id)
	var safe: Array = (lay["containers"] as Array).filter(func(c: Dictionary) -> bool: return c["id"] == "safe")
	expect(safe.size() == 1 and int(safe[0]["lock"]) == 2 and safe[0]["room"] == "back", "a hard safe in the back room")
	expect((lay["sleep"] as Array).size() >= 4, "beds upstairs")
	expect(float((lay["sleep"] as Array)[0]["pos"][1]) > 3.0, "the beds are upstairs")
	expect((lay["points"] as Array).any(func(p: Dictionary) -> bool: return p["type"] == "work"), "a place for the bartender")
	expect((lay["points"] as Array).any(func(p: Dictionary) -> bool: return p["type"] == "hide"), "somewhere to hide")
	expect(not (lay["stairs"] as Array).is_empty(), "stairs up")


func test_marshal_cells_ship_decks_and_sleepers() -> void:
	var m := Interiors.layout("marshal", "old_west", 1)
	var bars: Array = (m["doors"] as Array).filter(func(d: Dictionary) -> bool: return d["kind"] == "bars")
	expect(bars.size() == 3 and bars.all(func(d: Dictionary) -> bool: return int(d["lock"]) >= 1), "three locked cells")
	expect((m["containers"] as Array).any(func(c: Dictionary) -> bool: return c["kind"] == "safe"), "the marshal's safe")
	var ship := Interiors.layout("ship_deck", "", 1)
	for id: String in ["bridge", "captain", "crew", "commons", "engineering", "cargo"]:
		expect((ship["rooms"] as Dictionary).has(id), "ship room %s" % id)
	expect((ship["furniture"] as Array).any(func(f: Dictionary) -> bool: return f["kind"] == "nhp_core"), "the NHP's casing in engineering")
	var vault := Interiors.layout("sleeper_vault", "", 1)
	expect((vault["sleep"] as Array).filter(func(s: Dictionary) -> bool: return s["kind"] == "pod").size() >= 20, "rows of sleepers")


func test_doors_open_and_shut() -> void:
	var lay := Interiors.layout("marshal", "old_west", 1)
	var node := Interiors.build(lay)
	var door: Dictionary = (lay["doors"] as Array).filter(func(d: Dictionary) -> bool: return d["kind"] == "door")[0]
	var hinge: Node3D = node.get_node("Door_" + str(door["id"]))
	var shut := hinge.rotation.y
	Interiors.set_door(node, door["id"], true)
	expect(absf(hinge.rotation.y - shut) > 1.0, "the door swings open")
	Interiors.set_door(node, door["id"], false)
	expect(absf(hinge.rotation.y - shut) < 0.01, "and shut")
	node.free()
