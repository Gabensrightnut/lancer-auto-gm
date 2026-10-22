class_name Dialogue
extends RefCounted
## Runs dialogue scenes written as data (data/game/story/scenes/<id>.json). StoryEngine calls
## it; the open conversation lives in story.dialogue so it saves and syncs like everything
## else. Scene format:
##   {"id", "start": node id, "nodes": {id: node}}
##   node: {"speaker": "npc" | "pilot" | "narrator", "expression": "neutral", "line": "@pool" | text | [variants],
##          "effects": [...], "next": id, "end": true, "branch": [{"if": cond, "next": id}],
##          "choices": [choice]}
##   choice: {"id", "text", "condition", "tags": ["diplomatic"], "trigger": "sk_charm" (badge + unlock),
##            "effects", "next", "end", "pinned": true (always offered), "priority": n,
##            "check": {"skills", "tags", "against_tags", "difficult", "risky", "heroic", "goal",
##                      "teamwork", "challenge", "consequence", "success", "fail",
##                      "success_effects", "fail_effects"}}
## Only choices whose condition holds are offered, at most MAX_CHOICES (DESIGN.md section 10:
## 4-6 options). Pinned choices (like leaving) always stay; trigger-unlocked ones come next.
## A goal failed earlier can only be tried again by pushing it (Core p.46).

const SCENE_DIR := "res://data/game/story/scenes/"
const MAX_CHOICES := 6
const PERSONAS := "res://data/game/story/personas.json"

static var _scenes: Dictionary = {}
static var _personas: Dictionary = {}


static func scene(id: String) -> Dictionary:
	if not _scenes.has(id):
		var path := SCENE_DIR + id + ".json"
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_scenes[id] = data if data is Dictionary else {}
	return _scenes[id]


static func scene_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(SCENE_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


static func is_open(story: StoryState) -> bool:
	return not story.dialogue.is_empty()


# --- Running -----------------------------------------------------------------------------

## Opens a conversation. ctx: {"speaker": pilot id, "npc": npc id, "vars": {...}}.
static func start(story: StoryState, campaign: Campaign, scene_id: String, ctx: Dictionary) -> Array:
	var sc := scene(scene_id)
	story.dialogue = {"scene": scene_id, "node": "", "ctx": ctx.duplicate(true), "log": [], "votes": {}, "choices": []}
	var events: Array = [{"type": "dialogue_started", "scene": scene_id, "npc": ctx.get("npc", ""), "speaker": ctx.get("speaker", "")}]
	events.append_array(_enter(story, campaign, str(sc.get("start", ""))))
	return events


## Goes to the next node of a line without choices.
static func advance(story: StoryState, campaign: Campaign) -> Array:
	var node := current_node(story)
	if node.get("end", false) or not node.has("next"):
		return close(story, "finished")
	return _enter(story, campaign, str(node["next"]))


static func close(story: StoryState, why: String = "finished") -> Array:
	var sc := str(story.dialogue.get("scene", ""))
	story.dialogue = {}
	return [{"type": "dialogue_ended", "scene": sc, "reason": why}]


static func current_node(story: StoryState) -> Dictionary:
	return scene(str(story.dialogue.get("scene", ""))).get("nodes", {}).get(str(story.dialogue.get("node", "")), {})


static func offered(story: StoryState) -> Array:
	return story.dialogue.get("choices", [])


static func _enter(story: StoryState, campaign: Campaign, node_id: String) -> Array:
	var nodes: Dictionary = scene(str(story.dialogue["scene"])).get("nodes", {})
	var ctx: Dictionary = story.dialogue["ctx"]
	var events: Array = []
	var guard := 0
	while guard < 16:
		guard += 1
		if node_id == "" or not nodes.has(node_id):
			return events + close(story, "finished")
		var node: Dictionary = nodes[node_id]
		var jumped := false
		for b: Dictionary in node.get("branch", []):
			if StoryConditions.check(b.get("if"), story, campaign, ctx):
				node_id = str(b["next"])
				jumped = true
				break
		if jumped:
			continue
		story.dialogue["node"] = node_id
		events.append_array(StoryEffects.apply_all(node.get("effects", []), story, campaign, ctx))
		if not is_open(story):
			return events
		if not node.has("line") and not node.has("choices"):
			if node.has("next") and not bool(node.get("end", false)):
				node_id = str(node["next"])
				continue
			return events + close(story, "finished")
		var text := StoryText.line(node.get("line", ""), story, campaign, ctx) if node.has("line") else ""
		var speaker := str(node.get("speaker", "npc"))
		story.dialogue["text"] = text
		story.dialogue["speaker"] = speaker
		story.dialogue["expression"] = str(node.get("expression", "neutral"))
		story.dialogue["votes"] = {}
		story.dialogue["choices"] = _build_choices(story, campaign, node.get("choices", []), ctx)
		if text != "":
			(story.dialogue["log"] as Array).append({"speaker": speaker, "name": speaker_name(story, campaign, speaker), "text": text})
			events.append({"type": "dialogue_line", "speaker": speaker, "name": speaker_name(story, campaign, speaker),
				"expression": story.dialogue["expression"], "text": text, "choices": story.dialogue["choices"].duplicate(true)})
		if node.has("choices") and (story.dialogue["choices"] as Array).is_empty():
			# Nothing to say here any more: go on (or end) instead of getting stuck.
			if node.has("next"):
				node_id = str(node["next"])
				continue
			return events + close(story, "finished")
		return events
	return events + close(story, "loop")


static func _build_choices(story: StoryState, campaign: Campaign, raw: Array, ctx: Dictionary) -> Array:
	var eligible: Array = []
	var i := 0
	for c: Dictionary in raw:
		i += 1
		if not StoryConditions.check(c.get("condition"), story, campaign, ctx):
			continue
		if c.has("trigger") and not StoryConditions.check({"trigger": c["trigger"]}, story, campaign, ctx):
			continue
		var cc := {"id": str(c.get("id", "c%d" % i)), "order": i, "tags": c.get("tags", []), "pinned": bool(c.get("pinned", false)),
			"priority": int(c.get("priority", 2 if c.has("trigger") else 1))}
		cc["text"] = StoryText.line(c.get("text", "..."), story, campaign, ctx)
		if c.has("trigger"):
			cc["badge"] = NarrativeCheck.trigger_name(str(c["trigger"]))
		if c.has("check"):
			var chk: Dictionary = c["check"]
			var level := NarrativeCheck.level_of(chk)
			var goal := StoryText.fill(str(chk.get("goal", "")), story, campaign, ctx)
			if goal != "" and story.failed_goals.has(goal):
				var push := NarrativeCheck.push_level(str(story.failed_goals[goal]), bool(campaign.options.get("allow_heroic_push", true)) if campaign != null else true)
				if not push["ok"]:
					continue
				level = str(push["level"])
				cc["pushed"] = true
				cc["text"] = "[Push it] " + str(cc["text"])
			var p: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {}) if campaign != null else {}
			var trig := NarrativeCheck.pick_trigger(p, chk.get("skills", []))
			cc["check"] = {"level": level, "difficult": bool(chk.get("difficult", false)), "trigger": trig["name"], "bonus": trig["bonus"],
				"consequence": StoryText.fill(str(chk.get("consequence", "")), story, campaign, ctx), "challenge": bool(chk.get("challenge", false))}
		eligible.append(cc)
	# Cap at MAX_CHOICES: pinned first, then by priority, keeping the written order.
	var ranked := eligible.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pinned"] != b["pinned"]:
			return a["pinned"]
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		return a["order"] < b["order"])
	var kept := ranked.slice(0, MAX_CHOICES)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return kept


## Resolves the picked choice. Returns events.
static func resolve_choice(story: StoryState, campaign: Campaign, choice_id: String, chooser_seat: String) -> Array:
	var node := current_node(story)
	var ctx: Dictionary = story.dialogue["ctx"]
	var c: Dictionary = {}
	for raw: Dictionary in node.get("choices", []):
		if str(raw.get("id", "")) == choice_id:
			c = raw
	var shown: Dictionary = {}
	for o: Dictionary in offered(story):
		if o["id"] == choice_id:
			shown = o
	var events: Array = [{"type": "dialogue_choice", "choice": choice_id, "text": shown.get("text", ""), "by": chooser_seat,
		"votes": story.dialogue.get("votes", {}).duplicate()}]
	(story.dialogue["log"] as Array).append({"speaker": "pilot", "name": speaker_name(story, campaign, "pilot"), "text": shown.get("text", "")})
	events.append_array(StoryEffects.apply_all(c.get("effects", []), story, campaign, ctx))
	if not is_open(story):
		return events
	var next := str(c.get("next", ""))
	if c.has("check"):
		var r := _roll_choice(story, campaign, c["check"], shown, ctx)
		events.append_array(r["events"])
		next = str(c["check"].get("success" if r["success"] else "fail", next))
		if not is_open(story):
			return events
	if bool(c.get("end", false)) or next == "":
		return events + close(story, "finished")
	if _ends(events):
		return events + close(story, "combat")
	events.append_array(_enter(story, campaign, next))
	return events


static func _ends(events: Array) -> bool:
	for e: Dictionary in events:
		if str(e.get("type", "")) == "combat_requested":
			return true
	return false


static func _roll_choice(story: StoryState, campaign: Campaign, chk: Dictionary, shown: Dictionary, ctx: Dictionary) -> Dictionary:
	var events: Array = []
	var speaker := str(ctx.get("speaker", ""))
	var squad: Array = []
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			squad.append(pid)
	squad.sort()
	var opts := chk.duplicate(true)
	opts["label"] = StoryText.fill(str(chk.get("label", shown.get("text", "Skill check"))), story, campaign, ctx)
	opts["consequence"] = StoryText.fill(str(chk.get("consequence", "")), story, campaign, ctx)
	var shown_check: Dictionary = shown.get("check", {})
	if shown.get("pushed", false):
		opts["risky"] = shown_check.get("level", "") == "risky"
		opts["heroic"] = shown_check.get("level", "") == "heroic"
	var success := false
	var consequence := false
	var sharing: Array = [speaker]
	if bool(chk.get("challenge", false)):
		var pilots: Array = squad.map(func(pid: String) -> Dictionary: return campaign.pilots[pid])
		var res := NarrativeCheck.challenge(story.dice, pilots, opts)
		for rec: Dictionary in res["checks"]:
			events.append({"type": "narrative_check", "pilot": rec["pilot"], "check": rec, "rule_ref": NarrativeCheck.REF})
		events.append({"type": "skill_challenge", "success": res["success"], "successes": res["successes"], "failures": res["failures"],
			"tiebreak": res["tiebreak"], "rule_ref": NarrativeCheck.REF_CHALLENGE})
		success = res["success"]
		consequence = not success
		sharing = squad
	else:
		if bool(chk.get("teamwork", false)):
			var helpers := squad.filter(func(pid: String) -> bool: return pid != speaker)
			opts["helpers"] = helpers.size()
			sharing = squad
		var rec := NarrativeCheck.roll(story.dice, campaign.pilots.get(speaker, {}), opts)
		events.append({"type": "narrative_check", "pilot": speaker, "check": rec, "rule_ref": NarrativeCheck.REF})
		success = rec["success"]
		consequence = rec["consequence"]
		var goal := StoryText.fill(str(chk.get("goal", "")), story, campaign, ctx)
		if goal != "":
			if success:
				story.failed_goals.erase(goal)
			else:
				story.failed_goals[goal] = rec["level"]
	var fx: Array = chk.get("success_effects" if success else "fail_effects", [])
	events.append_array(StoryEffects.apply_all(fx, story, campaign, ctx))
	# A RISKY success still has consequences (Core p.45): the fail effects marked "risky_too".
	if success and consequence:
		for e: Dictionary in chk.get("fail_effects", []):
			if bool(e.get("risky_too", false)):
				events.append_array(StoryEffects.apply(e, story, campaign, ctx))
	# Harm from a failed check hits everyone who helped too (teamwork, Core p.45).
	if consequence and sharing.size() > 1 and not bool(chk.get("challenge", false)):
		for e: Dictionary in chk.get("fail_effects", []):
			if e.has("harm") and str(e.get("to", "speaker")) != "squad" and (not success or bool(e.get("risky_too", false))):
				for pid: String in sharing:
					if pid != speaker:
						events.append_array(StoryEffects.harm(story, campaign, pid, int(e["harm"]), bool(e.get("ap", false))))
	return {"success": success, "events": events}


# --- Who decides -------------------------------------------------------------------------

## {"mode": "speaker" | "vote", "seats": [...]} for the open choice. Host setting
## campaign.options["dialogue_choice"]: "speaker" (default) or "vote".
static func decider(story: StoryState, campaign: Campaign) -> Dictionary:
	var mode := str(campaign.options.get("dialogue_choice", "speaker")) if campaign != null else "speaker"
	var speaker_seat := story.seat_of(str(story.dialogue.get("ctx", {}).get("speaker", "")))
	if mode == "vote":
		var seats: Array = []
		for s: String in story.seats:
			if story.is_alive(story.pilot_of_seat(s)):
				seats.append(s)
		seats.sort()
		return {"mode": "vote", "seats": seats, "speaker_seat": speaker_seat}
	return {"mode": "speaker", "seats": [speaker_seat], "speaker_seat": speaker_seat}


## The vote result once every seat has voted ("" while waiting). Ties go to the speaking
## pilot's vote, then to the earliest option (PROVISIONAL: a table procedure, not a book rule).
static func vote_result(story: StoryState, campaign: Campaign) -> String:
	var d := decider(story, campaign)
	var votes: Dictionary = story.dialogue.get("votes", {})
	for s: String in d["seats"]:
		if not votes.has(s):
			return ""
	var counts := {}
	for s: String in votes:
		counts[votes[s]] = int(counts.get(votes[s], 0)) + 1
	var best := 0
	for k: String in counts:
		best = maxi(best, int(counts[k]))
	var tied: Array = []
	for o: Dictionary in offered(story):
		if int(counts.get(o["id"], 0)) == best:
			tied.append(o["id"])
	var sp := str(votes.get(d["speaker_seat"], ""))
	if tied.has(sp):
		return sp
	return str(tied[0]) if not tied.is_empty() else ""


## An AI squadmate picks in character: persona likes and dislikes by choice tags, plus how
## good their trigger is for a check, plus a little story-dice noise.
## {"choice": id, "why": text}
static func ai_pick(story: StoryState, campaign: Campaign, seat: String) -> Dictionary:
	var persona_id := str(story.seats.get(seat, {}).get("persona", "steady"))
	var persona: Dictionary = personas().get(persona_id, personas().get("steady", {}))
	var likes: Dictionary = persona.get("likes", {})
	var pilot: Dictionary = campaign.pilots.get(story.pilot_of_seat(seat), {})
	var best_id := ""
	var best_score := -INF
	var best_tag := ""
	for o: Dictionary in offered(story):
		var score := float(story.dice.die(10)) / 10.0
		var top_tag := ""
		var top := -INF
		for t: String in o.get("tags", []):
			var w := float(likes.get(t, 0))
			score += w
			if w > top:
				top = w
				top_tag = t
		if o.has("check"):
			score += float(o["check"].get("bonus", 0)) * 0.4 - (1.0 if o["check"].get("level", "normal") != "normal" else 0.0) * float(persona.get("caution", 1))
		if o.get("tags", []).has("leave"):
			score += float(persona.get("leave", -2))
		if score > best_score:
			best_score = score
			best_id = str(o["id"])
			best_tag = top_tag
	var why_pool: Dictionary = persona.get("why", {})
	var why := str(why_pool.get(best_tag, persona.get("why_default", "")))
	return {"choice": best_id, "why": StoryText.fill(why, story, campaign, {"speaker": str(pilot.get("id", ""))}), "persona": persona_id}


static func personas() -> Dictionary:
	if _personas.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
		_personas = data.get("personas", {}) if data is Dictionary else {"steady": {}}
	return _personas


static func speaker_name(story: StoryState, campaign: Campaign, speaker: String) -> String:
	var ctx: Dictionary = story.dialogue.get("ctx", {})
	match speaker:
		"npc":
			return str(story.npcs.get(str(ctx.get("npc", "")), {}).get("name", "Command"))
		"pilot":
			var p: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {}) if campaign != null else {}
			return str(p.get("callsign", p.get("name", "You")))
		"narrator":
			return ""
	return speaker
