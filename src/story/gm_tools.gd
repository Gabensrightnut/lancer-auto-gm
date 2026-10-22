class_name GmTools
extends RefCounted
## Story tools for a human GM (DESIGN.md "Human GM seat"). Every tool is a StoryEngine action
## from the "gm" seat, so it is checked like any other action, players only ever see their
## filtered StoryView, and it works online (StorySession runs it on the host).
##
##   gm_scene     {npc, speaker, lines: [{who: "npc"|"pilot"|"narrator", text, expression}],
##                 choices: [{text, reply, tags, effects}], start: true}
##                write a conversation on the spot (0-6 replies); it is kept in the story so it
##                syncs and can be replayed (start a saved one with {"id": ...})
##   gm_twist     {hook: id | "" (current), do: "reveal" | "hide" | "set", reveal, question}
##   gm_standing  {faction, add} or {faction, set}           (this game's own bookkeeping)
##   gm_reserve   {pilot | "squad", reserve: id, name} to grant, {pilot, remove: index} to take back
##   gm_job       {template, patron, title, objective, stakes, place, enemy}   a side job on the board
##   gm_edit_job  {hook, set: {title, objective, stakes, question, place, enemy, patron_id,
##                 briefing: [lines], commander: rival id | "none" | {new: {callsign, rank, personality}}}}
##                change a job before the squad sees its briefing
##   gm_remove_job {hook}
##   gm_npc       {npc, set: {name, title, personality, faction, secret, dead, portrait}} or
##                {new: {role, name, title, faction, personality}}  a new person at this hub
##
## GM-written text is the GM's own: it isn't checked against the book (CANON.md).

const SCENES := "_gm_scenes"
const MAX_CHOICES := 6
const REF_RESERVES := "Core p.50-52: the GM gives out reserves"
const REF_TWIST := "Core p.43: goals and situations can change mid-mission"
const ACTIONS := ["gm_scene", "gm_twist", "gm_standing", "gm_reserve", "gm_job", "gm_edit_job", "gm_remove_job", "gm_npc"]
const EDITABLE_HOOK := ["title", "objective", "stakes", "question", "place", "enemy", "patron_id"]
const EDITABLE_NPC := ["name", "title", "personality", "faction", "secret", "dead", "portrait", "quirk", "want"]


static func handles(type: String) -> bool:
	return ACTIONS.has(type)


static func scenes(story: StoryState) -> Dictionary:
	return story.flags.get(SCENES, {})


## Why a GM action can't be done ("" if it can).
static func refusal(story: StoryState, campaign: Campaign, type: String, p: Dictionary, seat: String) -> String:
	if seat != "gm":
		return "Only the GM can do that."
	match type:
		"gm_scene":
			if Dialogue.is_open(story):
				return "Someone is already talking. Finish that conversation first."
			if p.has("id"):
				return "" if scenes(story).has(str(p["id"])) else "There's no saved scene called that."
			var lines: Array = p.get("lines", [])
			if lines.is_empty():
				return "Write at least one line."
			for l: Variant in lines:
				if not l is Dictionary or str(l.get("text", "")).strip_edges() == "":
					return "Every line needs some text."
				if not str(l.get("who", "npc")) in ["npc", "pilot", "narrator"]:
					return "A line is spoken by the NPC, the pilot or the narrator."
			var choices: Array = p.get("choices", [])
			if choices.size() > MAX_CHOICES:
				return "At most %d replies." % MAX_CHOICES
			for c: Variant in choices:
				if not c is Dictionary or str(c.get("text", "")).strip_edges() == "":
					return "Every reply needs some text."
				for fx: Variant in c.get("effects", []):
					var bad := _bad_effect(fx)
					if bad != "":
						return bad
			var npc := str(p.get("npc", ""))
			if npc != "" and not story.npcs.has(npc):
				return "Nobody like that is here."
			if lines.any(func(l: Dictionary) -> bool: return str(l.get("who", "npc")) == "npc") and npc == "":
				return "Pick who the NPC lines belong to."
		"gm_twist":
			var hook := _hook(story, str(p.get("hook", "")))
			if hook.is_empty():
				return "No such job."
			match str(p.get("do", "")):
				"reveal", "hide":
					if hook.get("twist", {}).is_empty():
						return "That job has no twist."
				"set":
					if str(p.get("reveal", "")).strip_edges() == "":
						return "Write what the twist is."
				_:
					return "Reveal, hide or set a twist."
		"gm_standing":
			if str(p.get("faction", "")).strip_edges() == "":
				return "Which faction?"
			if not p.has("add") and not p.has("set"):
				return "Add to it or set it."
		"gm_reserve":
			if p.has("remove"):
				var list: Array = story.reserves.get(str(p.get("pilot", "")), [])
				if int(p["remove"]) < 0 or int(p["remove"]) >= list.size():
					return "That pilot doesn't have that reserve."
			else:
				var to := str(p.get("pilot", ""))
				if to != "squad" and not campaign.pilots.has(to):
					return "Which pilot?"
				var rid := str(p.get("reserve", ""))
				if rid == "" or (rid != "custom" and not StoryEffects.is_book_reserve(rid)):
					return "Pick a book reserve, or a custom one with a name."
				if rid == "custom" and str(p.get("name", "")).strip_edges() == "":
					return "Name the custom reserve."
		"gm_job":
			if MissionHooks.data().get("templates", {}).get(str(p.get("template", "")), {}).is_empty():
				return "Pick a kind of job."
			if story.hub.is_empty():
				return "The squad isn't at a hub."
		"gm_edit_job", "gm_remove_job":
			var on_board := story.hooks.any(func(h: Dictionary) -> bool: return str(h["id"]) == str(p.get("hook", "")))
			var current := str(story.current_hook.get("id", "")) == str(p.get("hook", ""))
			if not on_board and not current:
				return "No such job."
			if current and story.phase == "mission":
				return "That job is under way; change it after the mission."
			if type == "gm_edit_job":
				var set: Dictionary = p.get("set", {})
				if current and set.has("briefing"):
					return "Its briefing has already been given."
				var cmd: Variant = set.get("commander", null)
				if cmd is String and str(cmd) != "none" and str(cmd) != "" and not story.npcs.has(str(cmd)):
					return "No such commander."
		"gm_npc":
			if p.has("new"):
				if story.hub.is_empty():
					return "The squad isn't at a hub."
				if str(p["new"].get("name", "")).strip_edges() == "":
					return "Name them."
			elif not story.npcs.has(str(p.get("npc", ""))):
				return "Nobody like that."
	return ""


static func _bad_effect(fx: Variant) -> String:
	if not fx is Dictionary or (fx as Dictionary).is_empty():
		return "A reply's effect isn't one the game knows."
	for k: String in fx:
		if StoryData.EFFECTS.has(k):
			return ""
	return "A reply's effect isn't one the game knows (%s)." % ", ".join(PackedStringArray((fx as Dictionary).keys()))


static func apply(story: StoryState, campaign: Campaign, type: String, p: Dictionary, first_alive: String) -> Array:
	match type:
		"gm_scene":
			var id := str(p.get("id", ""))
			var ctx := {"speaker": str(p.get("speaker", first_alive)), "npc": str(p.get("npc", ""))}
			if id == "":
				id = "gm_%d" % scenes(story).size()
				var all := scenes(story).duplicate()
				all[id] = build_scene(id, p)
				all[id]["ctx"] = ctx
				story.flags[SCENES] = all
				if not bool(p.get("start", true)):
					return [{"type": "gm_scene_saved", "id": id}]
			else:
				ctx = (scenes(story)[id] as Dictionary).get("ctx", ctx).duplicate()
				if p.has("speaker"):
					ctx["speaker"] = str(p["speaker"])
			if not story.is_alive(str(ctx["speaker"])):
				ctx["speaker"] = first_alive
			return Dialogue.start(story, campaign, id, ctx)
		"gm_twist":
			var hook := _hook(story, str(p.get("hook", "")))
			match str(p["do"]):
				"reveal":
					var tw: Dictionary = hook["twist"].duplicate(true)
					hook.erase("twist")
					story.add_log("Twist: %s" % tw.get("reveal", ""))
					return [{"type": "twist_revealed", "twist": tw, "by_gm": true, "rule_ref": REF_TWIST}]
				"hide":
					hook.erase("twist")
					return [{"type": "gm_note", "text": "The twist on %s is gone." % hook.get("title", "the job")}]
				"set":
					hook["twist"] = {"id": "gm", "reveal": str(p["reveal"]), "question": str(p.get("question", "")), "effects": []}
					return [{"type": "gm_note", "text": "A twist is set on %s." % hook.get("title", "the job")}]
		"gm_standing":
			var f := str(p["faction"])
			var add := int(p.get("add", 0)) if not p.has("set") else int(p["set"]) - story.get_standing(f)
			return StoryEffects.apply({"standing": f, "add": add}, story, campaign, {})
		"gm_reserve":
			if p.has("remove"):
				var pid := str(p["pilot"])
				var list: Array = story.reserves[pid]
				var r: Dictionary = list.pop_at(int(p["remove"]))
				var ids: Array = campaign.pilots.get(pid, {}).get("reserves", [])
				ids.erase(str(r.get("id", "")))
				return [{"type": "reserve_removed", "pilot": pid, "reserve": r, "rule_ref": REF_RESERVES}]
			var fx := {"reserve": str(p["reserve"]), "to": str(p["pilot"]), "source": str(p.get("source", "The GM")), "note": str(p.get("note", ""))}
			if str(p["reserve"]) == "custom":
				fx["name"] = str(p["name"])
			return StoryEffects.give_reserve(story, campaign, {"speaker": first_alive}, fx)
		"gm_job":
			var hook := MissionHooks.make(story, campaign, str(p["template"]), {"patron": str(p.get("patron", ""))})
			for k: String in EDITABLE_HOOK:
				if str(p.get(k, "")) != "":
					hook[k] = str(p[k])
			hook["gm"] = true
			story.hooks.append(hook)
			return [{"type": "hook_added", "hook": hook}]
		"gm_edit_job":
			var hook := _hook(story, str(p["hook"]))
			var set: Dictionary = p.get("set", {})
			for k: String in EDITABLE_HOOK:
				if set.has(k):
					hook[k] = str(set[k])
			if set.has("patron_id"):
				hook["patron"] = str(story.npcs.get(str(set["patron_id"]), {}).get("name", hook.get("patron", "")))
			if set.has("briefing"):
				var lines: Array = (set["briefing"] as Array).filter(func(l: Variant) -> bool: return str(l).strip_edges() != "")
				if lines.is_empty():
					hook.erase("briefing_scene")
				else:
					var sid := "gm_brief_%s" % hook["id"]
					var all := scenes(story).duplicate()
					all[sid] = build_scene(sid, {"lines": lines.map(func(l: Variant) -> Dictionary: return {"who": "npc", "text": str(l)})})
					story.flags[SCENES] = all
					hook["briefing_scene"] = sid
			if set.has("commander"):
				var cmd: Variant = set["commander"]
				if cmd is Dictionary:
					var nc: Dictionary = cmd.get("new", cmd)
					var rid := Rivals.make(story, campaign, str(nc.get("faction", hook.get("rival", hook.get("enemy", "")))))
					var r: Dictionary = story.npcs[rid]
					for k: String in ["callsign", "rank", "personality"]:
						if str(nc.get(k, "")) != "":
							r[k] = str(nc[k])
					r["name"] = Rivals.call_name(r)
					hook["commander"] = {"id": rid, "name": Rivals.call_name(r), "returning": false}
				elif str(cmd) in ["none", ""]:
					hook.erase("commander")
				else:
					hook["commander"] = {"id": str(cmd), "name": Rivals.call_name(story.npcs[str(cmd)]), "returning": int(story.npcs[str(cmd)].get("met", 0)) > 0}
			return [{"type": "hook_edited", "hook": hook.duplicate(true)}]
		"gm_remove_job":
			story.hooks = story.hooks.filter(func(h: Dictionary) -> bool: return str(h["id"]) != str(p["hook"]))
			if str(story.current_hook.get("id", "")) == str(p["hook"]):
				story.current_hook = {}
				story.phase = "briefing"
			return [{"type": "hook_removed", "hook": str(p["hook"])}]
		"gm_npc":
			if p.has("new"):
				var nd: Dictionary = p["new"]
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([story.story_seed, story.npcs.size(), "gm_npc"])
				var id := "%s_gm%d" % [story.hub.get("id", "hub"), story.npcs.size()]
				var npc := NpcGen.make_npc(rng, NameGen.new(rng), campaign, story.hub, str(nd.get("role", "local")), id)
				for k: String in EDITABLE_NPC:
					if nd.has(k):
						npc[k] = nd[k]
				story.npcs[id] = npc
				(story.hub["npcs"] as Array).append(id)
				return [{"type": "npc_added", "npc": id, "name": npc["name"]}]
			var npc: Dictionary = story.npcs[str(p["npc"])]
			var set: Dictionary = p.get("set", {})
			for k: String in EDITABLE_NPC:
				if set.has(k):
					npc[k] = set[k]
			return [{"type": "npc_edited", "npc": str(p["npc"]), "fields": set.keys()}]
	return []


## A GM-written conversation as an ordinary scene: the lines in order, then the replies; each
## reply can have a short answer and effects (StoryEffects vocabulary).
static func build_scene(id: String, p: Dictionary) -> Dictionary:
	var nodes := {}
	var lines: Array = p.get("lines", [])
	var choices: Array = p.get("choices", [])
	for i in range(lines.size()):
		var l: Dictionary = lines[i]
		var node := {"speaker": str(l.get("who", "npc")), "line": str(l["text"])}
		if str(l.get("expression", "")) != "":
			node["expression"] = str(l["expression"])
		if i < lines.size() - 1:
			node["next"] = "l%d" % (i + 1)
		elif choices.is_empty():
			node["end"] = true
		else:
			var cs: Array = []
			for j in range(choices.size()):
				var c: Dictionary = choices[j]
				var cc := {"id": "c%d" % j, "text": str(c["text"]), "tags": (c.get("tags", []) as Array).duplicate(),
					"effects": (c.get("effects", []) as Array).duplicate(true), "pinned": true}
				if str(c.get("reply", "")).strip_edges() != "":
					cc["next"] = "r%d" % j
					nodes["r%d" % j] = {"speaker": str(c.get("reply_who", "npc")), "line": str(c["reply"]), "end": true}
				else:
					cc["end"] = true
				cs.append(cc)
			node["choices"] = cs
		nodes["l%d" % i] = node
	return {"id": id, "start": "l0", "nodes": nodes, "_note": "Written by the GM."}


static func _hook(story: StoryState, id: String) -> Dictionary:
	if id == "" or str(story.current_hook.get("id", "")) == id:
		return story.current_hook
	for h: Dictionary in story.hooks:
		if str(h["id"]) == id:
			return h
	return {}
