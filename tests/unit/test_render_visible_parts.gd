extends TestCase
## What you see matches the state: drones leave the body and leave gaps, recalls bring them
## back, destroyed weapons are gone, every deployable in the book has a look, and first person
## is a cockpit or (drone-bodied frames) your own remaining body.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _deployables_in(o: Variant, out: Array) -> void:
	if o is Dictionary:
		for d: Variant in (o as Dictionary).get("deployables", []):
			if d is Dictionary:
				out.append(d)
		for v: Variant in (o as Dictionary).values():
			_deployables_in(v, out)
	elif o is Array:
		for v: Variant in o:
			_deployables_in(v, out)


func test_every_book_deployable_has_a_look() -> void:
	var table: Dictionary = VisibleParts.data()["deployables"]
	var found: Array = []
	for f: String in ["frames", "systems", "weapons", "pilot_gear", "talents", "core_bonuses"]:
		_deployables_in(JSON.parse_string(FileAccess.get_file_as_string("res://data/lancer-data/%s.json" % f)), found)
	expect(found.size() >= 30, "found the book's deployables (%d)" % found.size())
	for d: Dictionary in found:
		var n := String(d.get("name", ""))
		expect(table.has(n), "%s is in data/game/visible_parts.json" % n)
		var s := VisibleParts.spec(n, String(d.get("type", "")))
		expect(String(s["look"]) in VisibleParts.LOOKS, "%s has a known look (%s)" % [n, s["look"]])
		var m := DeployableBuilder.build({"id": "x", "name": n, "size": d.get("size", 0.5) if d.get("size") != null else 0.5, "counters": {"deploy_type": d.get("type", "")}})
		expect(m.height > 0.03 and not m.find_children("*", "MeshInstance3D", true, false).is_empty(), "%s builds a model" % n)
		m.free()
	for n: String in table:
		expect(String(table[n].get("look", "")) in VisibleParts.LOOKS, "%s: known look" % n)


func test_hydra_drone_leaves_the_body_and_comes_back() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var hy := UnitFactory.build_mech(db(), "hy", "mf_hydra", {"mounts": [], "systems": [], "orochi": "Snare OROCHI Drone"})
	hy.side = "players"
	s.add_unit(hy)
	e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	s.turn_side = "players"
	F.act(e, s, "start_turn", "hy")
	var deploy := ""
	var recall := ""
	for a: Dictionary in Abilities.all(hy):
		if a["name"] == "Deploy Snare OROCHI Drone":
			deploy = a["key"]
		elif a["name"] == "Recall Snare OROCHI Drone":
			recall = a["key"]
	var out := F.act(e, s, "activate", "hy", {"ability": deploy, "to": [3, 0]})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "hy")
	s.round_number += 1
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "hy")
	var bv := BattleView.new()
	bv.content = db()
	bv.load_view(ViewFilter.new().view_for(s, "gm"))
	var mv: MechView = bv.units["hy"]
	expect(mv.model.docks.size() == 4, "the Hydra carries its four OROCHI drones")
	expect(not (mv.model.docks["Snare OROCHI Drone"] as Node3D).visible, "the deployed drone left a gap")
	expect((mv.model.docks["Guardian OROCHI Drone"] as Node3D).visible, "the others are still part of the body")
	var drone_id := ""
	for id: String in bv.units:
		if String((bv.units[id] as MechView).unit.get("kind", "")) == "deployable":
			drone_id = id
	expect(drone_id != "", "the drone is out on the board")
	if drone_id != "":
		expect(String((bv.units[drone_id] as MechView).model.name).begins_with("Deployable_"), "with its own drone model, not a mech")
	expect_eq(bv.first_person_style(mv), "body", "drone-bodied: first person shows your own body, no cockpit")
	out = F.act(e, s, "activate", "hy", {"ability": recall})
	expect(F.ok(out), F.reason(out))
	bv.sync_parts(ViewFilter.new().view_for(s, "gm")["units"])
	expect(not bv.units.has(drone_id), "recalled: gone from the board")
	expect((mv.model.docks["Snare OROCHI Drone"] as Node3D).visible, "and back in the body")
	bv.free()


func test_destroyed_weapon_is_gone_from_the_body() -> void:
	var s := F.state()
	var ev := UnitFactory.build_mech(db(), "ev", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []})
	ev.side = "players"
	s.add_unit(ev)
	var bv := BattleView.new()
	bv.content = db()
	bv.load_view(ViewFilter.new().view_for(s, "gm"))
	var mv: MechView = bv.units["ev"]
	var rifle: Node3D = mv.model.weapons.get("mw_assault_rifle")
	expect(rifle != null and rifle.visible, "the rifle is on the body")
	Weapons.state_of(ev, ev.loadout["weapons"][0])["destroyed"] = true
	bv.sync_parts(ViewFilter.new().view_for(s, "gm")["units"])
	expect(rifle != null and not rifle.visible, "destroyed: gone from the body")
	expect_eq(bv.first_person_style(mv), "cockpit", "a normal frame sees out of a cockpit")
	var shell := CockpitShell.build(MechStyles.palette("GMS"))
	expect(shell.get_child_count() >= 5, "the cockpit has a dash, screens, pillars and a strut")
	shell.free()
	bv.free()


func test_balor_hellswarm_and_lancaster_latch_follow_the_state() -> void:
	var s := F.state()
	var ba := UnitFactory.build_mech(db(), "ba", "mf_balor", {"mounts": [], "systems": []})
	ba.side = "players"
	s.add_unit(ba)
	var la := UnitFactory.build_mech(db(), "la", "mf_lancaster", {"mounts": [], "systems": []})
	la.side = "players"
	la.cell = Vector2i(2, 0)
	s.add_unit(la)
	var bv := BattleView.new()
	bv.content = db()
	bv.load_view(ViewFilter.new().view_for(s, "gm"))
	var bmv: MechView = bv.units["ba"]
	var lmv: MechView = bv.units["la"]
	expect(bmv.get_node_or_null("Hellswarm") == null, "no swarm until the core is active")
	expect((lmv.model.docks["Latch Drone"] as Node3D).visible, "the latch drone rides the Lancaster")
	ba.counters["core_active"] = true
	la.counters["latched_to"] = "ba"
	bv.sync_parts(ViewFilter.new().view_for(s, "gm")["units"])
	expect(bmv.get_node_or_null("Hellswarm") != null, "Hellswarm: the nanite cloak is out")
	expect(not (lmv.model.docks["Latch Drone"] as Node3D).visible, "the latch drone left the Lancaster")
	expect(bmv.get_node_or_null("Latched_la") != null, "and clamps onto its ally")
	bv.free()
