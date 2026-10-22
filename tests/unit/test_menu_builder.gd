extends TestCase
## Pilot and mech builder: live legality, blocked choices with reasons, point budgets.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _builder(ll: int = 0) -> BuilderModel:
	var c := Campaign.create("B", {"start_ll": ll})
	return BuilderModel.new(MissionTest.db(), c.new_pilot("Ama", "Bluebird"))


static func _find(options: Array, id: String) -> Dictionary:
	for o: Dictionary in options:
		if o["id"] == id:
			return o
	return {}


func test_starter_build_is_legal() -> void:
	var b := _builder()
	expect(b.is_legal(), str(b.problems()))
	expect_eq(b.budgets()["licenses"], {"used": 0, "max": 0})
	expect_eq(b.budgets()["talents"]["max"], 3)
	expect_eq(b.budgets()["skills"]["max"], 4)
	expect_eq(b.budgets()["hase"]["max"], 2)
	expect(b.sp()["used"] <= b.sp()["max"])


func test_ll0_blocks_licensed_frames_with_a_reason() -> void:
	var b := _builder()
	var bb := _find(b.frame_options(), "mf_blackbeard")
	expect(not bb.is_empty())
	expect(not bb["ok"])
	expect(bb["reason"].contains("license"), bb["reason"])
	var why := b.set_frame("mf_blackbeard")
	expect(why != "", "refused")
	expect_eq(b.mech()["frame"], Campaign.STARTER_FRAME, "nothing changed")
	expect(_find(b.frame_options(), "mf_standard_pattern_i_everest")["selected"])


func test_license_ranks_unlock_frames() -> void:
	var b := _builder(2)
	expect_eq(b.set_license("mf_blackbeard", 2), "")
	expect(_find(b.frame_options(), "mf_blackbeard")["ok"])
	expect_eq(b.set_frame("mf_blackbeard"), "")
	expect_eq(b.mech()["frame"], "mf_blackbeard")
	expect(b.set_license("mf_drake", 1) != "", "no license ranks left at LL2")
	expect(_find(b.license_options(), "mf_drake")["reason"].contains("License"))


func test_mount_choices_check_size_and_sp() -> void:
	var b := _builder()
	# Everest: Main, Flex, Heavy. A Heavy weapon doesn't fit the Main mount.
	var main := b.weapon_options(0, 0)
	var hmg := _find(main, "mw_heavy_machine_gun")
	expect(not hmg["ok"])
	expect(hmg["reason"].contains("fit"), hmg["reason"])
	expect(_find(main, "mw_assault_rifle")["selected"])
	expect(_find(main, "mw_shotgun")["ok"])
	expect_eq(b.set_weapon(0, 0, "mw_shotgun"), "")
	expect_eq(b.mounts()[0]["weapons"][0]["id"], "mw_shotgun")
	# Flex: two Auxiliary weapons are fine.
	expect_eq(b.set_weapon(1, 1, "mw_pistol"), "")
	expect_eq(b.mounts()[1]["weapons"].size(), 2)
	expect(b.set_weapon(1, 1, "mw_shotgun") != "", "Flex holds one Main or two Auxiliary")
	expect_eq(b.set_weapon(1, 1, ""), "", "emptying a slot is always fine")
	# Systems until the SP run out (Everest LL0: 6 SP).
	expect_eq(b.add_system("ms_pattern_a_smoke_charges"), "")
	expect(b.add_system("ms_pattern_a_smoke_charges").contains("Unique"), "Unique systems: one copy")
	expect_eq(b.add_system("ms_personalizations"), "")
	expect_eq(b.add_system("ms_type_3_projected_shield"), "")
	expect_eq(b.sp(), {"used": 5, "max": 6})
	var why := b.add_system("ms_pattern_b_hex_charges")
	expect(why.contains("SP"), why)
	expect(not _find(b.system_options(), "ms_pattern_b_hex_charges")["ok"])
	expect_eq(b.remove_system(0), "")
	expect_eq(b.add_system("ms_pattern_b_hex_charges"), "", "room again after removing one")
	expect(b.is_legal(), str(b.problems()))


func test_point_budgets() -> void:
	var b := _builder()
	expect_eq(b.set_talent("t_ace", 1), "")
	expect_eq(b.set_talent("t_bonded", 1), "")
	expect_eq(b.set_talent("t_brawler", 1), "")
	var why := b.set_talent("t_crack_shot", 1)
	expect(why.contains("Talents"), why)
	expect(not _find(b.talent_options(), "t_crack_shot")["ok"])
	expect_eq(b.set_skill("sk_charm", 2), "")
	expect_eq(b.set_skill("sk_blow_something_up", 2), "")
	expect(b.set_skill("sk_hack_or_fix", 1) != "", "4 skill points at LL0")
	expect_eq(b.set_hase("hull", 2), "")
	expect(b.set_hase("agility", 1) != "", "2 mech skill points at LL0")
	expect(b.toggle_core_bonus("cb_overpower_caliber") != "", "no core bonus before LL3")
	var b3 := _builder(3)
	expect_eq(b3.toggle_core_bonus("cb_overpower_caliber"), "", "GMS core bonus at LL3")
	var ipsn := ""
	for cb: Dictionary in MissionTest.db().all("core_bonuses"):
		if cb.get("source", "") == "IPS-N":
			ipsn = cb["id"]
	var b3b := _builder(3)
	expect(b3b.toggle_core_bonus(ipsn).contains("license ranks"), "manufacturer core bonuses need its license ranks")


func test_lowering_ll_shows_overspent_points() -> void:
	var b := _builder(2)
	b.set_license("mf_blackbeard", 2)
	expect_eq(b.set_ll(0), "", "you can always change the level")
	expect(not b.is_legal())
	expect(" ".join(b.problems()).contains("License"), str(b.problems()))
