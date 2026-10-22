extends TestCase
## Resource HUD warnings, action bar buttons and lockouts, and the action catalog on the
## real rules engine.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _hud(heat: int) -> ResourceHUD:
	var hud := ResourceHUD.new()
	hud.set_data({"name": "T", "heat": [heat, 6], "danger_zone": 3, "economy": {"quick": [2, 2]}})
	return hud


func test_heat_preview_warnings() -> void:
	var hud := _hud(2)
	hud.set_preview({"heat": [1, 3]})
	expect("DANGER ZONE" in hud._warning(), "2 + up to 3 reaches the Danger Zone at 3")
	hud.set_preview({"heat": 5})
	expect("OVERHEAT" in hud._warning(), "2 + 5 is over the cap of 6")
	hud.set_preview({"quick": 1})
	expect_eq(hud._warning(), "")
	hud.free()
	var hot := _hud(4)
	hot.set_preview({"heat": 1})
	expect_eq(hot._warning(), "", "already in the Danger Zone: no new warning")
	hot.free()


func test_action_buttons_built_and_locked() -> void:
	var bar := ActionBar.new()
	bar.set_actions([
		{"id": "a", "name": "Skirmish", "cost": "quick", "group": "weapons", "enabled": true},
		{"id": "b", "name": "Barrage", "cost": "full", "group": "full", "enabled": false, "reason": "No Full action left"},
	], "test_pilot_unsaved")
	expect_eq(bar._buttons.size(), 2)
	expect(not ActionButton.locked((bar._buttons["a"] as ActionButton).action))
	expect(ActionButton.locked((bar._buttons["b"] as ActionButton).action))
	bar.free()


func test_lockout_sweep_shrinks_with_turns_left() -> void:
	expect_eq(ActionButton.lock_fraction({"enabled": true}), 0.0)
	expect_eq(ActionButton.lock_fraction({"enabled": false, "lockout": {"kind": "turns", "left": 1, "total": 2}}), 0.5)
	expect_eq(ActionButton.lock_fraction({"enabled": false, "lockout": {"kind": "loading"}}), 1.0, "no fixed length: fully grey")
	expect_eq(ActionButton.lock_fraction({"enabled": false, "lockout": {"kind": "recharge", "target": 5}}), 1.0)


func test_catalog_uses_rules_for_availability() -> void:
	var db := ContentDB.new()
	db.load_all()
	var s := F.state()
	var e := RulesEngine.new()
	var a := UnitFactory.build_mech(db, "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}]})
	a.side = "players"
	a.cell = Vector2i(0, 0)
	s.add_unit(a)
	var t := F.mech(s, "t", "enemies", Vector2i(3, 0))
	F.begin(e, s, a)
	var list := ActionCatalog.for_unit(s, e, db, "a")
	var rifle: Dictionary = {}
	var barrage: Dictionary = {}
	for x: Dictionary in list:
		if x.get("weapon") == "0:0":
			rifle = x
		if x.get("id") == "act_barrage":
			barrage = x
	expect(not rifle.is_empty() and rifle.get("enabled", false), "rifle can shoot the enemy 3 spaces away")
	expect(barrage.get("enabled", false), "barrage available before any quick action")
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	for x: Dictionary in ActionCatalog.for_unit(s, e, db, "a"):
		if x.get("id") == "act_barrage":
			expect(not x.get("enabled", true), "full action blocked after a quick action")
			expect(String(x.get("reason", "")) != "", "says why")
	var o := ActionCatalog.attack_outcome(s, "a", "0:0", "t")
	expect(o.has("hit_chance") and float(o["hit_chance"]) > 0.0, "hit chance from the rules")


func test_heat_warning_text() -> void:
	var u := Unit.new()
	u.heat = 5
	u.heat_cap = 6
	var w := ActionCatalog.heat_warnings(u, 1, 3)
	expect(not w.is_empty() and "overheat" in String(w[0]["text"]), "5 + up to 3 can overheat a cap of 6")
