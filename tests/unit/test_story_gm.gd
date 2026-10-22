extends TestCase
## A human GM's story tools (GmTools): all StoryEngine actions from the gm seat.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _gm(t: Dictionary, type: String, params: Dictionary) -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": "gm", "params": params})


func test_only_the_gm_seat() -> void:
	var t := Setup.setup(200)
	for type: String in GmTools.ACTIONS:
		var r: Dictionary = t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": "p1", "params": {}})
		expect(not r["ok"] and str(r["reason"]).contains("GM"), "%s refused for a player" % type)


func test_a_scene_written_on_the_spot() -> void:
	var t := Setup.setup(201)
	var s: StoryState = t["story"]
	var bar := Setup.npc_with_role(s, "bartender")
	var faction := str(s.npcs[bar]["faction"])
	var before := s.get_standing(faction)
	var scene := {"npc": bar, "lines": [{"who": "npc", "text": "You're the ones who blew up the depot.", "expression": "angry"}, {"who": "narrator", "text": "The room goes quiet."}],
		"choices": [{"text": "That was us.", "reply": "Then drinks are on the house.", "effects": [{"standing": "$npc.faction", "add": 1}]},
			{"text": "Never heard of it."}, {"text": "Who's asking?"}, {"text": "We should go."}]}
	expect(not _gm(t, "gm_scene", {"npc": bar, "lines": [{"who": "npc", "text": "Hi"}], "choices": [{"text": "x", "effects": [{"explode": true}]}]})["ok"], "unknown effects are refused")
	expect(not _gm(t, "gm_scene", {"lines": [{"who": "npc", "text": "Hi"}]})["ok"], "NPC lines need an NPC")
	var r := _gm(t, "gm_scene", scene)
	expect(r["ok"], str(r["reason"]))
	var said: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line")
	expect(not said.is_empty() and str(said[0]["text"]) == "You're the ones who blew up the depot." and str(said[0]["expression"]) == "angry")
	t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
	expect_eq(Dialogue.offered(s).size(), 4, "four replies")
	# A client mirrors the scene from the view (it works online).
	var mirror := StoryView.mirror(StoryView.view_for(s, t["campaign"], "p2"))
	expect_eq(Dialogue.offered(mirror["story"]).size(), 4, "the client sees the same replies")
	r = t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "c0"}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(s.get_standing(faction), before + 1, "the reply's effect")
	t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
	expect(not Dialogue.is_open(s))
	r = _gm(t, "gm_scene", {"id": "gm_0"})
	expect(r["ok"] and Dialogue.is_open(s), "a saved scene can be played again")


func test_twists_standing_reserves() -> void:
	var t := Setup.setup(202)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook: Dictionary = s.hooks[0]
	expect(_gm(t, "gm_twist", {"hook": hook["id"], "do": "set", "reveal": "The convoy is empty.", "question": "Who's lying?"})["ok"])
	var view := StoryView.view_for(s, c, "p1")
	for h: Dictionary in view["story"]["hooks"]:
		expect(not h.has("twist"), "players never see a hidden twist")
	var r := _gm(t, "gm_twist", {"hook": hook["id"], "do": "reveal"})
	var ev: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "twist_revealed")
	expect(not ev.is_empty() and str(ev[0]["twist"]["reveal"]) == "The convoy is empty.", "revealed to everyone")
	expect(not s.hooks[0].has("twist"), "and not again at the debrief")
	expect(_gm(t, "gm_standing", {"faction": "The Iron Tithe", "set": -2})["ok"])
	expect_eq(s.get_standing("The Iron Tithe"), -2)
	expect(not _gm(t, "gm_reserve", {"pilot": t["a"], "reserve": "reserve_nonsense"})["ok"], "a real book reserve, or a named custom one")
	expect(_gm(t, "gm_reserve", {"pilot": t["a"], "reserve": "reserve_extra_repairs"})["ok"])
	expect(_gm(t, "gm_reserve", {"pilot": "squad", "reserve": "custom", "name": "A local guide"})["ok"])
	expect_eq((s.reserves[t["a"]] as Array).size(), 2)
	expect(_gm(t, "gm_reserve", {"pilot": t["a"], "remove": 0})["ok"])
	expect_eq((s.reserves[t["a"]] as Array).size(), 1, "taken back")
	expect(not (c.pilots[t["a"]]["reserves"] as Array).has("reserve_extra_repairs"))


func test_jobs_briefings_commanders_and_npcs() -> void:
	var t := Setup.setup(203)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	t["engine"].db = MissionTest.db()
	var n := s.hooks.size()
	var r := _gm(t, "gm_job", {"template": "clear_raiders", "title": "The Bridge at Dawn"})
	expect(r["ok"] and s.hooks.size() == n + 1 and str(s.hooks[-1]["title"]) == "The Bridge at Dawn", "a side job from the GM")
	var hook: Dictionary = s.hooks[-1]
	expect(_gm(t, "gm_edit_job", {"hook": hook["id"], "set": {"stakes": "If the bridge falls, the town starves.", "briefing": ["Listen close.", "The bridge falls at dawn unless you hold it."],
		"commander": {"new": {"callsign": "Hollow", "rank": "Captain", "personality": "honorable"}}}})["ok"])
	expect_eq(str(hook["commander"]["name"]), "Captain Hollow")
	r = t["engine"].submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	var said: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line").map(func(x: Dictionary) -> String: return x["text"])
	expect_eq(said, ["Listen close."], "the GM's briefing, not the generated one")
	expect(not _gm(t, "gm_edit_job", {"hook": hook["id"], "set": {"briefing": ["Too late."]}})["ok"], "a briefing already given can't change")
	Dialogue.close(s)
	t["engine"].submit(s, c, {"type": "confirm_reserves", "seat": "gm"})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var lead: Unit = (gen["state"] as GameState).unit(str(Rivals.battle(s)["unit"]))
	expect(lead.name.begins_with("Hollow"), "the GM's commander leads the enemy: %s" % lead.name)
	expect(not _gm(t, "gm_remove_job", {"hook": hook["id"]})["ok"], "not mid-mission")
	r = _gm(t, "gm_npc", {"new": {"role": "local", "name": "Old Ines", "title": "Ferry keeper", "secret": "Smuggles for both sides."}})
	expect(r["ok"], str(r["reason"]))
	var id := str(r["events"][0]["npc"])
	expect(str(s.npcs[id]["name"]) == "Old Ines" and (s.hub["npcs"] as Array).has(id), "a new person at the hub")
	expect(not StoryView.view_for(s, c, "p1")["story"]["npcs"][id].has("secret"), "their secret stays with the GM")
	expect(_gm(t, "gm_npc", {"npc": id, "set": {"personality": "gruff", "title": "Harbor master"}})["ok"])
	expect_eq(str(s.npcs[id]["title"]), "Harbor master")
