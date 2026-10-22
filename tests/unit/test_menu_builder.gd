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


# --- Leveling up (Core p.18) and core bonuses (p.35) ---------------------------------------

static func _maker_bonuses(src: String) -> Array:
	var out: Array = []
	for cb: Dictionary in MissionTest.db().all("core_bonuses"):
		if cb.get("source", "") == src:
			out.append(cb["id"])
	return out


## A campaign pilot at `ll` who spent points, then leveled up once.
func _leveled(ll: int, setup: Callable) -> Array:
	var c := Campaign.create("Lv", {"start_ll": ll})
	var p := c.new_pilot("Ama", "Bluebird")
	var b := BuilderModel.new(MissionTest.db(), p)
	setup.call(b)
	c.pilots[p["id"]] = b.pilot
	c.level_up(p["id"])
	return [c, BuilderModel.new(MissionTest.db(), c.pilots[p["id"]])]


func test_spent_points_stay_spent_after_leveling() -> void:
	var r := _leveled(0, func(b: BuilderModel) -> void:
		b.set_talent("t_ace", 2)
		b.set_skill("sk_charm", 2))
	var b: BuilderModel = r[1]
	expect_eq(b.ll(), 1)
	expect(b.can_reallocate(), "one reallocation at the level up")
	var why := b.set_talent("t_ace", 1)
	expect(why.contains("stay spent"), why)
	expect(b.set_skill("sk_charm", 1).contains("stay spent"), "skill points too")
	expect_eq(b.set_talent("t_ace", 3), "", "new points can be spent")


func test_reallocate_a_talent_once() -> void:
	var r := _leveled(0, func(b: BuilderModel) -> void: b.set_talent("t_ace", 2))
	var b: BuilderModel = r[1]
	expect(b.reallocate("talent", "t_ace", "t_ace").contains("doesn't have"), "must move to a new talent")
	expect_eq(b.reallocate("talent", "t_ace", "t_brawler"), "")
	expect(not b.pilot["talents"].has("t_ace"))
	expect_eq(b.pilot["talents"]["t_brawler"], 2, "all the ranks moved")
	expect(b.is_legal(), str(b.problems()))
	expect(not b.can_reallocate())
	expect(b.reallocate("talent", "t_brawler", "t_ace").contains("once"), "only once per level")


func test_license_move_that_breaks_a_core_bonus_forces_a_replacement() -> void:
	var ipsn := _maker_bonuses("IPS-N")
	var r := _leveled(3, func(b: BuilderModel) -> void:
		expect_eq(b.set_license("mf_blackbeard", 3), "")
		expect_eq(b.toggle_core_bonus(ipsn[0]), "", "3 IPS-N ranks: first IPS-N bonus"))
	var b: BuilderModel = r[1]
	expect_eq(b.reallocate("license", "mf_blackbeard", "mf_everest_does_not_exist").begins_with("Unknown"), true)
	expect_eq(b.reallocate("license", "mf_blackbeard", "mf_genghis"), "", "moving the ranks is allowed")
	var problems := " ".join(b.problems())
	expect(problems.contains("core bonus"), "the IPS-N bonus no longer qualifies: " + problems)
	expect_eq(b.toggle_core_bonus(ipsn[0]), "", "so it can be dropped")
	var gms := _maker_bonuses("GMS")
	expect_eq(b.toggle_core_bonus(gms[0]), "", "and replaced")
	expect(b.is_legal(), str(b.problems()))


func test_swap_a_core_bonus() -> void:
	var gms := _maker_bonuses("GMS")
	var r := _leveled(3, func(b: BuilderModel) -> void: b.toggle_core_bonus(gms[0]))
	var b: BuilderModel = r[1]
	expect(b.toggle_core_bonus(gms[0]).contains("swap"), "can't just drop an earlier core bonus")
	expect_eq(b.reallocate("core_bonus", gms[0], gms[1]), "")
	expect_eq(b.pilot["core_bonuses"], [gms[1]])
	expect(b.is_legal(), str(b.problems()))


func test_manufacturer_core_bonuses_need_three_more_ranks_each() -> void:
	var ipsn := _maker_bonuses("IPS-N")
	var b := _builder(6)
	expect_eq(b.set_license("mf_blackbeard", 3), "")
	expect_eq(b.toggle_core_bonus(ipsn[0]), "", "3 ranks: 1st IPS-N bonus")
	var why := b.toggle_core_bonus(ipsn[1])
	expect(why.contains("6 IPS-N license ranks"), why)
	expect_eq(b.set_license("mf_drake", 3), "", "ranks can be spread over any IPS-N licenses")
	expect_eq(b.toggle_core_bonus(ipsn[1]), "", "6 ranks: 2nd IPS-N bonus")


func test_automation_report_for_the_build() -> void:
	var b := _builder()
	var report := b.automation()
	expect(not report.is_empty(), "the Everest's traits and core system are listed")
	var kinds := report.map(func(e: Dictionary) -> String: return str(e["kind"]))
	expect(kinds.has("trait") and kinds.has("core"), str(kinds))
	for e: Dictionary in report:
		expect(e["status"] in ["automated", "partial", "manual"], str(e))
		expect(str(e["name"]) != "")
		if e["status"] != "automated":
			expect(str(e["guidance"]) != "", "what to do at the table: %s" % str(e))


func test_new_pilots_get_a_look_and_picks_left_count_down() -> void:
	var b := _builder(1)
	expect(b.pilot.get("portrait") is Dictionary and not (b.pilot["portrait"] as Dictionary).is_empty(), "a starting portrait for the look creator")
	expect_eq(b.picks_left(), {"talent": 4, "license": 1, "core_bonus": 0}, "LL1, nothing spent: 3 + 1 talent ranks and 1 license rank")
	expect_eq(b.set_license("mf_blackbeard", 1), "")
	expect_eq(b.picks_left()["license"], 0, "spent in the builder")
