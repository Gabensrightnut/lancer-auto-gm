class_name StoryArc
extends RefCounted
## A story arc at a hub: a few missions that escalate to a reveal and a confrontation
## (data/game/story/arcs.json; patterns from published campaigns, docs/research/). The next
## mission of the arc is always on the job board, next to side jobs. Every mission moves the
## arc on, won or lost (the story goes on either way, as pilots level up either way, Core p.40);
## the final one's result is remembered in flags and standing.

const FILE := "res://data/game/story/arcs.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"arcs": []}
	return _data


## Starts an arc if none is running and makes sure its current mission is on the board.
## Returns the hook it added ({} if nothing was added).
static func ensure(story: StoryState, campaign: Campaign) -> Dictionary:
	if story.hub.is_empty():
		return {}
	if story.arc.is_empty() or str(story.arc.get("hub", "")) != str(story.hub.get("id", "")):
		start(story, campaign)
	if story.arc.is_empty():
		return {}
	for h: Dictionary in story.hooks:
		if h.get("arc", {}).get("id", "") == story.arc["id"]:
			return {}
	if story.current_hook.get("arc", {}).get("id", "") == story.arc["id"]:
		return {}
	var hook := stage_hook(story, campaign)
	if not hook.is_empty():
		story.hooks.push_front(hook)
	return hook


static func start(story: StoryState, campaign: Campaign = null) -> void:
	var arcs: Array = (data().get("arcs", []) as Array).filter(func(a: Dictionary) -> bool: return SessionZero.allowed(campaign, "arcs", str(a["id"])))
	var conflict: Dictionary = story.hub.get("conflict", {})
	if arcs.is_empty() or conflict.is_empty():
		story.arc = {}
		return
	# The table's tone (session zero) shifts which situations come up.
	var w := func(a: Dictionary) -> int: return maxi(1, roundi(float(a.get("weight", 1)) * 10.0 * SessionZero.arc_weight(campaign, str(a["id"]))))
	var total := 0
	for a: Dictionary in arcs:
		total += int(w.call(a))
	var roll := story.dice.die(maxi(total, 1))
	var pick: Dictionary = arcs[0]
	for a: Dictionary in arcs:
		roll -= int(w.call(a))
		if roll <= 0:
			pick = a
			break
	var names: Array = data().get("rival_names", ["the other squad"])
	story.arc = {"id": str(pick["id"]), "name": str(pick["name"]), "stage": 0, "hub": str(story.hub["id"]),
		"a": str(conflict["a"]), "b": str(conflict["b"]), "rival": str(names[story.dice.die(names.size()) - 1])}
	# The other side has one commander for the whole situation (Rivals).
	story.arc["commander"] = Rivals.make(story, campaign, str(conflict["b"]), str(pick["id"]), str(story.arc["rival"]) if str(pick["id"]) == "rivalry" else "")
	story.add_log("A new situation at %s: %s" % [story.hub.get("name", ""), conflict.get("summary", "")])


static func arc_def(id: String) -> Dictionary:
	for a: Dictionary in data().get("arcs", []):
		if str(a["id"]) == id:
			return a
	return {}


## The hook for the arc's current stage.
static func stage_hook(story: StoryState, campaign: Campaign) -> Dictionary:
	var def := arc_def(str(story.arc["id"]))
	var stages: Array = def.get("stages", [])
	var n := int(story.arc["stage"])
	if n >= stages.size():
		return {}
	var stage: Dictionary = stages[n]
	var conflict: Dictionary = story.hub.get("conflict", {})
	var kind := str(stage.get("hook", "side_a"))
	var side := "b" if kind == "side_b" else "a"
	var tid := kind
	match kind:
		"side_a", "side_b":
			var list: Array = conflict.get(side + "_hooks", ["clear_raiders"])
			tid = str(list[story.dice.die(list.size()) - 1])
		"side_b_strike":
			tid = "raid_depot"
	var patron := _npc_of(story, str(story.arc[side]))
	var other := str(story.arc["b" if side == "a" else "a"])
	var hook := MissionHooks.make(story, campaign, tid, {"patron": patron, "rival": other, "twist": str(stage.get("twist", "")),
		"commander": str(story.arc.get("commander", "")) if side == "a" else ""})
	if hook.is_empty():
		return {}
	hook["enemy"] = "%s's forces" % other if kind != "side_a" or n > 0 else hook["enemy"]
	var vars := {"a": story.arc["a"], "b": story.arc["b"], "rival": story.arc["rival"]}
	var beat := StoryText.fill(_fill(StoryText.line(stage.get("beat", [""]), story, campaign, {}), vars), story, campaign, {"hook": hook})
	# Each stage remembers how the last one went.
	if story.arc.has("last_won"):
		beat = StoryText.fill(_fill(StoryText.pool_line("arc_after_win" if bool(story.arc["last_won"]) else "arc_after_loss", story), vars), story, campaign, {"hook": hook}) + " " + beat
	hook["arc"] = {"id": story.arc["id"], "name": story.arc["name"], "stage": n, "of": stages.size(), "final": bool(stage.get("final", false)), "beat": beat}
	hook["short_title"] = hook["title"]
	hook["title"] = "%s (%d/%d): %s" % [story.arc["name"], n + 1, stages.size(), hook["title"]]
	return hook


## After a mission: moves the arc on if the mission was its current stage.
static func advance(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool) -> Array:
	var info: Dictionary = hook.get("arc", {})
	if info.is_empty() or story.arc.is_empty() or str(info["id"]) != str(story.arc["id"]):
		return []
	var def := arc_def(str(story.arc["id"]))
	if bool(info.get("final", false)):
		var ctx := {"arc": story.arc, "hook": hook}
		var events: Array = [{"type": "arc_finished", "arc": story.arc.duplicate(), "won": won}]
		events.append_array(StoryEffects.apply_all(def.get("on_win" if won else "on_loss", []), story, campaign, ctx))
		story.flags["arc_done:%s:%s" % [story.arc["id"], story.arc["hub"]]] = "won" if won else "lost"
		story.add_log("%s at %s is over: %s." % [story.arc["name"], story.hub.get("name", ""), "the squad came out on top" if won else "it didn't go the squad's way"])
		story.arc = {}
		return events
	story.arc["stage"] = int(story.arc["stage"]) + 1
	story.arc["last_won"] = won
	return [{"type": "arc_advanced", "arc": story.arc.duplicate(), "won": won}]


static func _npc_of(story: StoryState, faction: String) -> String:
	var fallback := ""
	for id: String in story.hub.get("npcs", []):
		var npc: Dictionary = story.npcs.get(id, {})
		if bool(npc.get("dead", false)):
			continue
		if str(npc.get("faction", "")) == faction:
			if str(npc.get("role", "")) in ["faction_agent", "local", "bartender", "company_rep"]:
				return id
			fallback = id
	return fallback


static func _fill(text: String, vars: Dictionary) -> String:
	for k: String in vars:
		text = text.replace("{%s}" % k, str(vars[k]))
	return text
