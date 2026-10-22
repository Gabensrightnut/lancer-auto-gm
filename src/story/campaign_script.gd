class_name CampaignScript
extends RefCounted
## The authored main campaign for AI-GM play (DESIGN.md section 11), read from
## data/game/story/campaign/<id>.json ("The Long Arrival"). The plot comes only from that
## data; the procedural generator fills in names, maps, enemy mixes and line variants. With a
## human GM, nothing here runs (the GM makes things up with GmTools).
##
## Each chapter is one mission plus the town play around it. What the squad does (in
## conversations, or in town: sneaking, stealing, following) sets story flags; when the
## chapter ends (at the end of the downtime after its mission, or straight after a final
## battle), its branch is resolved from them and the next chapter is picked. Chapters can
## move the squad to another world. Final battles differ in who's at your side (allied units),
## who you fight (enemy mix and commander) and where (the town, the dock, the ship).
##
## State in story.flags["_campaign"]: {id, chapter, branches: {b1: outcome, ...}, done, line,
## worlds, commanders, ending}.

const DIR := "res://data/game/story/campaign/"
const KEY := "_campaign"
const PREFIX := "cs_"

static var _cache: Dictionary = {}


static func data(id: String) -> Dictionary:
	if not _cache.has(id):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json")) if FileAccess.file_exists(DIR + id + ".json") else null
		_cache[id] = d if d is Dictionary else {}
	return _cache[id]


static func active(campaign: Campaign) -> bool:
	return campaign != null and str(campaign.options.get("story_mode", "")) == "campaign" and str(campaign.options.get("campaign_script", "")) != ""


static func script(campaign: Campaign) -> Dictionary:
	return data(str(campaign.options.get("campaign_script", "")))


static func state(story: StoryState) -> Dictionary:
	return story.flags.get(KEY, {})


static func chapter(story: StoryState, campaign: Campaign) -> Dictionary:
	return script(campaign).get("chapters", {}).get(str(state(story).get("chapter", "")), {})


## An authored scene by id, from any campaign file that's been loaded (Dialogue.scene_of).
static func find_scene(id: String) -> Dictionary:
	for k: String in _cache:
		var sc: Dictionary = (_cache[k] as Dictionary).get("scenes", {})
		if sc.has(id):
			return sc[id]
	return {}


## The story id of an authored NPC ("ione" -> "cs_ione").
static func npc(local: String) -> String:
	return local if local.begins_with(PREFIX) else PREFIX + local


# --- Starting --------------------------------------------------------------------------

## Starts the main campaign in a fresh campaign: the first world's town, its people, the
## first chapter.
static func begin(story: StoryState, campaign: Campaign, engine: StoryEngine, id: String = "long_arrival") -> Array:
	campaign.options["story_mode"] = "campaign"
	campaign.options["campaign_script"] = id
	var sd := data(id)
	story.flags[KEY] = {"id": id, "chapter": "", "branches": {}, "done": [], "worlds": {}, "commanders": {}}
	var worlds: Dictionary = sd.get("worlds", {})
	var town: Dictionary = worlds[worlds.keys()[0]] if not worlds.is_empty() else {}
	var events: Array = engine.submit(story, campaign, {"type": "enter_hub", "seat": "gm", "params": {"kind": str(town.get("kind", "town")),
		"seed": absi(hash([campaign.id, id])) % 100000, "culture": str(town.get("culture", "")), "no_jobs": true}})["events"]
	_shape_sector(story, campaign)
	events.append({"type": "campaign_premise", "title": str(sd.get("name", "")), "text": str(sd.get("premise", ""))})
	events.append_array(start_chapter(story, campaign, str(sd.get("first", ""))))
	return events


## The authored worlds take the sector's first places: the town, then the dock.
static func _shape_sector(story: StoryState, campaign: Campaign) -> void:
	var sec := Sector.get_sector(story)
	var worlds: Dictionary = script(campaign).get("worlds", {})
	var ids := {}
	var slots := ["w_0_0", "w_0_1", "w_1_0", "w_1_1", "w_2_0"]
	var n := 0
	for key: String in worlds:
		ids[key] = str(worlds[key].get("slot", slots[mini(n, slots.size() - 1)]))
		n += 1
	for key: String in ids:
		var w := Sector.world(story, str(ids[key]))
		var def: Dictionary = worlds.get(key, {})
		if w.is_empty() or def.is_empty():
			continue
		for f: String in ["name", "culture", "kind", "landscape"]:
			if def.has(f):
				w[f] = def[f]
		var kit: Dictionary = NpcGen.cultures().get(str(w["culture"]), {})
		w["culture_name"] = str(kit.get("name", w["culture"]))
		w["summary"] = str(kit.get("summary", ""))
		state(story)["worlds"][key] = ids[key]
	if not sec.is_empty():
		var first := str(worlds.keys()[0]) if not worlds.is_empty() else "town"
		var def: Dictionary = worlds.get(first, {})
		story.hub["planet"] = str(def.get("name", story.hub.get("planet", "")))
		story.hub["name"] = str(def.get("hub", story.hub.get("name", "")))
		story.hub["landscape"] = str(def.get("landscape", story.hub.get("landscape", "")))
		Sector.current(story)["hub_name"] = story.hub["name"]
	populate(story, campaign)


static func _world_key(story: StoryState) -> String:
	var at := str(Sector.get_sector(story).get("at", ""))
	var ws: Dictionary = state(story).get("worlds", {})
	for k: String in ws:
		if str(ws[k]) == at:
			return k
	return ""


## The authored people of this world join its hub (taking the place of a generated person in
## the same job), and the things they keep are where they keep them.
static func populate(story: StoryState, campaign: Campaign) -> void:
	if not active(campaign) or story.hub.is_empty():
		return
	var here := _world_key(story)
	var sd := script(campaign)
	var factions: Dictionary = sd.get("factions", {})
	# The world's own look for its hub: renamed buildings (a ship's mess, engineering, the
	# captain's quarters) and what it has (a flash-clone vat...).
	var wdef: Dictionary = sd.get("worlds", {}).get(here, {})
	for sp: Dictionary in story.hub.get("spots", []):
		if wdef.get("spot_names", {}).has(str(sp["kind"])):
			sp["name"] = str(wdef["spot_names"][str(sp["kind"])])
	if wdef.has("room_names"):
		story.hub["room_names"] = (wdef["room_names"] as Dictionary).duplicate(true)
	# What's inside its buildings (HubInterior): a ship's deck, a sleeper vault.
	if wdef.has("interiors"):
		story.hub["interiors"] = (wdef["interiors"] as Dictionary).duplicate(true)
	for k: String in wdef.get("hub_flags", {}):
		story.hub[k] = wdef["hub_flags"][k]
	if wdef.has("hub") and str(story.hub.get("name", "")) != str(wdef["hub"]) and not bool(story.hub.get("_named", false)):
		story.hub["name"] = str(wdef["hub"])
		story.hub["_named"] = true
		Sector.current(story)["hub_name"] = story.hub["name"]
	for local: String in sd.get("npcs", {}):
		var def: Dictionary = sd["npcs"][local]
		if str(def.get("world", "")) != here:
			continue
		var id := npc(local)
		if not story.npcs.has(id):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([story.story_seed, id])
			var made := NpcGen.make_npc(rng, NameGen.new(rng), campaign, story.hub, str(def.get("role", "local")), id)
			for k: String in ["name", "title", "personality", "spot", "scene", "schedule"]:
				if def.has(k):
					made[k] = def[k]
			made["faction"] = str(factions.get(str(def.get("faction", "")), def.get("faction", "")))
			made["authored"] = true
			made["trust"] = 0
			story.npcs[id] = made
		var list: Array = story.hub.get("npcs", [])
		# Someone who isn't here (not yet come aboard, marooned, dead) isn't in the hub.
		if def.has("if") and not check(story, campaign, def["if"], {}):
			list.erase(id)
			continue
		if list.has(id):
			continue
		var replaces := str(def.get("replaces", ""))
		if replaces != "":
			for other: String in list.duplicate():
				if str(story.npcs.get(other, {}).get("role", "")) == replaces and not bool(story.npcs[other].get("authored", false)):
					list.erase(other)
					break
		list.append(id)
		story.hub["npcs"] = list
	for it: Dictionary in sd.get("items", []):
		var owner := npc(str(it.get("owner", "")))
		if (story.hub.get("npcs", []) as Array).has(owner) and TownLife.item(story, str(it["id"])).is_empty():
			var spec := it.duplicate(true)
			spec["owner"] = owner
			TownLife.add_item(story, spec)


# --- Chapters ----------------------------------------------------------------------------

## Begins a chapter: travel if it's on another world, its intro, its job on the board.
static func start_chapter(story: StoryState, campaign: Campaign, cid: String) -> Array:
	var st := state(story)
	var ch: Dictionary = script(campaign).get("chapters", {}).get(cid, {})
	if ch.is_empty():
		return []
	st["chapter"] = cid
	var events: Array = []
	var want := str(st.get("worlds", {}).get(str(ch.get("world", "")), ""))
	if want != "" and want != str(Sector.get_sector(story).get("at", "")):
		var saved_phase := story.phase
		story.phase = "downtime"
		events.append_array(Sector.travel(story, campaign, want))
		story.phase = saved_phase
	# Who's around changes with the story (Hask comes aboard, the old captain leaves).
	populate(story, campaign)
	story.hooks = story.hooks.filter(func(h: Dictionary) -> bool: return not h.has("chapter"))
	var intro := " ".join(PackedStringArray((ch.get("intro", []) as Array).map(func(t: String) -> String: return fill(story, campaign, t, ch))))
	events.append({"type": "chapter_started", "chapter": cid, "act": int(ch.get("act", 1)), "act_name": str(ch.get("act_name", "")), "title": str(ch.get("title", "")), "text": intro})
	story.add_log("%s: %s" % [ch.get("title", ""), intro])
	for h: Dictionary in fill_board(story, campaign):
		events.append({"type": "hook_added", "hook": h})
	# Work for the people aboard the squad's ship (ShipLife).
	for h: Dictionary in ShipLife.side_jobs(story, campaign):
		events.append({"type": "hook_added", "hook": h})
	if bool(ch.get("final", false)):
		var names: Array = (fill_allies(story, campaign) as Array).map(func(a: Dictionary) -> String: return a["name"])
		st["branches"]["b13"] = ", ".join(PackedStringArray(names)) if not names.is_empty() else "alone"
	return events


## The current chapter's job, when the squad is on its world (MissionHooks.fill_board in
## campaign mode: no procedural jobs).
static func fill_board(story: StoryState, campaign: Campaign) -> Array:
	var cid := str(state(story).get("chapter", ""))
	var ch := chapter(story, campaign)
	if ch.is_empty() or str(state(story).get("worlds", {}).get(str(ch.get("world", "")), "")) != str(Sector.get_sector(story).get("at", "")):
		return []
	if story.hooks.any(func(h: Dictionary) -> bool: return str(h.get("chapter", "")) == cid) or str(story.current_hook.get("chapter", "")) == cid:
		return []
	if (state(story).get("done", []) as Array).has(cid):
		return []
	var hook := build_hook(story, campaign, cid)
	story.hooks.push_front(hook)
	return [hook]


static func build_hook(story: StoryState, campaign: Campaign, cid: String) -> Dictionary:
	var sd := script(campaign)
	var ch: Dictionary = sd.get("chapters", {})[cid]
	var hs: Dictionary = (ch.get("hook", {}) as Dictionary).duplicate(true)
	# The job can take another shape from what the squad has done (a challenge instead of a
	# mutiny...): the first matching variant's fields replace the job's.
	for v: Dictionary in hs.get("variants", []):
		if check(story, campaign, v.get("if"), {}):
			for k: String in v:
				if k != "if":
					hs[k] = v[k]
			if not v.has("foes_var") and v.has("npc_templates"):
				hs.erase("foes_var")
			break
	var hook := MissionHooks.make(story, campaign, str(hs.get("template", "clear_raiders")), {"patron": npc(str(hs.get("patron", "")))})
	hook.erase("twist")
	hook.erase("commander")
	for k: String in ["title", "objective", "stakes", "question", "place", "enemy"]:
		if hs.has(k):
			hook[k] = fill(story, campaign, str(hs[k]), ch)
	for k: String in ["sitrep", "landscape"]:
		if hs.has(k):
			hook[k] = str(hs[k])
	if hs.has("boarding"):
		hook["boarding"] = (hs["boarding"] as Dictionary).duplicate()
		hook["landscape"] = ""
	# Rules environments the story calls for (zero-g aboard a ship with its systems dead, Core p.63).
	for env: Dictionary in hs.get("environments_if", []):
		if check(story, campaign, env.get("if"), {}):
			hook["environments"] = (env["ids"] as Array).duplicate()
			break
	if bool(hs.get("in_town", false)):
		hook["in_town"] = true
		hook["town_spot"] = "plaza"
	var mix: Array = hs.get("npc_templates", [])
	if hs.has("foes_var"):
		mix = sd.get("enemy_mixes", {}).get(fill(story, campaign, str(hs["foes_var"]), ch), [])
	hook["npc_templates"] = mix
	var cmd := fill(story, campaign, str(hs.get("commander", "")), ch)
	if cmd != "":
		var rid := commander(story, campaign, cmd)
		if story.npcs.has(rid) and str(story.npcs[rid].get("status", "active")) == "active":
			hook["commander"] = {"id": rid, "name": Rivals.call_name(story.npcs[rid]), "returning": int(story.npcs[rid].get("met", 0)) > 0}
	if bool(ch.get("final", false)):
		hook["allies"] = fill_allies(story, campaign)
	var betrayer := str(state(story).get("betrayer", ""))
	if betrayer != "" and not bool(state(story).get("betrayal_used", false)):
		state(story)["betrayal_used"] = true
		hook["twist"] = {"id": "betrayal", "reveal": "%s sold you out: the enemy knew exactly where you'd be." % story.npcs.get(betrayer, {}).get("name", "Someone"),
			"question": "Why did they turn on you?", "effects": [{"set_flag": "la_betrayed"}]}
	if hs.has("loot"):
		hook["loot"] = {"name": fill(story, campaign, str(hs["loot"].get("name", "")), ch), "value": int(hs["loot"].get("value", 200)), "reserve": str(hs["loot"].get("reserve", "reserve_supplies"))}
	hook["chapter"] = cid
	hook["short_title"] = str(hook["title"])
	var lines: Array = (ch.get("briefing", []) as Array).map(func(t: String) -> Dictionary: return {"who": "npc", "text": fill(story, campaign, t, ch)})
	if not lines.is_empty():
		var sid := "cs_brief_%s" % cid
		var all: Dictionary = GmTools.scenes(story).duplicate()
		all[sid] = GmTools.build_scene(sid, {"lines": lines})
		story.flags[GmTools.SCENES] = all
		hook["briefing_scene"] = sid
	return hook


## An authored enemy commander, made once and remembered (Rivals keeps their fate).
static func commander(story: StoryState, campaign: Campaign, key: String) -> String:
	var map: Dictionary = state(story).get("commanders", {})
	if map.has(key) and story.npcs.has(str(map[key])):
		return str(map[key])
	var def: Dictionary = script(campaign).get("commanders", {}).get(key, {})
	if def.is_empty():
		return ""
	var rid := Rivals.make(story, campaign, str(def.get("faction", "")))
	var r: Dictionary = story.npcs[rid]
	for k: String in ["callsign", "rank", "personality"]:
		if def.has(k):
			r[k] = def[k]
	r["name"] = Rivals.call_name(r)
	map[key] = rid
	state(story)["commanders"] = map
	return rid


static func fill_allies(story: StoryState, campaign: Campaign) -> Array:
	var out: Array = []
	for a: Dictionary in script(campaign).get("allies", []):
		if check(story, campaign, a.get("if"), {}):
			out.append({"name": str(a["name"]), "template": str(a["template"]), "count": int(a.get("count", 1))})
	return out


## Text with the campaign's variables ({final_foe}, {dock_line}...): the first matching line.
static func fill(story: StoryState, campaign: Campaign, text: String, ch: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var vars: Dictionary = (script(campaign).get("vars", {}) as Dictionary).duplicate()
	vars.merge(ch.get("intro_vars", {}), true)
	var foe := _final_foe(story, campaign)
	text = text.replace("{final_foe}", str(foe.get("foe", ""))).replace("{final_foes}", str(foe.get("foes", ""))).replace("{final_commander}", str(foe.get("commander", "")))
	for k: String in vars:
		if text.contains("{%s}" % k):
			for opt: Dictionary in vars[k]:
				if check(story, campaign, opt.get("if"), {}):
					text = text.replace("{%s}" % k, str(opt["text"]))
					break
	# The pilot with a grudge (Agendas), by callsign.
	var sore := Agendas.anyone(story, "grievance")
	return text.replace("{aggrieved}", str(campaign.pilots.get(sore, {}).get("callsign", "one of the pilots")))


static func _final_foe(story: StoryState, campaign: Campaign) -> Dictionary:
	for f: Dictionary in script(campaign).get("final_foe", []):
		if check(story, campaign, f.get("if"), {}):
			return f
	return {}


## Which way Act 1 leaned: the Sleepers, the town or the company.
static func line_of(story: StoryState, campaign: Campaign) -> String:
	var st := state(story)
	if st.has("line"):
		return str(st["line"])
	var best := "sleepers"
	var top := -1
	var lines: Dictionary = script(campaign).get("lines", {})
	for k: String in lines:
		var n := 0
		for c: Variant in lines.get(k, []):
			if check(story, campaign, c, {}):
				n += 1
		if n > top:
			top = n
			best = k
	return best


## Conditions: the story's own (flags, trust, standing...) plus {line}, {rival, fate}, {won},
## {final_lost}.
static func check(story: StoryState, campaign: Campaign, cond: Variant, ctx: Dictionary) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c: Variant in cond:
			if not check(story, campaign, c, ctx):
				return false
		return true
	var c: Dictionary = cond
	if c.has("not"):
		return not check(story, campaign, c["not"], ctx)
	if c.has("any"):
		return (c["any"] as Array).any(func(x: Variant) -> bool: return check(story, campaign, x, ctx))
	if c.has("line"):
		return line_of(story, campaign) == str(c["line"])
	if c.has("rival"):
		var rid := str(state(story).get("commanders", {}).get(str(c["rival"]), ""))
		return rid != "" and str(story.npcs.get(rid, {}).get("last", "")) == str(c["fate"])
	if c.has("won"):
		return bool(ctx.get("won", true)) == bool(c["won"])
	if c.has("final_lost"):
		return bool(ctx.get("final_lost", false)) == bool(c["final_lost"])
	if c.has("trust"):
		var t := int(story.npcs.get(npc(str(c["trust"])), {}).get("trust", 0))
		return t >= int(c.get("min", -99)) and t <= int(c.get("max", 99))
	return StoryConditions.check(c, story, campaign, {})


# --- After a mission ---------------------------------------------------------------------

## Remembers how the chapter's mission went; a final battle ends the campaign.
static func after_mission(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool) -> Array:
	if not active(campaign) or not hook.has("chapter"):
		return []
	var st := state(story)
	var cid := str(hook["chapter"])
	var ch: Dictionary = script(campaign).get("chapters", {}).get(cid, {})
	st["won"] = won
	(st["done"] as Array).append(cid)
	st["aftermath"] = cid
	if bool(ch.get("final", false)):
		var events := _resolve(story, campaign, cid, {"won": won, "final_lost": not won})
		var ending := _ending(story, campaign, not won)
		st["ending"] = ending.get("id", "")
		st["branches"]["b18"] = st["ending"]
		events.append({"type": "campaign_ending_due", "ending": st["ending"]})
		return events
	return []


## At the end of the downtime after a chapter's mission: its branch, then the next chapter.
static func advance(story: StoryState, campaign: Campaign) -> Array:
	if not active(campaign):
		return []
	var st := state(story)
	var cid := str(st.get("chapter", ""))
	if not (st.get("done", []) as Array).has(cid) or st.has("ending"):
		return []
	var events := _resolve(story, campaign, cid, {"won": bool(st.get("won", true))})
	var ch: Dictionary = script(campaign).get("chapters", {})[cid]
	var line_act := int(script(campaign).get("line_act", 1))
	if int(ch.get("act", 1)) == line_act and not st.has("line"):
		var nxt_act := 1
		for n: Dictionary in ch.get("next", []):
			nxt_act = int(script(campaign)["chapters"].get(str(n.get("chapter", "")), {}).get("act", 1))
		if nxt_act > line_act:
			st["line"] = line_of(story, campaign)
			events.append({"type": "story_line", "line": st["line"]})
	for n: Dictionary in ch.get("next", []):
		if check(story, campaign, n.get("if"), {}):
			events.append_array(start_chapter(story, campaign, str(n["chapter"])))
			break
	return events


static func _resolve(story: StoryState, campaign: Campaign, cid: String, ctx: Dictionary) -> Array:
	var st := state(story)
	var ch: Dictionary = script(campaign).get("chapters", {})[cid]
	var events: Array = []
	var br: Dictionary = st["branches"]
	for key: String in ["outcomes", "b10"]:
		var bid := str(ch.get("branch", "")) if key == "outcomes" else "b10"
		if not ch.has(key) or bid == "":
			continue
		for o: Dictionary in ch[key]:
			if check(story, campaign, o.get("if"), ctx):
				br[bid] = str(o["set"])
				events.append_array(StoryEffects.apply_all(ch.get("on_resolve", {}).get(str(o["set"]), []), story, campaign, {}))
				break
	for bid: String in ch.get("rival_branches", {}):
		var rid := str(st.get("commanders", {}).get(str(ch["rival_branches"][bid]), ""))
		br[bid] = str(story.npcs.get(rid, {}).get("last", "")) if rid != "" else "absent"
		if br[bid] == "":
			br[bid] = "absent"
	if ch.has("betrayal"):
		var worst := ""
		var low := -2
		for local: String in script(campaign).get("npcs", {}):
			var t := int(story.npcs.get(npc(local), {}).get("trust", 0))
			if story.npcs.has(npc(local)) and t <= low:
				low = t
				worst = npc(local)
		br[str(ch["betrayal"])] = worst.trim_prefix(PREFIX) if worst != "" else "none"
		st["betrayer"] = worst
	events.append({"type": "branch_resolved", "chapter": cid, "branches": br.duplicate()})
	return events


static func _ending(story: StoryState, campaign: Campaign, lost: bool) -> Dictionary:
	for e: Dictionary in script(campaign).get("endings", []):
		if check(story, campaign, e.get("if"), {"final_lost": lost}):
			return e
	return {}


## The authored ending dressed onto Ending's record (title, kind, the story's last words).
static func decorate(story: StoryState, campaign: Campaign, ending: Dictionary) -> void:
	var id := str(state(story).get("ending", ""))
	for e: Dictionary in script(campaign).get("endings", []):
		if str(e.get("id", "")) == id:
			ending["kind"] = str(e.get("kind", ending.get("kind", "")))
			ending["label"] = str(e.get("title", ending.get("label", "")))
			ending["title"] = str(e.get("title", ending.get("title", "")))
			ending["story"] = str(e.get("text", ""))
			ending["chain"] = (state(story).get("branches", {}) as Dictionary).duplicate()


## The conversation after a chapter's mission (first thing in downtime): what the squad
## decides there is part of the chapter's branch.
static func aftermath(story: StoryState, campaign: Campaign, first_alive: String) -> Array:
	var st := state(story)
	var cid := str(st.get("aftermath", ""))
	st.erase("aftermath")
	var ch: Dictionary = script(campaign).get("chapters", {}).get(cid, {})
	if ch.is_empty() or Dialogue.is_open(story):
		return []
	# The pilot with a grudge speaks first (Agendas): they're the one pushing.
	var sore := Agendas.anyone(story, str(ch.get("speaker_agenda", "")))
	if str(ch.get("speaker_agenda", "")) != "" and sore != "":
		first_alive = sore
	if ch.has("aftermath_scene"):
		var a: Dictionary = ch["aftermath_scene"]
		return Dialogue.start(story, campaign, str(a["scene"]), {"speaker": first_alive, "npc": npc(str(a.get("npc", "")))})
	var am: Dictionary = ch.get("aftermath", {})
	if am.is_empty() or not check(story, campaign, am.get("if"), {}):
		return []
	var sid := "cs_after_%s" % cid
	var scene := GmTools.build_scene(sid, {"lines": am.get("lines", []), "choices": (am.get("choices", []) as Array).map(func(c: Dictionary) -> Dictionary:
		var cc := c.duplicate(true)
		for fx: Dictionary in cc.get("effects", []):
			if fx.has("trust"):
				fx["trust"] = npc(str(fx["trust"]))
		return cc)})
	if am.has("mode"):
		scene["mode"] = str(am["mode"])
		scene["channel"] = str(am.get("channel", ""))
	var all: Dictionary = GmTools.scenes(story).duplicate()
	all[sid] = scene
	story.flags[GmTools.SCENES] = all
	return Dialogue.start(story, campaign, sid, {"speaker": first_alive, "npc": npc(str(am.get("npc", "")))})


## A clone wakes (Cloning): whoever runs the ship has something to say about it (the
## script's "clone_beats": the first whose "if" holds, {if, npc, lines}).
static func on_clone(story: StoryState, campaign: Campaign, pid: String) -> Array:
	if not active(campaign):
		return []
	story.flags["cloned_" + pid] = true
	story.flags["dr_cloned"] = true
	for b: Dictionary in script(campaign).get("clone_beats", []):
		if not check(story, campaign, b.get("if"), {}):
			continue
		var cs := str(campaign.pilots[pid].get("callsign", ""))
		var lines: Array = (b.get("lines", []) as Array).map(func(l: Dictionary) -> Dictionary: return {"who": l.get("who", "npc"), "text": str(l["text"]).replace("{name}", cs)})
		var sid := "cs_clone_%s" % pid
		var all: Dictionary = GmTools.scenes(story).duplicate()
		all[sid] = GmTools.build_scene(sid, {"lines": lines})
		story.flags[GmTools.SCENES] = all
		if Dialogue.is_open(story):
			return [{"type": "clone_beat", "pilot": pid, "text": str(lines[0]["text"]) if not lines.is_empty() else ""}]
		var ev := Dialogue.start(story, campaign, sid, {"speaker": pid, "npc": npc(str(b.get("npc", "")))})
		ev.push_front({"type": "clone_beat", "pilot": pid, "text": str(lines[0]["text"]) if not lines.is_empty() else ""})
		return ev
	return []
