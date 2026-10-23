extends TestCase
## Other people's mechs on the world map (MapTraffic): walking the roads between sites, seen only
## nearby, met, followed, or fought where they are; the warring factions in a region at war.

const Ambush := preload("res://tests/unit/test_flow_ambushes.gd")


func _region(war: bool) -> Dictionary:
	var r: Dictionary = Ambush.new()._region(war)
	r["sites"] = [{"id": "a", "kind": "town", "at": [2, 2], "area": {"place": "town", "at": [0, 0]}, "name": "A"},
		{"id": "b", "kind": "outpost", "at": [17, 2], "area": {"place": "outskirts", "at": [1, 0]}, "name": "B"},
		{"id": "c", "kind": "landmark", "at": [17, 17], "area": {"place": "wilds", "at": [1, 1]}, "name": "C"}]
	r["ambush_spots"] = []
	return r


func test_traffic_walks_is_seen_nearby_and_can_be_met_or_followed() -> void:
	var m := WorldMapSession.new(_region(false))
	expect(m.traffic.groups.size() >= 3, "a few groups on the roads")
	var g: Dictionary = m.traffic.groups[0]
	var start: Vector2 = g["at"]
	for i in range(20):
		m.tick(0.1)
	expect((g["at"] as Vector2) != start, "they walk in real time")
	m.add_seat("near", g["at"] + Vector2(1, 0), 4)
	m.add_seat("far", Vector2(-30, -30), 4)
	expect(m.view_for("near")["traffic"].any(func(t: Dictionary) -> bool: return t["id"] == g["id"]), "seen up close")
	expect(m.view_for("far")["traffic"].is_empty(), "not from far away")
	var met: Array = []
	m.traffic.met.connect(func(seat: String, grp: Dictionary) -> void: met.append([seat, grp["id"]]))
	expect_eq(m.traffic.meet("near", m.seats["near"]["at"], g["id"]), "")
	expect(met == [["near", g["id"]]], "a mech-to-mech talk for story")
	expect(m.traffic.meet("far", m.seats["far"]["at"], g["id"]) != "", "too far to talk")
	expect_eq(m.follow("near", g["id"]), "")
	for i in range(40):
		m.tick(0.1)
	expect((m.seats["near"]["at"] as Vector2).distance_to(g["at"]) < 2.5, "following them")


func test_at_war_some_are_the_factions() -> void:
	var factions := {}
	for seed_value in range(20):
		var m := WorldMapSession.new(_region(true), null, Dice.new(seed_value))
		for g: Dictionary in m.traffic.groups:
			if str(g["faction"]) != "":
				factions[g["faction"]] = true
				expect(bool(g["hostile"]))
	expect(factions.size() == 2, "both sides' patrols are out there: %s" % str(factions.keys()))
	var peace := WorldMapSession.new(_region(false))
	expect(peace.traffic.groups.all(func(g: Dictionary) -> bool: return str(g["faction"]) == ""), "no war: no faction troops")
