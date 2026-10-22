class_name NarrativeCheck
extends RefCounted
## Skill checks in narrative play (out of mech combat), by the book (Core p.45-47):
## roll 1d20 + one trigger (+2/+4/+6) + Accuracy/Difficulty; 10+ succeeds.
## - Only one trigger counts at a time (Core p.25); triggers never apply to attacks or saves.
## - Invoking a relevant background gives 1 Accuracy (or the GM invokes it for 1 Difficulty)
##   (Core p.20).
## - DIFFICULT: +1 Difficulty. RISKY: consequences on anything under 20, even on a success.
##   HEROIC: only 20+ succeeds, consequences under 20 (Core p.45-46).
## - Teamwork: helpers give +1 (however many), and share the consequences (Core p.45).
## - Pushing it: retry a failed check in the same circumstances; it becomes RISKY. A RISKY
##   check can be pushed only if the GM allows (it becomes HEROIC). HEROIC can't be pushed
##   (Core p.46).
## - Skill challenges: everyone rolls, more successes than failures wins, a tie is a coin
##   flip (Core p.47).
## No dice graphics: the UI shows the total as a pop-up number (StoryCheckPopup).

const TARGET := 10
const REF := "Core p.45: skill checks"
const REF_TRIGGERS := "Core p.25: triggers"
const REF_BACKGROUND := "Core p.20: invoking backgrounds"
const REF_PUSH := "Core p.46: trying again and pushing it"
const REF_TEAMWORK := "Core p.45: teamwork"
const REF_CHALLENGE := "Core p.47: skill challenges"
const SKILLS_FILE := "res://data/lancer-data/skills.json"
const BACKGROUND_TAGS := "res://data/game/story/backgrounds.json"

static var _skill_names: Dictionary = {}
static var _background_tags: Dictionary = {}


## Rolls one check. opts:
##   skills: [trigger ids] that fit this goal (the GM's call on what's relevant)
##   use_trigger: the trigger the player picked (must be in skills and on the pilot); default
##     = the pilot's best relevant one
##   tags: situation tags; a background with a matching tag gives +1 Accuracy
##   against_tags: tags that make the GM invoke the background for +1 Difficulty
##   difficult / risky / heroic: bools; helpers: number of pilots helping
##   accuracy / difficulty: extra (reserves, freeform rewards), sources: [{label, kind, value}]
##   label: what's shown ("Charm the quartermaster"), consequence: what failure costs
## Returns a record shaped like Dice.check plus: outcome ("success" / "success_cost" /
## "fail"), consequence (bool), trigger {id, name, bonus}, level, label, rule_ref.
static func roll(dice: Dice, pilot: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var sources: Array = (opts.get("sources", []) as Array).duplicate(true)
	var acc := int(opts.get("accuracy", 0))
	var diff := int(opts.get("difficulty", 0))
	var level := level_of(opts)
	if bool(opts.get("difficult", false)):
		diff += 1
		sources.append({"label": "Difficult", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "Core p.45: difficult rolls"})
	var bg := background_invoke(pilot, opts.get("tags", []), opts.get("against_tags", []))
	if bg != 0:
		if bg > 0:
			acc += 1
		else:
			diff += 1
		sources.append({"label": "Background: %s" % background_name(pilot), "kind": "accuracy" if bg > 0 else "difficulty",
			"type": "accuracy" if bg > 0 else "difficulty", "value": 1, "rule_ref": REF_BACKGROUND})
	var trig := pick_trigger(pilot, opts.get("skills", []), str(opts.get("use_trigger", "")))
	var bonus := int(trig.get("bonus", 0))
	var bonus_sources: Array = []
	if bonus > 0:
		bonus_sources.append({"label": str(trig["name"]), "value": bonus})
	if int(opts.get("helpers", 0)) > 0:
		bonus += 1
		bonus_sources.append({"label": "Teamwork", "value": 1})
	for b: Dictionary in opts.get("bonuses", []):
		bonus += int(b.get("value", 0))
		bonus_sources.append(b)
	var rec := dice.check(bonus, acc, diff, TARGET, sources)
	var total := int(rec["total"])
	var outcome := "fail"
	match level:
		"heroic":
			outcome = "success" if total >= 20 else "fail"
		"risky":
			outcome = "success" if total >= 20 else ("success_cost" if total >= TARGET else "fail")
		_:
			outcome = "success" if total >= TARGET else "fail"
	rec["success"] = outcome != "fail"
	rec["outcome"] = outcome
	rec["consequence"] = outcome != "success"
	rec["level"] = level
	rec["trigger"] = trig
	rec["bonus_sources"] = bonus_sources
	rec["bonuses"] = bonus_sources
	rec["target_label"] = "Check (20+)" if level == "heroic" else "Check (10+)"
	rec["label"] = str(opts.get("label", "Skill check"))
	rec["consequence_text"] = str(opts.get("consequence", ""))
	rec["pilot"] = str(pilot.get("id", ""))
	rec["rule_ref"] = REF
	return rec


static func level_of(opts: Dictionary) -> String:
	if bool(opts.get("heroic", false)):
		return "heroic"
	if bool(opts.get("risky", false)):
		return "risky"
	return "normal"


## Can a failed goal be tried again in the same circumstances? {"ok", "level", "reason", "rule_ref"}.
## `previous` = the level the failed check had; allow_heroic = the GM's say on pushing a RISKY one.
static func push_level(previous: String, allow_heroic: bool = true) -> Dictionary:
	match previous:
		"normal":
			return {"ok": true, "level": "risky", "reason": "", "rule_ref": REF_PUSH}
		"risky":
			if allow_heroic:
				return {"ok": true, "level": "heroic", "reason": "", "rule_ref": REF_PUSH}
			return {"ok": false, "level": "", "reason": "This was already a RISKY check, and the GM won't let it be pushed further.", "rule_ref": REF_PUSH}
	return {"ok": false, "level": "", "reason": "A HEROIC check can never be pushed further. Change the circumstances first.", "rule_ref": REF_PUSH}


## The trigger that counts: the one asked for if the pilot has it and it fits, otherwise the
## pilot's best fitting one. {id, name, rank, bonus} ({} bonus 0 = rolling with no trigger).
static func pick_trigger(pilot: Dictionary, relevant: Array, wanted: String = "") -> Dictionary:
	var skills: Dictionary = pilot.get("skills", {})
	var best := {"id": "", "name": "No trigger", "rank": 0, "bonus": 0}
	for sid: String in skills:
		if not relevant.is_empty() and not relevant.has(sid):
			continue
		var rank := clampi(int(skills[sid]), 0, 3)
		var t := {"id": sid, "name": trigger_name(sid), "rank": rank, "bonus": rank * 2}
		if wanted != "" and sid == wanted:
			return t
		if int(t["bonus"]) > int(best["bonus"]):
			best = t
	return best


## Every trigger a pilot has: [{id, name, rank, bonus}], best first.
static func triggers_of(pilot: Dictionary) -> Array:
	var out: Array = []
	var skills: Dictionary = pilot.get("skills", {})
	for sid: String in skills:
		out.append({"id": sid, "name": trigger_name(sid), "rank": int(skills[sid]), "bonus": int(skills[sid]) * 2})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bonus"]) > int(b["bonus"]) or (int(a["bonus"]) == int(b["bonus"]) and str(a["name"]) < str(b["name"])))
	return out


static func trigger_name(sid: String) -> String:
	if sid.begins_with("custom:"):
		return sid.substr(7)
	if _skill_names.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKILLS_FILE))
		if data is Array:
			for s: Dictionary in data:
				_skill_names[str(s["id"])] = str(s["name"])
	return str(_skill_names.get(sid, sid.trim_prefix("sk_").replace("_", " ").capitalize()))


## +1 when the pilot's background fits the situation, -1 when the GM invokes it against
## them, 0 otherwise.
static func background_invoke(pilot: Dictionary, tags: Array, against: Array) -> int:
	var bg_tags := background_tags(str(pilot.get("background", "")))
	for t: String in against:
		if bg_tags.has(t):
			return -1
	for t: String in tags:
		if bg_tags.has(t):
			return 1
	return 0


static func background_tags(bg_id: String) -> Array:
	if _background_tags.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BACKGROUND_TAGS))
		_background_tags = data.get("backgrounds", {}) if data is Dictionary else {"_": {}}
	return (_background_tags.get(bg_id, {}) as Dictionary).get("tags", [])


static func background_name(pilot: Dictionary) -> String:
	var bg := str(pilot.get("background", ""))
	background_tags(bg)
	return str((_background_tags.get(bg, {}) as Dictionary).get("name", bg.trim_prefix("pbg_").capitalize()))


## A skill challenge (Core p.47): every listed pilot rolls; more successes than failures
## wins; a tie is a coin flip. `per_pilot` = pilot id -> opts for roll().
## Returns {"success", "checks": [records], "successes", "failures", "tiebreak" (d2 or 0)}.
static func challenge(dice: Dice, pilots: Array, opts: Dictionary, per_pilot: Dictionary = {}) -> Dictionary:
	var checks: Array = []
	var ok := 0
	for p: Dictionary in pilots:
		var o := opts.duplicate(true)
		o.merge(per_pilot.get(str(p.get("id", "")), {}), true)
		var rec := roll(dice, p, o)
		checks.append(rec)
		if rec["success"]:
			ok += 1
	var bad := checks.size() - ok
	var tie := 0
	var success := ok > bad
	if ok == bad:
		tie = dice.die(2)
		success = tie == 2
	return {"success": success, "checks": checks, "successes": ok, "failures": bad, "tiebreak": tie, "rule_ref": REF_CHALLENGE}
