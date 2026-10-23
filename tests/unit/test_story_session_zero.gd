extends TestCase
## Session zero's squad history (SessionZero.squad_history): made from the pilots' own
## backgrounds and origins, editable and rerollable; the question game is optional and folded.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func test_history_comes_from_who_the_pilots_are() -> void:
	var t := Setup.setup(780)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var world := str(Origin.data()["homeworld"][0]["id"])
	c.pilots[t["a"]]["origin"] = {"homeworld": world}
	c.pilots[t["b"]]["origin"] = {"homeworld": world}
	var lines := SessionZero.squad_history(s, c)
	expect(not lines.is_empty())
	expect_eq(str(lines[0]["kind"]), "homeworld", "two pilots from the same world know each other")
	expect(str(lines[0]["text"]).contains("Bluebird") and str(lines[0]["text"]).contains("Kettle"))
	# Nothing in common: they still met somehow, and everyone is in the story.
	var third := str(c.new_pilot("Joss Varga", "Dove")["id"])
	c.pilots[t["b"]]["origin"] = {}
	c.pilots[t["a"]]["origin"] = {}
	c.pilots[t["a"]]["background"] = ""
	c.pilots[t["b"]]["background"] = ""
	var all := SessionZero.squad_history(s, c, 3)
	for pid: String in [t["a"], t["b"], third]:
		expect(all.any(func(h: Dictionary) -> bool: return h["a"] == pid or h["b"] == pid), "%s is in the history" % pid)


func test_the_edited_history_is_what_the_story_keeps() -> void:
	var t := Setup.setup(781)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var r := e.submit(s, c, {"type": "session_zero", "seat": "gm", "params": {"identity": "Mercenaries", "patron": "company", "tone": "heroic", "focus": "balanced",
		"squad_history": [{"a": t["a"], "b": t["b"], "text": "Bluebird owes Kettle a ship."}]}})
	expect(r["ok"], str(r.get("reason", "")))
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "history_set" and str(x["text"]) == "Bluebird owes Kettle a ship."), "your words, as written")


func test_the_screen_leads_with_the_summary_and_folds_the_questions() -> void:
	var t := Setup.setup(782)
	var screen := SessionZeroScreen.new()
	screen.bind(t["engine"], t["story"], t["campaign"])
	expect(not screen._shared_rows.is_empty(), "a readable summary to edit")
	expect(not screen._questions.visible, "the question game is optional and folded away")
	var ch := screen.choices()
	expect(not (ch["squad_history"] as Array).is_empty())
	expect((ch["history"] as Array).is_empty(), "no questions unless you add them")
	var before := str((screen._shared_rows[0]["edit"] as LineEdit).text)
	screen._variant = 7
	screen._fill_shared()
	expect(not screen._shared_rows.is_empty(), "rerolled: %s" % before)
	screen.free()
