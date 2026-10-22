extends TestCase
## Pilot origins (Origin): a richer background for the book's +1 Accuracy (Core p.20).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func test_an_origin_widens_the_background_but_never_stacks() -> void:
	var t := Setup.setup(260)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var origin := {"homeworld": "city", "upbringing": "street", "employer": "ssc", "specialty": "hacker", "perks": ["netrunner", "weak_spots"]}
	expect(not t["engine"].submit(s, c, {"type": "set_origin", "seat": "p1", "params": {"pilot": t["a"], "origin": {"homeworld": "nowhere"}}})["ok"], "unknown parts are refused")
	expect(not t["engine"].submit(s, c, {"type": "set_origin", "seat": "p1", "params": {"pilot": t["a"], "origin": {"employer": "none", "perks": ["weak_spots"]}}})["ok"], "weak spots need a former employer")
	var r: Dictionary = t["engine"].submit(s, c, {"type": "set_origin", "seat": "p1", "params": {"pilot": t["a"], "origin": origin}})
	expect(r["ok"], str(r["reason"]))
	var p: Dictionary = c.pilots[t["a"]]
	expect(Origin.tags(p).has("ssc") and Origin.tags(p).has("omninet"), "Smith-Shimano and the omninet count as relevant")
	expect_eq(NarrativeCheck.background_invoke(p, ["ssc", "tech", "streets"], []), 1, "still +1 at most, as the book says")
	expect_eq(Origin.combat_perks(p)[0]["manufacturer"], "SSC", "the combat perk names the manufacturer, for the rules engine's house rule")
	expect(not p.has("ll_bonus") and int(p.get("ll", 0)) == 0, "no License Levels from an origin")
	expect(Origin.describe(p).contains("ex-Smith-Shimano"), Origin.describe(p))
