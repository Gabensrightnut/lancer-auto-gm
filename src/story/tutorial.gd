class_name Tutorial
extends RefCounted
## The guided first campaign opening (DESIGN.md section 8), from data/game/story/tutorial.json:
## a briefing at a training base, a live-fire drill that teaches one thing at a time, then the
## debrief, level up and a first downtime. Lessons run in order; each pops up when its topic
## first comes up and is done when the pilot does it. Tips explain a rule the first time it
## happens (only while teaching hints are on: campaign.options.teaching_hints, default on).
##
## Story events are watched automatically (StoryEngine.submit). The battle screen passes its
## events in: `Tutorial.observe_battle(story, campaign, events, my_unit_ids)`; both return
## `tutorial_prompt` events {kind: "lesson"/"tip", id, title, text, objective, rule_ref, step, of}.

const FILE := "res://data/game/story/tutorial.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"lessons": [], "tips": []}
	return _data


static func active(story: StoryState) -> bool:
	return bool(story.tutorial.get("active", false))


static func lessons() -> Array:
	return data().get("lessons", [])


static func start(story: StoryState) -> Array:
	story.tutorial = {"active": true, "step": 0, "shown": false, "turns": 0, "tips": []}
	return _show_if_ready(story, [])


static func current(story: StoryState) -> Dictionary:
	var i := int(story.tutorial.get("step", 0))
	return lessons()[i] if active(story) and i < lessons().size() else {}


## Battle events from the rules engine (and the GM's mission_ended). `mine` = the player's unit ids.
static func observe_battle(story: StoryState, campaign: Campaign, events: Array, mine: Array) -> Array:
	return _observe(story, campaign, events, mine, "event")


static func observe_story(story: StoryState, campaign: Campaign, events: Array) -> Array:
	return _observe(story, campaign, events, [], "story")


static func _observe(story: StoryState, campaign: Campaign, events: Array, mine: Array, key: String) -> Array:
	var out: Array = []
	if not active(story) and not hints_on(campaign):
		return out
	for e: Dictionary in events:
		if str(e.get("type", "")) == "tutorial_prompt":
			continue
		if hints_on(campaign):
			out.append_array(_tips(story, e, mine, key))
		if not active(story):
			continue
		var lesson := current(story)
		if lesson.is_empty():
			continue
		if key == "event" and str(e.get("type", "")) == "turn_ended" and _is_mine(e, mine):
			story.tutorial["turns"] = int(story.tutorial.get("turns", 0)) + 1
		if not bool(story.tutorial.get("shown", false)) and _any(lesson.get("show_on", []), e, mine, key, story):
			out.append(_prompt(story, lesson))
		if _any(lesson.get("done_on", []), e, mine, key, story):
			out.append({"type": "tutorial_lesson_done", "id": lesson["id"]})
			story.tutorial["step"] = int(story.tutorial["step"]) + 1
			story.tutorial["shown"] = false
			story.tutorial["turns"] = 0
			if int(story.tutorial["step"]) >= lessons().size():
				story.tutorial["active"] = false
				out.append({"type": "tutorial_finished"})
			else:
				out.append_array(_show_if_ready(story, [e]))
	return out


static func hints_on(campaign: Campaign) -> bool:
	return campaign == null or bool(campaign.options.get("teaching_hints", true))


## Shows the current lesson now unless it waits for its topic to come up (show_on).
static func _show_if_ready(story: StoryState, _events: Array) -> Array:
	var lesson := current(story)
	if lesson.is_empty() or not (lesson.get("show_on", []) as Array).is_empty():
		return []
	return [_prompt(story, lesson)]


static func _prompt(story: StoryState, lesson: Dictionary) -> Dictionary:
	story.tutorial["shown"] = true
	return {"type": "tutorial_prompt", "kind": "lesson", "id": lesson["id"], "title": lesson.get("title", ""), "text": lesson.get("text", ""),
		"objective": lesson.get("objective", ""), "rule_ref": lesson.get("rule_ref", ""), "phase": lesson.get("phase", ""),
		"codex": lesson.get("codex", lesson.get("title", "")),
		"step": int(story.tutorial.get("step", 0)) + 1, "of": lessons().size()}


static func _tips(story: StoryState, e: Dictionary, mine: Array, key: String) -> Array:
	var out: Array = []
	var seen: Array = story.tutorial.get("tips", [])
	for t: Dictionary in data().get("tips", []):
		if seen.has(t["id"]):
			continue
		if _match(t.get("on", {}), e, mine, key, story):
			seen.append(t["id"])
			out.append({"type": "tutorial_prompt", "kind": "tip", "id": t["id"], "title": t.get("title", ""), "text": t.get("text", ""),
				"objective": "", "rule_ref": t.get("rule_ref", "")})
	if not story.tutorial.has("tips"):
		story.tutorial["tips"] = seen
	return out


static func _any(conds: Array, e: Dictionary, mine: Array, key: String, story: StoryState) -> bool:
	for c: Dictionary in conds:
		if _match(c, e, mine, key, story):
			return true
	return false


static func _match(c: Dictionary, e: Dictionary, mine: Array, key: String, story: StoryState) -> bool:
	if not c.has(key) or str(c[key]) != str(e.get("type", "")):
		return false
	if c.has("mine") and _is_mine(e, mine) != bool(c["mine"]):
		return false
	if bool(c.get("mine_target", false)) and not mine.has(str(e.get("target", e.get("unit", "")))):
		return false
	if c.has("cover") and (str(e.get("cover", "none")) != "none") != bool(c["cover"]):
		return false
	if c.has("result") and str(e.get("result", "")) != str(c["result"]):
		return false
	if c.has("lesson_turns") and int(story.tutorial.get("turns", 0)) < int(c["lesson_turns"]):
		return false
	return true


static func _is_mine(e: Dictionary, mine: Array) -> bool:
	for k in ["unit", "attacker"]:
		if e.has(k) and mine.has(str(e[k])):
			return true
	return false
