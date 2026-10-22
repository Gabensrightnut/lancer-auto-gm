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
	# Whatever the rules engine still leaves to the table must say so (the list shrinks as rules get automated).
	var manual: Array = list.filter(func(a: Dictionary) -> bool: return String(a.get("automation", "")) in ["manual", "partial"])
	for a: Dictionary in manual:
		expect(a.has("table") and String(a.get("table_note", "")) != "", "manual entry %s carries a table badge and note" % a.get("name", ""))
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


func test_destroyed_terrain_reaches_the_board() -> void:
	var view := BattleView.new()
	var rules_map := DemoMap.build_showcase(GridLayout.Shape.HEX)
	view.set_map(rules_map, "grassy_hills")
	expect(view.map != rules_map, "the board keeps its own copy")
	var hit: Array[Vector2i] = []
	for c in rules_map.cells():
		if rules_map.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE) and hit.size() < 3:
			rules_map.column(c).ground = 0  # the rules change their map in place
			hit.append(c)
	expect(not hit.is_empty(), "the showcase board has destructible terrain")
	var broke := view.refresh_map(rules_map)
	expect_eq(broke.size(), hit.size(), "lowered columns collapse on the board")
	expect_eq(view.map.ground_height(hit[0]), 0)
	expect(view.refresh_map(rules_map).is_empty(), "nothing changed: nothing happens")
	view.free()


func test_inputs_for_rider_and_cable_actions() -> void:
	var g := _gear_state()
	var u: Unit = g[3]
	for t: Array in [["climb_on", "host"], ["board", "mech"], ["disembark", "to"], ["cut_cable", "target"], ["use_object", "object"]]:
		var st := ActionInputs.steps(g[1], g[2], u, {"type": t[0], "params": {}})
		expect_eq(st.size(), 1, t[0])
		expect_eq(st[0]["param"], t[1], "%s picks %s" % [t[0], t[1]])
	expect(ActionInputs.steps(g[1], g[2], u, {"type": "ai_control", "params": {"take_back": false}}).is_empty(), "AI control needs no pick")


func test_weapon_mod_shows_on_the_card() -> void:
	var db := ContentDB.new()
	db.load_all()
	var s := F.state()
	var u := UnitFactory.build_mech(db, "me", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"], "mod": "wm_thermal_charge"}], "systems": []}, {"ll": 3})
	u.side = "players"
	u.cell = Vector2i(3, 3)
	s.add_unit(u)
	F.mech(s, "foe", "enemies", Vector2i(8, 3))
	var engine := RulesEngine.new()
	F.begin(engine, s, u)
	var weapon: Array = ActionCatalog.for_unit(s, engine, db, "me").filter(func(a: Dictionary) -> bool: return String(a.get("id", "")).begins_with("w:"))
	expect(not weapon.is_empty() and weapon[0].get("mod") is Dictionary, "the modded weapon carries its mod")
	expect_eq(String(weapon[0]["mod"]["name"]), "Thermal Charge")
	expect(String(weapon[0]["mod"]["text"]) != "", "with what it does")


func test_mission_objectives_follow_the_phase() -> void:
	var view := BattleView.new()
	view.set_map(BattleMap.flat(GridLayout.Shape.HEX, 10, 10), "grassy_hills")
	view.show_mission({"zones": {"zone_1": [[2, 2], [2, 3]], "true_zone": [[5, 5]], "_secret": [[6, 6]]},
		"deployment": {"players": [[1, 8]], "enemies": [[1, 1]]}}, GameState.PHASE_SETUP)
	var shown: Array = view.terrain.objectives
	expect_eq((shown[0] as Dictionary).keys(), ["zone_1"], "secret zones are never drawn")
	expect(bool(shown[2]), "deployment areas show during setup")
	view.set_phase(GameState.PHASE_COMBAT)
	expect(not bool(view.terrain.objectives[2]), "and go away once combat starts")
	view.free()


func test_out_of_range_reason_and_turn_bar_names() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 30, 6)
	var me := F.mech(s, "me", "players", Vector2i(1, 2))
	me.loadout["weapons"] = [F.weapon("gun", "Short Gun", "Main", "Rifle", "1d6", 5)]
	F.mech(s, "foe", "enemies", Vector2i(20, 2))
	var engine := RulesEngine.new()
	F.begin(engine, s, me)
	var db := ContentDB.new()
	db.load_all()
	var gun: Array = ActionCatalog.for_unit(s, engine, db, "me").filter(func(a: Dictionary) -> bool: return a.get("id") == "w:gun")
	expect(String(gun[0].get("reason", "")).begins_with("Out of range (19 > 5)"), "real distance and reach: %s" % gun[0].get("reason", ""))
	var bar := TurnOrderBar.new()
	bar.set_data({"units": [{"id": "x", "name": "Placeholder Controller", "side": "enemies"}], "round": 1})
	var labels := bar.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "Placeholder Controller")
	expect(not labels.is_empty() and (labels[0] as Label).text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long names end in an ellipsis")
	expect_eq((labels[0] as Label).tooltip_text, "Placeholder Controller", "full name on hover")
	bar.free()


func test_new_talent_actions_and_attack_options() -> void:
	var g := _gear_state()
	var u: Unit = g[3]
	for t: Array in [["feint", "target"], ["trip", "target"], ["duelist_strike", "target"], ["hunter_throw", "target"]]:
		var st := ActionInputs.steps(g[1], g[2], u, {"type": t[0], "params": {}})
		expect_eq(st[0]["param"], t[1], "%s picks %s" % [t[0], t[1]])
	var pinaka := {"id": "mw_pinaka_missiles", "type": "Launcher", "range": []}
	var keys := ActionCatalog.attack_options(u, pinaka).map(func(o: Dictionary) -> String: return o["key"])
	expect(keys.has("delayed"), "Pinaka offers a delayed strike")
	var pt := PlayerTurn.new()
	var ui := CanvasLayer.new()
	pt.bar = ActionBar.new()
	pt.setup(ui)
	pt.selected = {"name": "Pinaka", "options": ActionCatalog.attack_options(u, pinaka)}
	pt._ask("Fire?", {"type": "skirmish", "actor": "me", "params": {"weapon": "w"}})
	expect_eq(pt.pending["params"].get("delayed"), false, "options start at their defaults")
	pt.bar.free()
	pt.free()
	ui.free()


func test_gm_edits_reach_the_board() -> void:
	var view := BattleView.new()
	var rules_map := BattleMap.flat(GridLayout.Shape.HEX, 8, 8)
	view.set_map(rules_map, "grassy_hills")
	var ep := EventPlayer.new(view, null, null)
	Fx.speed = 0.0
	ep.on_map_changed = func() -> BattleMap: return rules_map
	ep.on_mission_view = func() -> Dictionary: return {"zones": {"zone_1": [[2, 2]]}, "deployment": {}}
	rules_map.column(Vector2i(3, 3)).ground = 2
	await ep.play_event({"type": "terrain_edited", "cells": [[3, 3, 2]]})
	expect_eq(view.map.ground_height(Vector2i(3, 3)), 2, "the edited column is on the board")
	await ep.play_event({"type": "objectives_changed"})
	expect_eq((view.terrain.objectives[0] as Dictionary).keys(), ["zone_1"], "objectives redrawn from the seat's view")
	Fx.speed = 1.0
	ep.free()
	view.free()


func test_terrain_hits_show_damage() -> void:
	var view := BattleView.new()
	view.set_map(DemoMap.build_showcase(GridLayout.Shape.HEX), "grassy_hills")
	var ep := EventPlayer.new(view, null, null)
	Fx.speed = 0.0
	await ep.play_event({"type": "terrain_damaged", "cell": [3, 3], "amount": 4, "damage_type": "Kinetic"})
	await ep.play_event({"type": "terrain_damaged", "cell": [3, 3], "amount": 3, "damage_type": "Kinetic"})
	expect_eq(int(view.terrain.damage.get("3,3", 0)), 7, "clients add up the hits they've seen")
	Fx.speed = 1.0
	ep.free()
	view.free()


func test_keybind_file_matches_the_code() -> void:
	var d := BattleKeys.defaults()
	for a: String in BattleKeys.ACTIONS:
		expect(d.has(a), "keybinds.json has %s" % a)
		expect_eq((d[a] as Array).slice(1), (BattleKeys.ACTIONS[a] as Array).slice(1), "%s keys match" % a)
