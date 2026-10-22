class_name StoryConditions
extends RefCounted
## Checks a condition from story data against the campaign. Conditions are plain
## Dictionaries so scenes stay data:
##   {"flag": "met_rep"}                       flag is set (truthy)
##   {"flag": "favors", "min": 2} / "max" / "eq"   (keys may use {placeholders}, e.g. "met:{npc_id}")
##   {"var": "outcome", "eq": "victory"}       a value the scene was opened with (ctx.vars)
##   {"not": cond} / {"all": [conds]} / {"any": [conds]}
##   {"standing": "$npc.faction", "min": 1}    faction standing (-3..+3) / "max"
##   {"alive": "speaker"} / {"dead": pilot id}  squad pilots ("speaker", "$x" or an id)
##   {"npc_alive": "$npc"}
##   {"trigger": "sk_charm", "min_rank": 1}    the speaking pilot has that skill trigger
##   {"squad_trigger": "sk_charm"}             anyone alive in the squad has it
##   {"background": "pbg_soldier"}             speaker's background
##   {"reserve": "reserve_access"}             speaker holds that reserve
##   {"phase": "downtime"} / {"phase": ["briefing", "downtime"]}
##   {"downtime_left": true}                   speaker still has a downtime action
##   {"last_outcome": "victory"}               last mission's result
##   {"ll_min": 2} / {"ll_max": 5}             speaker's License Level
##   {"contact": "$npc"}                       the squad has met this NPC
##   {"obligation": "$npc.faction"}            the squad owes this faction or contact a favor
##   {"missions_min": 1}                       missions finished
##   {"hub_has": "bar"}                        current hub has a place of that kind
##   {"role": "company_rep"}                   the NPC in this conversation has that role
## Values starting with "$" are looked up in the conversation context (see resolve()).


static func check(cond: Variant, story: StoryState, campaign: Campaign, ctx: Dictionary) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c: Variant in cond:
			if not check(c, story, campaign, ctx):
				return false
		return true
	if not cond is Dictionary or (cond as Dictionary).is_empty():
		return true
	var c: Dictionary = cond
	if c.has("all"):
		return check(c["all"], story, campaign, ctx)
	if c.has("any"):
		for sub: Variant in c["any"]:
			if check(sub, story, campaign, ctx):
				return true
		return false
	if c.has("not"):
		return not check(c["not"], story, campaign, ctx)
	if c.has("flag"):
		return _compare(story.flags.get(StoryText.fill(str(resolve(c["flag"], story, ctx)), story, campaign, ctx)), c)
	if c.has("var"):
		return _compare(ctx.get("vars", {}).get(str(c["var"])), c)
	if c.has("standing"):
		return _compare(story.get_standing(str(resolve(c["standing"], story, ctx))), c)
	if c.has("alive"):
		var pid := pilot_id(c["alive"], story, ctx)
		return campaign.pilots.has(pid) and story.is_alive(pid)
	if c.has("dead"):
		return story.dead.has(pilot_id(c["dead"], story, ctx))
	if c.has("npc_alive"):
		var npc: Dictionary = story.npcs.get(str(resolve(c["npc_alive"], story, ctx)), {})
		return not npc.is_empty() and not bool(npc.get("dead", false))
	if c.has("trigger"):
		var p: Dictionary = campaign.pilots.get(pilot_id("speaker", story, ctx), {})
		return int(p.get("skills", {}).get(str(c["trigger"]), 0)) >= int(c.get("min_rank", 1))
	if c.has("squad_trigger"):
		for pid: String in campaign.pilots:
			if story.is_alive(pid) and int(campaign.pilots[pid].get("skills", {}).get(str(c["squad_trigger"]), 0)) >= int(c.get("min_rank", 1)):
				return true
		return false
	if c.has("background"):
		var p: Dictionary = campaign.pilots.get(pilot_id("speaker", story, ctx), {})
		return str(p.get("background", "")) == str(c["background"])
	if c.has("reserve"):
		return story.has_reserve(pilot_id("speaker", story, ctx), str(c["reserve"]))
	if c.has("phase"):
		var phases: Variant = c["phase"]
		return (phases as Array).has(story.phase) if phases is Array else story.phase == str(phases)
	if c.has("downtime_left"):
		var left := int(story.downtime.get("actions_left", {}).get(pilot_id("speaker", story, ctx), 0))
		return (left > 0) == bool(c["downtime_left"])
	if c.has("last_outcome"):
		return str(story.last_mission.get("outcome", "")) == str(c["last_outcome"])
	if c.has("ll_min") or c.has("ll_max"):
		var ll := int(campaign.pilots.get(pilot_id("speaker", story, ctx), {}).get("ll", 0))
		return ll >= int(c.get("ll_min", 0)) and ll <= int(c.get("ll_max", 12))
	if c.has("contact"):
		return story.contacts.has(str(resolve(c["contact"], story, ctx)))
	if c.has("obligation"):
		var who := str(resolve(c["obligation"], story, ctx))
		for o: Dictionary in story.downtime.get("obligations", []):
			if str(o.get("to", "")) == who and not bool(o.get("done", false)):
				return true
		return false
	if c.has("missions_min"):
		return campaign.history.size() >= int(c["missions_min"])
	if c.has("hub_has"):
		for spot: Dictionary in story.hub.get("spots", []):
			if str(spot.get("kind", "")) == str(c["hub_has"]):
				return true
		return false
	if c.has("role"):
		return str(story.npcs.get(str(ctx.get("npc", "")), {}).get("role", "")) == str(c["role"])
	push_warning("StoryConditions: unknown condition %s" % [c])
	return false


static func _compare(value: Variant, c: Dictionary) -> bool:
	if c.has("eq"):
		return value != null and str(value) == str(c["eq"])
	if c.has("min") or c.has("max"):
		var n := 0.0
		if value is int or value is float:
			n = float(value)
		elif value is bool:
			n = 1.0 if value else 0.0
		return n >= float(c.get("min", -INF)) and n <= float(c.get("max", INF))
	return value != null and not (value is bool and value == false) and not (value is int and value == 0) and str(value) != ""


## "$npc" -> the NPC id; "$npc.faction" -> a field of that NPC; "$speaker" -> pilot id;
## "$hub.faction" -> a hub field; anything else in ctx by name. Other values pass through.
static func resolve(v: Variant, story: StoryState, ctx: Dictionary) -> Variant:
	if not v is String or not (v as String).begins_with("$"):
		return v
	var parts := (v as String).substr(1).split(".")
	var head := parts[0]
	var base: Variant
	if head == "hub":
		base = story.hub
	elif head == "npc":
		base = story.npcs.get(str(ctx.get("npc", "")), {}) if parts.size() > 1 else ctx.get("npc", "")
	else:
		base = ctx.get(head, "")
	for i in range(1, parts.size()):
		base = (base as Dictionary).get(parts[i], "") if base is Dictionary else ""
	return base


static func pilot_id(v: Variant, story: StoryState, ctx: Dictionary) -> String:
	if str(v) == "speaker":
		return str(ctx.get("speaker", ""))
	return str(resolve(v, story, ctx))
