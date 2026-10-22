extends TestCase
## Resource HUD warnings and action buttons from plain data.


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


func test_action_buttons_built_and_greyed() -> void:
	var bar := ActionBar.new()
	bar.set_actions([
		{"id": "a", "name": "Skirmish", "cost": "quick", "desc": "Attack", "enabled": true},
		{"id": "b", "name": "Barrage", "cost": "full", "enabled": false, "reason": "No Full action left"},
	])
	expect_eq(bar._buttons.size(), 2)
	expect(not (bar._buttons["a"] as Button).disabled)
	expect((bar._buttons["b"] as Button).disabled)
	bar.free()
