extends TestCase
## The battle hotbar: actions sort into the nine panels by book action type, every action
## gets a slot (none lost when panels shrink), the padlock stops dragging, hotkeys follow the
## slots, and slots are a readable size.

const SAMPLE := [
	{"id": "w:a", "kind": "attack", "cost": "quick", "group": "weapons", "name": "Assault Rifle"},
	{"id": "act_barrage", "kind": "barrage", "cost": "full", "group": "full", "name": "Barrage"},
	{"id": "ability:s1/a0", "kind": "pick", "cost": "quick", "group": "systems", "name": "Hunter Lock", "text": "Make an attack against a Locked On target."},
	{"id": "act_lock_on", "kind": "tech", "cost": "quick", "group": "tech", "name": "Lock On", "icon": "tech_quick"},
	{"id": "act_hide", "kind": "self", "cost": "quick", "group": "quick", "type": "hide", "name": "Hide"},
	{"id": "act_stabilize", "kind": "self", "cost": "full", "group": "full", "type": "stabilize", "name": "Stabilize"},
	{"id": "act_boost", "kind": "move_boost", "cost": "quick", "group": "quick", "name": "Boost"},
	{"id": "act_brace", "kind": "policy", "cost": "reaction", "group": "reactions", "name": "Brace"},
	{"id": "act_overcharge", "kind": "self", "cost": "free", "group": "quick", "name": "Overcharge"},
]


func _bar(pilot: String) -> ActionBar:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ActionBar.LAYOUT_DIR + pilot + ".json"))
	var b := ActionBar.new()
	b.set_actions(SAMPLE.duplicate(true), pilot)
	return b


func test_actions_sort_into_the_numpad_panels() -> void:
	var want := {"w:a": 1, "act_barrage": 2, "ability:s1/a0": 3, "act_lock_on": 6, "act_hide": 4, "act_stabilize": 5,
		"act_boost": 7, "act_brace": 8, "act_overcharge": 9}
	for a: Dictionary in SAMPLE:
		expect_eq(ActionBar.panel_of(a), want[a["id"]], String(a["name"]))
	var b := _bar("test_bar_sort")
	for a: Dictionary in SAMPLE:
		expect_eq(b.slot_of(a["id"])[0], want[a["id"]], "%s placed in its panel" % a["name"])
	b.free()


func test_slots_are_readable_and_hotkeys_follow_them() -> void:
	var b := _bar("test_bar_size")
	expect(b.slot_size() >= 56.0 and b.slot_size() <= 72.0, "about 60 px slots at 1080p (%.0f)" % b.slot_size())
	expect_eq(ActionBar.hotkey_label(0), "1")
	expect_eq(ActionBar.hotkey_label(9), "0")
	expect_eq(ActionBar.hotkey_label(10), "⇧1", "the second ten use Shift")
	expect_eq(String(b.hotkey_order()[0]["id"]), "w:a", "1 is the first slot of panel 1")
	b.free()


func test_moving_resizing_and_the_lock() -> void:
	var b := _bar("test_bar_move")
	expect(b.is_locked(), "locked by default")
	expect(not ActionButton.drag_enabled, "no dragging while locked")
	b.set_locked(false)
	expect(ActionButton.drag_enabled, "unlocked: drag and drop")
	b.move_action("act_hide", 1, 1)
	expect_eq(b.slot_of("act_hide"), [1, 1], "moved into panel 1")
	b.resize_panel(1, 0, -3)  # one column left: the second action must not be lost
	expect(b.slot_of("act_hide")[0] != 0 or (b.layout["overflow"] as Array).has("act_hide"), "never lost")
	b.reset_layout()
	expect_eq(b.slot_of("act_hide")[0], 4, "reset puts it back")
	b.set_locked(true)
	b.free()


func test_auto_toggle_is_for_repeatable_non_attacks() -> void:
	expect(AutoActions.can_auto({"id": "act_brace", "cost": "reaction", "group": "reactions", "kind": "policy"}) == "", "Brace can be auto")
	expect(AutoActions.can_auto({"id": "act_lock_on", "kind": "tech", "type": "lock_on", "cost": "quick", "icon": "tech_quick"}) == "", "Lock On can be auto")
	expect(AutoActions.can_auto({"id": "w:a", "kind": "attack", "cost": "quick"}) != "", "no weapon attacks")
	expect(AutoActions.can_auto({"id": "act_overwatch", "cost": "reaction", "group": "reactions"}) != "", "Overwatch attacks: no")
	expect(AutoActions.can_auto({"id": "act_invade", "kind": "tech", "type": "invade", "cost": "quick"}) != "", "no tech attacks")
	expect(AutoActions.can_auto({"id": "core", "group": "core"}) != "", "no Core Power")
	expect(AutoActions.can_auto({"id": "x", "kind": "self", "lockout": {"kind": "uses", "left": 1, "total": 2}}) != "", "no Limited gear")
	expect(AutoActions.can_auto({"id": "s", "kind": "attack", "sustain": {"effect": "e1"}}) == "", "sustaining an effect may be auto")
	expect_eq(AutoActions.reaction_answer({"reaction": "brace"}, {"act_brace": true}), {"take": true}, "auto-Brace answers the prompt")
	expect(AutoActions.reaction_answer({"reaction": "overwatch"}, {"act_overwatch": true}).is_empty(), "never auto-Overwatch")
	var plan := AutoActions.turn_plan([{"id": "a1", "kind": "self", "preview": {"heat": 3}}, {"id": "a2", "kind": "self", "preview": {"heat": 3}}],
		{"a1": true, "a2": true}, {"heat": [2, 6]})
	expect_eq(String(plan[0]["skip"]), "", "the first fits under the heat cap")
	expect_eq(String(plan[1]["skip"]), "would overheat", "the second would overheat: skipped, never forced")
	var b := _bar("test_bar_auto")
	b.toggle_auto(SAMPLE[7])  # Brace
	expect(bool(b.layout["auto"].get("act_brace", false)), "toggled on")
	b.toggle_auto(SAMPLE[0])  # a weapon: refused
	expect(not b.layout["auto"].has("w:a"), "attacks can't be toggled")
	b.toggle_auto(SAMPLE[7])
	expect(not b.layout["auto"].has("act_brace"), "and off again")
	b.free()


func test_group_buttons_open_sub_bars() -> void:
	var b := _bar("test_bar_groups")
	expect_eq(b.open_group, 0, "closed at first: just the nine group buttons")
	b.toggle_group(4)
	expect_eq(b.open_group, 4, "Quick actions open")
	expect((b._panels[4]["box"] as Panel).visible, "its sub-bar shows")
	b.toggle_group(7)
	expect_eq(b.open_group, 7, "another group swaps it")
	expect(not (b._panels[4]["box"] as Panel).visible, "the first one closes")
	b.toggle_group(7)
	expect_eq(b.open_group, 0, "clicking it again closes it")
	expect_eq(ActionBar.KEYPAD[KEY_KP_7], 1, "Kp7 is the top-left group, like the grid")
	expect_eq(ActionBar.slot_key_label(1, 0), "⇧1", "the second row of a sub-bar is Shift")
	expect_eq((b._groups[8] as ActionGroupButton).count, 1, "the Reactions button counts Brace")
	b.free()
