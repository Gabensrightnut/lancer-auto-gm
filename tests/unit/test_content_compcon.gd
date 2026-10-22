extends TestCase
## COMP/CON pilot import/export. The pilot files here are written for these tests in COMP/CON's
## layouts (v2 export and v3 "Save Pilot" export), not copied from COMP/CON.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


static func _weapon(id: String) -> Dictionary:
	return {"id": id, "destroyed": false, "loaded": true, "mod": null, "selectedProfile": 0}


static func _mount(type: String, slots: Array, extra: Array = []) -> Dictionary:
	var s: Array = []
	for w: Variant in slots:
		s.append({"size": type, "weapon": _weapon(w) if w != null else null})
	var e: Array = []
	for w: Variant in extra:
		e.append({"size": "Auxiliary", "weapon": _weapon(w) if w != null else null})
	return {"mount_type": type, "lock": false, "slots": s, "extra": e, "bonus_effects": []}


## A License Level 2 pilot with an Everest and a Blackbeard, v2 layout.
static func v2_pilot() -> Dictionary:
	var everest := {"id": "m-everest", "name": "Old Faithful", "frame": "mf_standard_pattern_i_everest", "active": true,
		"active_loadout_index": 0, "loadouts": [{"id": "l1", "name": "Primary",
			"systems": [{"id": "ms_personalizations"}, {"id": "ms_custom_paint_job"}], "integratedSystems": [],
			"mounts": [_mount("Main", ["mw_assault_rifle"]), _mount("Flex", ["mw_pistol"], ["mw_pistol"]), _mount("Heavy", ["mw_heavy_machine_gun"])],
			"integratedMounts": [], "improved_armament": _mount("Flex", [null], [null]),
			"integratedWeapon": _mount("Aux", [null]), "superheavy_mounting": _mount("Superheavy", [null])}]}
	var homebrew := {"id": "m-x", "name": "Pack Mech", "frame": "mf_from_a_pack", "loadouts": [{"mounts": []}]}
	return {
		"id": "cc-1234", "level": 2, "callsign": "Bluebird", "name": "Ama Okafor", "player_name": "Sam",
		"background": "Soldier", "history": "<p>Grew up on a <b>colony</b> ship.</p>", "notes": "",
		"mechSkills": [1, 2, 0, 1],
		"skills": [{"id": "sk_apply_fists_to_faces", "rank": 2}, {"id": "sk_charm", "rank": 1}, {"id": "custom-1", "custom": true, "custom_desc": "Juggle"}],
		"talents": [{"id": "t_ace", "rank": 1}, {"id": "t_bonded", "rank": 1}],
		"licenses": [{"id": "mf_blackbeard", "rank": 2}],
		"core_bonuses": [], "reserves": [{"id": "reserve_skill", "name": "Skill Point"}],
		"loadout": {"armor": [{"id": "pg_assault_hardsuit"}], "weapons": [], "gear": [{"id": "pg_patch"}]},
		"mechs": [everest, homebrew], "state": {"active_mech_id": "m-everest"},
		"brews": [{"LcpName": "Some Homebrew", "LcpVersion": "1.0"}],
	}


func test_imports_a_v2_pilot() -> void:
	var db := MissionTest.db()
	var r := Compcon.import_pilot(JSON.stringify(v2_pilot()), db)
	expect(r["ok"], str(r["errors"]))
	var p: Dictionary = r["pilot"]
	expect_eq(p["callsign"], "Bluebird")
	expect_eq(p["ll"], 2)
	expect_eq([p["hull"], p["agility"], p["systems"], p["engineering"]], [1, 2, 0, 1])
	expect_eq(p["skills"], {"sk_apply_fists_to_faces": 2, "sk_charm": 1})
	expect_eq(p["talents"].get("t_ace"), 1)
	expect_eq(p["licenses"], {"mf_blackbeard": 2})
	expect_eq(p["history"], "Grew up on a colony ship.", "HTML stripped")
	expect_eq(p["pilot_gear"], ["pg_assault_hardsuit", "pg_patch"])
	expect_eq(p["mechs"].size(), 1, "the mech with an unknown frame is left out")
	var m: Dictionary = p["mechs"][0]
	expect_eq(m["name"], "Old Faithful")
	expect_eq(p["active_mech"], m["id"])
	expect_eq(m["loadout"]["mounts"][1]["weapons"], ["mw_pistol", "mw_pistol"], "Flex mount with two Auxiliary weapons")
	expect_eq(m["loadout"]["systems"], ["ms_personalizations", "ms_custom_paint_job"])
	var text := "\n".join(r["warnings"])
	expect(text.contains("Juggle"), "custom skill reported")
	expect(text.contains("mf_from_a_pack") and text.contains("Some Homebrew"), "unknown frame reported with the pack it may need")
	expect(text.contains("Pilot gear"), "pilot gear noted")
	expect(UnitFactory.check_loadout(db, m["frame"], m["loadout"], p).ok, "imported Everest is legal")


func test_imports_a_v3_save_pilot_export() -> void:
	var d := v2_pilot()
	d.erase("loadout")
	d["loadouts"] = [{"armor": [], "weapons": [{"id": "pg_heavy_pistol"}], "gear": []}]
	d["active_index"] = 0
	d["core_bonuses"] = [{"id": "cb_overpower_caliber", "name": "Overpower Caliber"}]
	d["favorite_mech"] = "m-everest"
	d.erase("state")
	var r := Compcon.import_pilot({"EXPORT_TYPE": "Save Pilot", "data": d}, MissionTest.db())
	expect(r["ok"], str(r["errors"]))
	expect_eq(r["pilot"]["core_bonuses"], ["cb_overpower_caliber"])
	expect_eq(r["pilot"]["pilot_gear"], ["pg_heavy_pistol"])
	expect_eq(r["pilot"]["active_mech"], r["pilot"]["mechs"][0]["id"])


func test_rejects_files_that_are_not_pilots() -> void:
	var db := MissionTest.db()
	var r := Compcon.import_pilot({"EXPORT_TYPE": "Save Encounter", "data": {}}, db)
	expect(not r["ok"] and r["errors"][0].contains("Save Encounter"))
	expect(not Compcon.import_pilot("{not json", db)["ok"])
	expect(not Compcon.import_pilot({"hello": 1}, db)["ok"])


func test_illegal_builds_import_with_clear_warnings() -> void:
	var d := v2_pilot()
	d["level"] = 0
	d["licenses"] = []
	d["mechs"][0]["loadouts"][0]["mounts"][2] = _mount("Heavy", ["mw_thermal_lance"])
	d["mechs"][0]["frame"] = "mf_blackbeard"
	var r := Compcon.import_pilot(d, MissionTest.db())
	expect(r["ok"], "still imported so it can be fixed in the builder")
	var text := "\n".join(r["warnings"])
	expect(text.contains("isn't legal"), text)
	expect(text.contains("license"), "says which license is missing: " + text)


func test_export_round_trips_through_import() -> void:
	var db := MissionTest.db()
	var p: Dictionary = Compcon.import_pilot(v2_pilot(), db)["pilot"]
	var exported := Compcon.export_pilot(p, db)
	expect_eq(exported["callsign"], "Bluebird")
	expect_eq(exported["level"], 2)
	expect_eq(exported["mechSkills"], [1, 2, 0, 1])
	var flex: Dictionary = exported["mechs"][0]["loadouts"][0]["mounts"][1]
	expect_eq(flex["slots"][0]["weapon"]["id"], "mw_pistol")
	expect_eq(flex["extra"][0]["weapon"]["id"], "mw_pistol", "second Auxiliary goes in COMP/CON's extra slot")
	var back: Dictionary = Compcon.import_pilot(JSON.stringify(exported), db)["pilot"]
	for key in ["callsign", "name", "ll", "hull", "agility", "systems", "engineering", "skills", "talents", "licenses", "core_bonuses", "pilot_gear", "reserves"]:
		expect_eq(back[key], p[key], key)
	expect_eq(back["mechs"].size(), p["mechs"].size())
	expect_eq(back["mechs"][0]["loadout"], p["mechs"][0]["loadout"])
	expect_eq(back["mechs"][0]["name"], p["mechs"][0]["name"])
