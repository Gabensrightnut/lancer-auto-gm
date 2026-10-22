extends TestCase
## Inside the hubs' buildings (HubInterior over world's Interiors kit): rooms mapped onto
## TownLife's, people where their day puts them, things where they're kept, locks that hold
## until the squad picks or forces them, the Saint Cadence's deck and the sleeper vault.

const Main := preload("res://tests/unit/test_story_main_campaign.gd")
const DR := preload("res://tests/unit/test_story_dead_reckoning.gd")


func _door_between(p: Dictionary, a: String, b: String) -> Dictionary:
	for d: Dictionary in p["doors"]:
		if (d["rooms"] as Array).has(a) and (d["rooms"] as Array).has(b):
			return d
	return {}


func _npc_in(p: Dictionary, id: String) -> Dictionary:
	for n: Dictionary in p["npcs"]:
		if str(n["id"]) == id:
			return n
	return {}


func test_the_saloon_matches_the_story() -> void:
	var t := Main.fresh(600)
	var s: StoryState = t["story"]
	var e: StoryEngine = t["engine"]
	var c: Campaign = t["campaign"]
	var p := HubInterior.plan(s, "bar")
	expect_eq(str(p["kind"]), "bar")
	expect_eq(str(p["entry"]), "main", "the front door opens on the bar room")
	expect_eq(p["rooms"]["main"], ["bar", "main"])
	expect_eq(p["rooms"]["owner"], ["bar", "upstairs"], "the owner's room is part of the rooms upstairs")
	# Ione's key-codes sit in her chest upstairs, which is locked.
	var codes: Array = (p["items"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) == "la_codes")
	expect(not codes.is_empty() and str(codes[0]["container"]) == "owner_chest", "in the owner's chest")
	var door := _door_between(p, "landing", "upstairs")
	expect(bool(door.get("locked", false)), "the door to the rooms upstairs is locked")
	expect_eq(HubInterior.step_action(s, p, "landing", "upstairs", door, false), "locked")
	# By day Ione's behind her bar; at night she's asleep upstairs.
	expect_eq(str(_npc_in(p, "cs_ione").get("room", "")), "main")
	for i in range(3):
		if TownLife.period(s) == "night":
			break
		e.submit(s, c, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	HubInterior.refresh(s, p)
	var ione := _npc_in(p, "cs_ione")
	expect(bool(ione.get("asleep", false)) and (p["rooms"][str(ione["room"])] as Array) == ["bar", "upstairs"], "asleep upstairs at night")
	# Pick the lock (the same TownLife action as outside), and the door is open to you.
	var opened := false
	for i in range(12):
		e.submit(s, c, {"type": "pick_lock", "seat": "gm", "params": {"pilot": t["a"], "spot": "bar", "room": "upstairs"}})
		if TownLife.is_open(s, "bar", "upstairs"):
			opened = true
			break
	expect(opened)
	HubInterior.refresh(s, p)
	door = _door_between(p, "landing", "upstairs")
	expect(not bool(door["locked"]), "picked")
	expect_eq(HubInterior.step_action(s, p, "landing", "upstairs", door, true), "sneak", "sneaking in")
	expect_eq(HubInterior.step_action(s, p, "upstairs", "room_1", _door_between(p, "upstairs", "room_1"), true), "", "the rooms off the corridor are the same story room")


func test_an_old_west_office_is_the_marshals() -> void:
	var t := Main.fresh(601)
	var p := HubInterior.plan(t["story"], "office")
	expect_eq(str(p["kind"]), "marshal", "Redwater's office has cells")
	expect_eq(p["rooms"]["cell_1"], ["office", "back"])


func test_the_cadence_is_one_deck() -> void:
	var t := DR.fresh(602)
	var s: StoryState = t["story"]
	for pk: int in [0, 0, 0]:
		DR.play_chapter(t, pk)
	var p := HubInterior.plan(s, "office")
	expect_eq(str(p["kind"]), "ship_deck")
	expect_eq(p["rooms"]["bridge"], ["office", "front"])
	expect_eq(p["rooms"]["engineering"], ["printer", "floor"])
	var via_mess := HubInterior.plan(s, "bar")
	expect_eq(str(via_mess["kind"]), "ship_deck", "the mess's door opens on the same deck")
	var ledger: Array = (p["items"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) == "dr_ledger")
	expect(not ledger.is_empty() and str(ledger[0]["room"]) == "captain", "Hask's ledger is in the captain's quarters")
	expect(bool(_door_between(p, "corridor", "captain").get("locked", false)), "and the quarters are locked")
	expect(not bool(_door_between(p, "corridor", "bridge").get("locked", true)), "the bridge isn't, by day")
	var governor: Array = (p["items"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) == "dr_governor")
	expect(not governor.is_empty() and str(governor[0]["room"]) == "engineering", "the reactor key is down in engineering")
	expect(not _npc_in(p, "cs_wen").is_empty(), "Wen Lazaro runs the mess (the deck's commons)")


func test_the_long_arrivals_dock_has_the_vault() -> void:
	var t := Main.fresh(603)
	var s: StoryState = t["story"]
	for pk: int in [0, 0, 0]:
		Main.play_chapter(t, pk)
	expect_eq(str(CampaignScript.state(s)["chapter"]), "c4_wake")
	var p := HubInterior.plan(s, "market")
	expect_eq(str(p["kind"]), "sleeper_vault")
	expect_eq(TownLife.room_name(s, "market", "floor"), "the vault")


func test_walking_through_the_saloon() -> void:
	var t := Main.fresh(604)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hub := HubScene.new()
	hub.setup(t["engine"], s, c, MissionTest_db())
	expect(hub.enter_building("bar"), "in through the front door")
	expect_eq(str(TownLife.pilot_at(s, t["a"])["room"]), "main", "the story knows you're in the bar room")
	var me: PilotFigure = hub.avatars["p1"]
	expect(me.get_parent() == hub._interior, "the squad is inside")
	# Walk to the back room's door: it's locked, so you stop there.
	var d := _door_between(hub._inside, "main", "back")
	var goal := Vector3(float(d["pos"][0]), 0, float(d["pos"][2]))
	var back_c := hub._room_center("back")
	for i in range(80):
		var to := (goal.lerp(back_c, 0.8 if i > 40 else 0.0) - me.position)
		to.y = 0
		hub._move(me, to.normalized() * 0.15)
	expect(hub._iroom == "main" and me.position.z > -1.4, "the back room stays shut")
	expect(me.position.distance_to(goal) < 1.0, "you walked up to its door")
	hub._update_near_thing(me)
	expect_eq(str(hub._near_thing.get("kind", "")), "door", "the prompt offers to pick the lock")
	hub.leave_building()
	expect(hub._inside.is_empty() and hub._world.visible, "back out in the street")
	expect_eq(str(TownLife.pilot_at(s, t["a"])["spot"]), "plaza")
	hub.free()


static func MissionTest_db() -> ContentDB:
	return preload("res://tests/unit/test_gm_mission.gd").db()
