class_name Rivals
extends RefCounted
## Enemy commanders as characters (data/game/story/rivals.json). Every enemy force has someone
## in charge: a named NPC with a portrait and a personality, who taunts the squad in battle
## and remembers how the last fight went. A story arc's opposition gets one commander for the
## whole arc; a commander who got away can come back for revenge on a later job.
##
## The book: NPCs have objectives of their own and care about self-preservation, surrender and
## retreat are valid ends to a fight, and the GM may end a fight early once its outcome isn't
## in question (Core p.60). So when the fight turns against them, a commander may yield,
## withdraw or offer a deal (their personality decides), and when it turns against the squad,
## some offer to let the squad walk away. The squad can also call on them to stand down once
## the outcome is clear. Either opens the "parley" scene; its choices can end the battle
## ("battle_end_requested", for the flow to turn into gm_end_mission).
##
## The battle being fought is tracked in story.flags["_battle"] (CampaignLoop.build_mission
## sets it up, the StoryEngine "battle_events" action updates it, mission_finished reads it).

const FILE := "res://data/game/story/rivals.json"
const KEY := "_rivals"
const BATTLE := "_battle"
const DEBRIEF := "_rival_debrief"
const REF := "Core p.60: surrender and retreat are valid end-conditions for a fight"
const REF_EARLY := "Core p.60: the GM may end combat early if there are no questions as to the outcome"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func ids(story: StoryState) -> Array:
	return story.flags.get(KEY, [])


## Commanders still out there (not captured or dead).
static func at_large(story: StoryState) -> Array:
	return ids(story).filter(func(id: String) -> bool:
		var r: Dictionary = story.npcs.get(id, {})
		return not r.is_empty() and str(r.get("status", "")) == "active")


static func personality(r: Dictionary) -> Dictionary:
	return data().get("personalities", {}).get(str(r.get("personality", "")), {})


## How lines name them: "Captain Blackjack".
static func call_name(r: Dictionary) -> String:
	return "%s %s" % [r.get("rank", "Commander"), r.get("callsign", "")]


## A new commander for `faction`. `arc_id` ties them to a story arc; `squad` is the enemy
## outfit they lead (the rivalry arc's other lancer squad).
static func make(story: StoryState, campaign: Campaign, faction: String, arc_id: String = "", squad: String = "") -> String:
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, ids(story).size(), faction, "rival"])
	var names := NameGen.new(rng)
	var kinds: Array = (d.get("personalities", {}) as Dictionary).keys()
	var titles: Array = d.get("titles", ["Commander"])
	var id := "rival_%d" % (ids(story).size() + 1)
	var full := names.pilot_name()
	var callsign := names.callsign()
	var parts := full.split(" ", false, 1)
	var rank := str(titles[rng.randi_range(0, titles.size() - 1)])
	var look := {}
	var looks: Dictionary = NpcGen.tables().get("looks", {})
	for k: String in looks:
		var opts: Array = looks[k]
		look[k] = opts[rng.randi_range(0, opts.size() - 1)] if not opts.is_empty() else ""
	look["seed"] = rng.randi()
	var r := {
		"id": id, "name": "%s %s" % [rank, callsign], "full_name": ("%s \"%s\" %s" % [parts[0], callsign, parts[1]]) if parts.size() > 1 else "%s \"%s\"" % [full, callsign],
		"callsign": callsign, "rank": rank, "role": "enemy_commander", "role_name": "Enemy commander",
		"title": "Enemy commander", "leads": squad if squad != "" else (faction if faction != "" else "the enemy force"),
		"faction": faction, "squad": squad, "arc": arc_id, "personality": str(kinds[rng.randi_range(0, kinds.size() - 1)]) if not kinds.is_empty() else "honorable",
		"rival": true, "status": "active", "grudge": 0, "met": 0, "last": "", "history": [],
		"scene": "parley", "spot": "", "tags": [], "offers": [], "trusted_offers": [], "quirk": "", "want": "", "secret": "",
		"look": look, "dead": false,
	}
	r["portrait"] = PortraitSpec.complete(look, rng)
	story.npcs[id] = r
	var list: Array = ids(story).duplicate()
	list.append(id)
	story.flags[KEY] = list
	return id


## Puts a commander on a job (hook["commander"]): the given one (an arc's), or, now and then,
## one with a grudge who comes back for revenge. Uses the hook's own RNG.
static func attach(story: StoryState, hook: Dictionary, rng: RandomNumberGenerator, rival_id: String = "") -> void:
	if bool(hook.get("tutorial", false)):
		return
	var id := rival_id
	if id == "" or not story.npcs.has(id) or str(story.npcs[id].get("status", "")) != "active":
		var taken := story.hooks.map(func(h: Dictionary) -> String: return str(h.get("commander", {}).get("id", "")))
		var pool := at_large(story).filter(func(x: String) -> bool:
			return int(story.npcs[x].get("grudge", 0)) >= 1 and not taken.has(x) and str(story.npcs[x].get("arc", "")) != str(story.arc.get("id", "-")))
		if pool.is_empty() or rng.randi_range(1, 100) > int(data().get("revenge_chance", 25)):
			return
		id = str(pool[rng.randi_range(0, pool.size() - 1)])
	var r: Dictionary = story.npcs[id]
	hook["commander"] = {"id": id, "name": call_name(r), "returning": int(r.get("met", 0)) > 0}
	if int(r.get("met", 0)) > 0:
		var lines: Array = data().get("return_briefing", [])
		if not lines.is_empty():
			hook["commander"]["line"] = fill(str(lines[rng.randi_range(0, lines.size() - 1)]), r)
		hook["stakes"] = "%s %s" % [hook.get("stakes", ""), hook["commander"].get("line", "")]


## Text with the commander's names filled in.
static func fill(text: String, r: Dictionary, extra: Dictionary = {}) -> String:
	var last: Dictionary = data().get("last_time", {})
	var vars := {"rival": call_name(r), "rival_callsign": str(r.get("callsign", "")), "rival_faction": str(r.get("faction", "")) if str(r.get("faction", "")) != "" else "the cause",
		"last_time": str(last.get(str(r.get("last", "")), last.get("", "last time")))}
	vars.merge(extra, true)
	for k: String in vars:
		text = text.replace("{%s}" % k, str(vars[k]))
	return text


# --- In battle ---------------------------------------------------------------------------

## Called when the battle is built: the strongest enemy is the commander (only renamed; no
## stats change), and the fight's tracking starts.
static func setup_battle(story: StoryState, campaign: Campaign, state: GameState, mission: Mission) -> void:
	story.flags.erase(BATTLE)
	var hook := story.current_hook
	if bool(hook.get("tutorial", false)):
		return
	var enemies: Array = []
	var squad: Array = []
	for u: Unit in state.units.values():
		if u.kind == Unit.KIND_DEPLOYABLE or u.kind == Unit.KIND_PILOT:
			continue
		if u.side == Mission.ENEMIES:
			enemies.append(u)
		elif u.side == Mission.PLAYERS:
			squad.append(u)
	if enemies.is_empty():
		return
	enemies.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.max_structure * 100 + a.max_hp > b.max_structure * 100 + b.max_hp if a.max_structure * 100 + a.max_hp != b.max_structure * 100 + b.max_hp else a.id < b.id)
	var lead: Unit = enemies[0]
	var id := str(hook.get("commander", {}).get("id", ""))
	if id == "" or not story.npcs.has(id):
		var faction := str(hook.get("rival", ""))
		id = make(story, campaign, faction if faction != "" else str(hook.get("enemy", "")))
		hook["commander"] = {"id": id, "name": call_name(story.npcs[id]), "returning": false}
	var r: Dictionary = story.npcs[id]
	lead.name = "%s (%s)" % [r.get("callsign", ""), lead.name]
	lead.loadout["rival_id"] = id
	story.flags[BATTLE] = {"rival": id, "unit": lead.id, "enemy_ids": enemies.map(func(u: Unit) -> String: return u.id),
		"squad_ids": squad.map(func(u: Unit) -> String: return u.id), "enemy_down": [], "squad_down": [],
		"rival_structure": lead.structure, "rival_max_structure": lead.max_structure, "rival_destroyed": false,
		"offered": false, "demanded": false, "refused": false, "ended": "", "reason": "", "fate": ""}
	mission.flavor["commander"] = {"id": id, "name": call_name(r), "unit": lead.id, "personality": str(r.get("personality", "")),
		"returning": int(r.get("met", 0)) > 0}


static func battle(story: StoryState) -> Dictionary:
	return story.flags.get(BATTLE, {})


## The fight has turned against the enemy: half their force is down, or the commander is on
## their last structure. PROVISIONAL: our reading of "no questions as to the outcome" (Core
## p.60), which the book leaves to the GM.
static func enemy_losing(b: Dictionary) -> bool:
	if b.is_empty():
		return false
	var total := (b["enemy_ids"] as Array).size()
	if total > 0 and (b["enemy_down"] as Array).size() * 2 >= total:
		return true
	return int(b["rival_max_structure"]) > 1 and int(b["rival_structure"]) <= 1


## ...or against the squad: half its mechs are wrecked.
static func squad_losing(b: Dictionary) -> bool:
	var total := (b.get("squad_ids", []) as Array).size()
	return total > 0 and (b["squad_down"] as Array).size() * 2 >= total


## Reads a batch of battle events (StoryEngine "battle_events"): keeps count, and opens the
## parley when the commander's personality says it's time to talk.
static func observe(story: StoryState, campaign: Campaign, events: Array) -> Array:
	var b := battle(story)
	if b.is_empty() or str(b["ended"]) != "":
		return []
	for e: Dictionary in events:
		var u := str(e.get("unit", ""))
		match str(e.get("type", "")):
			"structure_lost":
				if u == str(b["unit"]):
					b["rival_structure"] = int(e.get("structure", b["rival_structure"]))
			"unit_destroyed":
				if u == str(b["unit"]):
					b["rival_destroyed"] = true
				if (b["enemy_ids"] as Array).has(u) and not (b["enemy_down"] as Array).has(u):
					(b["enemy_down"] as Array).append(u)
				elif (b["squad_ids"] as Array).has(u) and not (b["squad_down"] as Array).has(u):
					(b["squad_down"] as Array).append(u)
			"mission_ended":
				b["ended"] = "over"
	if bool(b["rival_destroyed"]) or bool(b["offered"]) or str(b["ended"]) != "" or Dialogue.is_open(story):
		return []
	var r: Dictionary = story.npcs.get(str(b["rival"]), {})
	var p := personality(r)
	var kind := ""
	if enemy_losing(b):
		kind = str(p.get("when_losing", "yield"))
	elif squad_losing(b):
		kind = str(p.get("when_winning", ""))
	if kind == "":
		return []
	b["offered"] = true
	if kind == "fight":
		return [{"type": "rival_defiant", "rival": b["rival"], "text": fill(_line(story, data().get("parley", {}).get("demand_fight", [])), r)}]
	var out: Array = [{"type": "parley_offered", "rival": b["rival"], "kind": kind, "rule_ref": REF}]
	out.append_array(_open(story, campaign, kind, ""))
	return out


## Why the squad can't call for a parley right now ("" if it can).
static func parley_refusal(story: StoryState, seat: String) -> String:
	var b := battle(story)
	if b.is_empty():
		return "There's no fight to talk your way out of."
	if str(b["ended"]) != "":
		return "The fight is already over."
	if seat != "gm" and not story.seats.has(seat):
		return "Only the squad can call for terms."
	if Dialogue.is_open(story):
		return "Finish the conversation first."
	if bool(b["rival_destroyed"]):
		return "Their commander is out of the fight; there's nobody left to give the order."
	if bool(b["refused"]) or bool(b["demanded"]):
		return "You've already had your chance to talk in this fight."
	if not enemy_losing(b):
		return "Nobody talks terms while they still think they can win. The GM ends a fight early only once its outcome isn't in question (Core p.60)."
	return ""


## The squad calls on the commander to stand down: what they do depends on who they are.
static func demand(story: StoryState, campaign: Campaign, seat: String) -> Array:
	var b := battle(story)
	b["demanded"] = true
	b["offered"] = true
	var speaker := story.pilot_of_seat(seat) if seat != "gm" else ""
	var events: Array = [{"type": "parley_called", "rival": b["rival"], "by": seat, "rule_ref": REF_EARLY}]
	events.append_array(_open(story, campaign, "demand", speaker))
	return events


static func _open(story: StoryState, campaign: Campaign, kind: String, speaker: String) -> Array:
	var b := battle(story)
	var r: Dictionary = story.npcs.get(str(b["rival"]), {})
	var p := personality(r)
	if speaker == "" or not story.is_alive(speaker):
		speaker = _lead_pilot(story, campaign)
	var talk: Dictionary = data().get("parley", {})
	var vars := {"kind": kind, "stance": str(p.get("when_losing", "yield")), "rival": call_name(r),
		"yield_line": fill(_line(story, talk.get("yield", [])), r), "withdraw_line": fill(_line(story, talk.get("withdraw", [])), r),
		"deal_line": fill(_line(story, talk.get("deal", [])), r), "retreat_line": fill(_line(story, talk.get("offer_retreat", [])), r),
		"defiant_line": fill(_line(story, talk.get("demand_fight", [])), r), "refused_line": fill(_line(story, p.get("refused", ["So be it."])), r)}
	return Dialogue.start(story, campaign, "parley", {"speaker": speaker, "npc": str(b["rival"]), "vars": vars})


static func _lead_pilot(story: StoryState, campaign: Campaign) -> String:
	var seats := story.seats.keys()
	seats.sort()
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		if pid != "" and story.is_alive(pid):
			return pid
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			return pid
	return ""


static func _line(story: StoryState, list: Array) -> String:
	return str(list[story.dice.die(list.size()) - 1]) if not list.is_empty() else ""


## Parley effects (StoryEffects): what became of the commander, and ending the fight.
static func set_fate(story: StoryState, fate: String) -> Array:
	var b := battle(story)
	if b.is_empty():
		return []
	b["fate"] = fate
	return []


static func end_battle(story: StoryState, outcome: String, reason: String) -> Array:
	var b := battle(story)
	if b.is_empty() or str(b["ended"]) != "":
		return []
	b["ended"] = outcome
	b["reason"] = reason
	return [{"type": "battle_end_requested", "outcome": outcome, "reason": reason, "rule_ref": REF}]


static func refuse(story: StoryState) -> Array:
	var b := battle(story)
	if not b.is_empty():
		b["refused"] = true
	return [{"type": "parley_refused", "rival": b.get("rival", ""), "text": "The fight goes on."}]


## Speech bubbles for the commander (cosmetic, own RNG; added to Squadmate.barks_for).
static func barks_for(story: StoryState, e: Dictionary) -> Array:
	var b := battle(story)
	if b.is_empty():
		return []
	var r: Dictionary = story.npcs.get(str(b["rival"]), {})
	var p := personality(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([e, story.story_seed, "rival"])
	var moment := ""
	var chance := 1.0
	var u := str(e.get("unit", ""))
	match str(e.get("type", "")):
		"combat_started":
			moment = "start_return" if int(r.get("met", 0)) > 0 else "start"
		"structure_lost":
			if u == str(b["unit"]):
				moment = "hurt"
		"unit_destroyed":
			if u == str(b["unit"]):
				moment = "defeated"
			elif (b["enemy_ids"] as Array).has(u):
				moment = "ally_down"
				chance = 0.6
			elif (b["squad_ids"] as Array).has(u):
				moment = "gloat"
				chance = 0.8
	var lines: Array = p.get(moment, [])
	if moment == "" or lines.is_empty() or rng.randf() > chance:
		return []
	var faces := {"start": "determined", "start_return": "smug", "hurt": "hurt", "ally_down": "worried", "gloat": "smug", "defeated": "shouting"}
	return [{"unit": str(b["unit"]), "pilot": str(b["rival"]), "who": str(r.get("callsign", "")), "rival": true,
		"face": {"portrait": PortraitSpec.for_npc(r), "expression": str(faces.get(moment, "neutral"))},
		"text": fill(str(lines[rng.randi_range(0, lines.size() - 1)]), r)}]


# --- After the mission -------------------------------------------------------------------

## What became of the commander, remembered for next time. Fates not settled by a parley:
## a wrecked commander's pilot got out or didn't (the GM's call, Core p.60: rolled on the
## story dice), otherwise they ran (the squad won) or held the field (the squad lost).
static func after_mission(story: StoryState, outcome: String, hook: Dictionary) -> Array:
	var b := battle(story)
	story.flags.erase(BATTLE)
	story.flags.erase(DEBRIEF)
	if b.is_empty() or not story.npcs.has(str(b["rival"])):
		return []
	var id := str(b["rival"])
	var r: Dictionary = story.npcs[id]
	var fate := str(b.get("fate", ""))
	if fate == "":
		if bool(b["rival_destroyed"]):
			fate = "dead" if story.dice.die(6) <= 2 else "escaped"
		elif outcome == "victory":
			fate = "routed"
		elif outcome == "defeat":
			fate = "won"
		else:
			fate = "withdrew"
	r["met"] = int(r.get("met", 0)) + 1
	r["last"] = fate
	match fate:
		"captured":
			r["status"] = "captured"
		"dead":
			r["status"] = "dead"
			r["dead"] = true
		"escaped":
			r["grudge"] = int(r.get("grudge", 0)) + 2
		"withdrew", "routed":
			r["grudge"] = int(r.get("grudge", 0)) + 1
	(r["history"] as Array).append({"mission": story.mission_number, "fate": fate, "job": str(hook.get("short_title", hook.get("title", "")))})
	var f: Dictionary = data().get("fates", {}).get(fate, {})
	var extra := {"patron": str(hook.get("patron", "your patron"))}
	story.add_log(fill(str(f.get("log", "")), r, extra))
	var lines: Array = f.get("debrief", [])
	var line := fill(_line(story, lines), r, extra)
	story.flags[DEBRIEF] = line
	return [{"type": "rival_fate", "rival": id, "name": call_name(r), "fate": fate, "text": line, "grudge": int(r.get("grudge", 0))}]
