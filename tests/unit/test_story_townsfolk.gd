extends TestCase
## Every person you can talk to is worth talking to (Townsfolk): a story and something to offer,
## no two wanting the same job, memory of what you did, and talk that opens up over time.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _talkable(s: StoryState) -> Array:
	return (s.hub["npcs"] as Array).filter(func(id: String) -> bool: return not bool(s.npcs[id].get("dead", false)) and str(s.npcs[id].get("scene", "")) != "")


func test_everyone_has_a_story_and_something_to_offer() -> void:
	for seed_value: int in [840, 841, 842, 843]:
		var t := Setup.setup(seed_value)
		var s: StoryState = t["story"]
		var hooks := {}
		for id: String in _talkable(s):
			var npc: Dictionary = s.npcs[id]
			expect(str(npc.get("backstory", "")) != "", "%s has a backstory" % npc["name"])
			var offers := str(npc.get("want_hook", "")) != "" or str(npc.get("service", "")) != "" or not (npc.get("offers", []) as Array).is_empty()
			expect(offers, "%s can do something for you, or needs something done" % npc["name"])
			var h := str(npc.get("want_hook", ""))
			if h != "":
				expect(not hooks.has(h), "no two people in one town want the same job (%s)" % h)
				hooks[h] = true


func test_they_remember_you_and_open_up() -> void:
	var t := Setup.setup(845)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var who := Setup.npc_with_role(s, "local")
	if who == "":
		who = Setup.npc_with_role(s, "bartender")
	e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": who}})
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 10:
		guard += 1
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
	var first: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return str(o["id"]))
	expect(first.has("tf_about"), "the first time: who they are")
	expect(not first.has("tf_worry"), "what worries them comes later")
	var r := e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "tf_about"}})
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line" and str(x["text"]) == str(s.npcs[who]["backstory"]) or str(x.get("text", "")).begins_with(str(s.npcs[who]["backstory"]))), "they tell you")
	Dialogue.close(s)
	StoryEffects.apply({"trust": who, "add": 2}, s, c, {})
	e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": who}})
	var lines: Array = (s.dialogue.get("log", []) as Array).map(func(l: Dictionary) -> String: return str(l.get("text", "")))
	expect(lines.any(func(l: String) -> bool: return l.contains("stood by me")), "they remember what you did, and say so: %s" % [lines])
	guard = 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 10:
		guard += 1
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
	expect(Dialogue.offered(s).any(func(o: Dictionary) -> bool: return str(o["id"]) == "tf_worry"), "coming back, they open up")
	Dialogue.close(s)


func test_the_first_town_has_short_local_jobs() -> void:
	var t := Setup.setup(846)
	var s: StoryState = t["story"]
	var local: Array = s.hooks.filter(func(h: Dictionary) -> bool: return bool(h.get("local", false)) and str(h.get("travel", "")) == "walk")
	expect(local.size() >= 1, "a short job you can walk out to before the first big one")
