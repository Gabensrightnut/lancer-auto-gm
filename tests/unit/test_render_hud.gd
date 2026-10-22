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


func test_reaction_prompt_offers_choices() -> void:
	var s := F.state()
	var monarch := F.mech(s, "m", "players", Vector2i(1, 1))
	monarch.name = "Monarch"
	var a := F.mech(s, "a", "enemies", Vector2i(5, 1))
	a.name = "Goblin"
	var b := F.mech(s, "b", "enemies", Vector2i(6, 3))
	b.name = "Sherman"
	var rp := ReactionPrompt.new()
	var got: Array = []
	var ask := func(p: Dictionary) -> void: got.append(await rp.ask(s, p))
	ask.call({"unit": "m", "reaction": "avenger_silos", "context": {"targets": ["a", "b"], "suggested": {"take": true, "target": "b"}}})
	expect_eq(rp._buttons.get_child_count(), 3, "one button per target and Hold fire")
	expect(String((rp._buttons.get_child(1) as Button).text).contains("suggested"), "the engine's pick is marked")
	expect_eq(rp._picking, "unit", "clicking a unit on the board answers too")
	(rp._buttons.get_child(0) as Button).pressed.emit()
	expect_eq(got[0], {"take": true, "target": "a"})
	ask.call({"unit": "a", "reaction": "reactive_code", "context": {"attacker": "m", "options": ["lock_on", "invade"], "suggested": {"take": true, "action": "lock_on"}}})
	expect_eq(rp._buttons.get_child_count(), 3, "an action per option and Don't")
	(rp._buttons.get_child(1) as Button).pressed.emit()
	expect_eq(got[1], {"take": true, "action": "invade"})
	ask.call({"unit": "a", "reaction": "tactical_simulation", "context": {"attacker": "m", "target": "b", "suggested": {"take": true}}})
	expect_eq(rp._picking, "cell", "a space is picked on the board")
	(rp._buttons.get_child(0) as Button).pressed.emit()
	expect_eq(got[2], {"take": true})
	rp.free()


func _gear_state() -> Array:
	var db := ContentDB.new()
	db.load_all()
	var s := F.state()
	var u := UnitFactory.build_mech(db, "me", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}],
		"systems": ["ms_pattern_a_smoke_charges", "ms_javelin_rockets", "ms_caltrop_launcher", "ms_comp_con_class_assistant_unit"]}, {"ll": 3})
	u.side = "players"
	u.cell = Vector2i(3, 3)
	s.add_unit(u)
	var foe := F.mech(s, "foe", "enemies", Vector2i(8, 3))
	foe.name = "Foe"
	var engine := RulesEngine.new()
	F.begin(engine, s, u)
	return [db, s, engine, u]


func test_catalog_lists_systems_with_table_badges() -> void:
	var g := _gear_state()
	var list := ActionCatalog.for_unit(g[1], g[2], g[0], "me")
	var names := list.map(func(a: Dictionary) -> String: return String(a.get("name", "")))
	expect(names.any(func(n: String) -> bool: return n.contains("Smoke Grenade")), "system abilities are listed")
	expect(names.any(func(n: String) -> bool: return n.contains("Javelin")), "Javelin Rockets are listed")
	var comp: Array = list.filter(func(a: Dictionary) -> bool: return String(a.get("name", "")).contains("COMP/CON"))
	expect(not comp.is_empty() and comp[0].has("table") and String(comp[0].get("table_note", "")) != "", "manual entries carry a table badge and note")
	var more: Array = list.filter(func(a: Dictionary) -> bool: return a.get("type", "") == "self_destruct")
	expect(not more.is_empty() and more[0]["group"] == "more", "situational actions go to the More tab")


func test_action_inputs_for_gear() -> void:
	var g := _gear_state()
	var s: GameState = g[1]
	var u: Unit = g[3]
	var by_name := {}
	for a: Dictionary in ActionCatalog.for_unit(s, g[2], g[0], "me"):
		by_name[String(a.get("name", ""))] = a
	var smoke: Dictionary = by_name.get("Smoke Grenade", {})
	var st := ActionInputs.steps(s, g[2], u, smoke)
	expect_eq(st.size(), 1)
	expect_eq(st[0]["param"], "aim", "a grenade is aimed at a space")
	expect(int(st[0].get("area", 0)) > 0, "with its blast previewed")
	var jav := ActionInputs.steps(s, g[2], u, by_name.get("Javelin Rockets", {}))
	expect_eq(jav[0]["param"], "spaces")
	expect_eq(int(jav[0]["count"]), 3, "three spaces")
	var dep := ActionInputs.steps(s, g[2], u, by_name.get("Deploy Caltrop Field", {}))
	expect_eq(dep[0]["param"], "to", "deployables are placed on a space")
	expect_eq(ActionInputs.value_of({"count": 1}, [[4, 2]]), [4, 2])
	expect_eq(ActionInputs.value_of({"count": 4, "pairs": true}, [[1, 1], [1, 2], [3, 3], [3, 4]]), [[[1, 1], [1, 2]], [[3, 3], [3, 4]]])
	var smoke_act := {"type": smoke["type"], "actor": "me", "params": (smoke["params"] as Dictionary).merged({"aim": [5, 3]})}
	expect((g[2] as RulesEngine).validate(s, smoke_act).ok, "the picked aim makes a legal action")
