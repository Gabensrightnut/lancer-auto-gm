class_name StoryText
extends RefCounted
## Written text from templates (DESIGN.md section 9): picks one of many variants and fills in
## names. "@pool" picks a line from data/game/story/lines.json (never the same one twice in a
## row); {placeholders} are filled from the conversation:
##   {npc} {npc_first} {npc_title} {npc_faction} {npc_role} {npc_want} {npc_quirk}   the NPC
##   {pilot} {callsign} {pilot_first}                          the speaking pilot
##   {hub} {hub_faction} {planet}                              the current hub
##   {operation} {patron} {objective} {target}                 the current mission hook
##   {subject} and anything else in ctx["vars"]

const LINES_FILE := "res://data/game/story/lines.json"
const STANDING_LABELS := {-3: "Hostile", -2: "Unfriendly", -1: "Wary", 0: "Neutral", 1: "Friendly", 2: "Trusted", 3: "Allied"}

static var _pools: Dictionary = {}
static var _re: RegEx


## One line: "@pool" -> a variant, an Array -> one of its entries, then placeholders filled.
static func line(src: Variant, story: StoryState, campaign: Campaign, ctx: Dictionary) -> String:
	var text := ""
	if src is Array:
		var arr: Array = src
		text = str(arr[_pick_index("inline:" + str(arr.hash()), arr.size(), story)]) if not arr.is_empty() else ""
	else:
		text = str(src)
	while text.begins_with("@"):
		text = pool_line(text.substr(1), story, ctx)
	return fill(text, story, campaign, ctx)


## A line from a pool. The NPC's personality adds its own variants: "@greet_local" also draws
## from "greet_local_gruff" for a gruff local; standing adds "_friendly" / "_hostile" ones.
static func pool_line(pool: String, story: StoryState, ctx: Dictionary = {}) -> String:
	var lines: Array = (pools().get(pool, []) as Array).duplicate()
	var culture := str(story.hub.get("culture", ""))
	if culture != "":
		lines.append_array(pools().get(pool + "_" + culture, []))
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	if not npc.is_empty():
		lines.append_array(pools().get(pool + "_" + str(npc.get("personality", "")), []))
		# Standing changes the tone: Wary or worse uses only the cold lines, Friendly or better adds warm ones.
		var st := story.get_standing(str(npc.get("faction", "")))
		if st <= -1 and pools().has(pool + "_hostile"):
			# Cold lines only (no culture flavor either: they're not in the mood).
			lines = (pools()[pool + "_hostile"] as Array).duplicate()
		elif st >= 1:
			lines.append_array(pools().get(pool + "_friendly", []))
	if lines.is_empty():
		return "[%s]" % pool
	return str(lines[_pick_index(pool + ":" + str(npc.get("id", "")), lines.size(), story)])


## Variant index from the story dice, like drawing from a shuffled deck: every variant of a
## pool is used once before any repeats, and never the same one twice in a row.
static func _pick_index(key: String, n: int, story: StoryState) -> int:
	if n <= 1:
		return 0
	var mem: Variant = story.line_memory.get(key, [])
	var used: Array = mem if mem is Array else []
	var left: Array = []
	for i in range(n):
		if not used.has(i):
			left.append(i)
	if left.is_empty():
		var last: int = int(used.back()) if not used.is_empty() else -1
		used = []
		for i in range(n):
			if i != last:
				left.append(i)
	var pick: int = int(left[story.dice.die(left.size()) - 1])
	used.append(pick)
	story.line_memory[key] = used
	return pick


static func pools() -> Dictionary:
	if _pools.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LINES_FILE))
		_pools = data.get("pools", {}) if data is Dictionary else {}
	return _pools


static func fill(text: String, story: StoryState, campaign: Campaign, ctx: Dictionary) -> String:
	if not "{" in text:
		return text
	if _re == null:
		_re = RegEx.create_from_string("\\{([a-z_]+)\\}")
	var vars := values(story, campaign, ctx)
	var out := text
	for m: RegExMatch in _re.search_all(text):
		var key := m.get_string(1)
		if not vars.has(key) and key in ["place", "enemy"]:
			# Rumors and small talk name a random place or threat from the hook tables.
			var list: Array = MissionHooks.data().get("places" if key == "place" else "enemies", [])
			if not list.is_empty():
				vars[key] = list[story.dice.die(list.size()) - 1]
		if vars.has(key):
			out = out.replace(m.get_string(0), str(vars[key]))
	return out


static func values(story: StoryState, campaign: Campaign, ctx: Dictionary) -> Dictionary:
	var v := {}
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	v["npc_id"] = str(ctx.get("npc", ""))
	if not npc.is_empty():
		v["npc"] = npc.get("name", "")
		v["npc_first"] = str(npc.get("name", "")).split(" ")[0]
		v["npc_title"] = npc.get("title", "")
		v["npc_faction"] = npc.get("faction", "")
		v["npc_role"] = npc.get("role_name", "")
		v["npc_role_lower"] = str(npc.get("role_name", "")).to_lower()
		v["npc_want"] = npc.get("want", "")
		v["npc_quirk"] = npc.get("quirk", "")
		v["npc_secret"] = npc.get("secret", "")
		v["npc_deal_reward"] = StoryEffects.reserve_name(str(npc.get("deal_reward", "reserve_backing")))
	var p: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {}) if campaign != null else {}
	if not p.is_empty():
		v["pilot"] = p.get("name", "")
		v["pilot_first"] = str(p.get("name", "")).split(" ")[0]
		v["callsign"] = p.get("callsign", "")
	v["hub"] = story.hub.get("name", "the settlement")
	v["hub_faction"] = story.hub.get("faction", "the locals")
	v["planet"] = story.hub.get("planet", "this world")
	var hook: Dictionary = story.current_hook if not story.current_hook.is_empty() else ctx.get("hook", {})
	for k in ["operation", "patron", "objective", "target", "stakes", "place", "question", "enemy", "cargo", "rival"]:
		if hook.has(k):
			v[k] = hook[k]
	if hook.get("arc") is Dictionary:
		v["arc_beat"] = hook["arc"].get("beat", "")
		v["arc_name"] = hook["arc"].get("name", "")
	if hook.get("deal") is Dictionary:
		v["deal_reward"] = StoryEffects.reserve_name(str(hook["deal"].get("reward", "")))
	var twist: Dictionary = hook.get("twist", {})
	if not twist.is_empty():
		v["twist_reveal"] = twist.get("reveal", "")
		v["twist_question"] = twist.get("question", "")
	v.merge(ctx.get("vars", {}), true)
	return v


## Debrief values from the mission that just ended (story.last_mission.summary).
static func mission_vars(story: StoryState, campaign: Campaign, outcome: String) -> Dictionary:
	var sm: Dictionary = story.last_mission.get("summary", {})
	var fallen_names: Array = []
	for pid: String in story.dead:
		if int(story.dead[pid].get("mission", -1)) == int(story.last_mission.get("number", -2)):
			fallen_names.append(str(campaign.pilots.get(pid, {}).get("callsign", "")))
	# A fallen pilot's mech isn't "reprinted for them"; the debrief mourns them instead.
	var lost: Array = (sm.get("lost", []) as Array).filter(func(n: String) -> bool: return not fallen_names.has(n))
	var v := {"outcome": outcome, "kills": str(sm.get("kills", 0)), "mvp": str(sm.get("mvp", ""))}
	if sm.has("rounds"):
		v["rounds"] = str(sm["rounds"])
		v["rounds_text"] = "1 round" if int(sm["rounds"]) == 1 else "%d rounds" % int(sm["rounds"])
	var kills := int(sm.get("kills", 0))
	v["kills_line"] = "None of theirs went down." if kills == 0 else ("One of theirs went down." if kills == 1 else "%d of theirs went down." % kills)
	if lost.is_empty():
		v["lost_line"] = "Every mech came back in one piece."
	else:
		v["lost_line"] = "%s %s wrecked; the printer will make %s at the full repair." % [", ".join(PackedStringArray(lost)),
			"was" if lost.size() == 1 else "were", "a new one" if lost.size() == 1 else "new ones"]
	v["mvp_line"] = ("%s did the most damage out there." % v["mvp"]) if v["mvp"] != "" else ""
	var fallen: Array = []
	for pid: String in story.dead:
		if int(story.dead[pid].get("mission", -1)) == int(story.last_mission.get("number", -2)):
			fallen.append(str(campaign.pilots.get(pid, {}).get("callsign", "a pilot")))
	if not fallen.is_empty():
		v["fallen"] = ", ".join(PackedStringArray(fallen))
	var ejected: Array = sm.get("ejected", [])
	v["ejected_line"] = ("%s had to get out on foot." % ", ".join(PackedStringArray(ejected))) if not ejected.is_empty() else ""
	v["rival_line"] = str(story.flags.get(Rivals.DEBRIEF, ""))
	return v


## Briefing values that look back: the last mission and what the squad did in downtime.
static func briefing_vars(story: StoryState, campaign: Campaign) -> Dictionary:
	var v := {}
	var lm := story.last_mission
	if not lm.is_empty():
		v["last_title"] = str(lm.get("hook", ""))
		v["last_place"] = str(lm.get("place", ""))
		v["last_outcome_line"] = {"victory": "it went our way", "defeat": "it went badly", "draw": "nobody won"}.get(str(lm.get("outcome", "")), "it's over")
		v["last_twist"] = str(lm.get("twist", ""))
	if str(story.flags.get("_identity", "")) != "" and campaign != null and campaign.history.is_empty():
		v["identity"] = str(story.flags["_identity"])
	var legacy: Dictionary = story.flags.get("_legacy", {})
	if not legacy.is_empty() and campaign != null and campaign.history.is_empty():
		var opts: Array = Ending.data().get("sequel", {}).get("briefing_legacy", [])
		if not opts.is_empty():
			v["legacy_line"] = str(opts[story.dice.die(opts.size()) - 1]).replace("{legacy_name}", str(legacy.get("name", "the last campaign")))
	var recap: Array = story.flags.get("_last_downtime", [])
	if not recap.is_empty():
		v["downtime_recap"] = " ".join(PackedStringArray(recap.slice(0, 4).map(func(r: Dictionary) -> String: return str(r.get("text", "")))))
	return v


static func standing_label(n: int) -> String:
	return str(STANDING_LABELS.get(clampi(n, -3, 3), "Neutral"))


## Strips the HTML lancer-data uses (<ul><li>, <i>, <br>) for plain labels.
static func plain(html: String) -> String:
	var t := html.replace("<li>", "\n• ").replace("<br>", "\n").replace("</li>", "")
	var re := RegEx.create_from_string("<[^>]+>")
	return re.sub(t, "", true).replace("• •", "•").strip_edges()
