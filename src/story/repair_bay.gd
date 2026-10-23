class_name RepairBay
extends RefCounted
## Mech damage that lasts, and the Full Repair that fixes it (Core p.82: 10 hours somewhere
## secure). After every mission each squad mech's condition is kept (HP, structure, stress,
## Repairs, CORE power, Limited charges, destroyed weapons and systems, or the mech wrecked)
## and carried into the next fight. A Full Repair at a repair bay (every hub has one: the
## mech gantries, a ship's hangar or engineering) puts every mech back to full, reprints a
## wrecked one and restores the pilots. Nothing but canon costs keeps it from being free:
##   - the 10 hours really pass (the TownLife clock, so people's days move on), the squad
##     eats (with the food-and-water house rule), and the enemy has those hours too (the next
##     fight in the region has one more enemy: they regrouped);
##   - it needs somewhere secure: a hub, or a safe point (region maps' "safe_point") with no
##     enemies left in the area; not while the alarm is up;
##   - between fights inside a mission there's only a Rest (spend Repairs), never this.
## Kept in story.flags["_mechs"] = {pilot id: condition}, "_regroup" = extra enemies due.
##
## StoryEngine action: full_repair {}. Effect {"full_repair": true} (the bay's conversation).

const KEY := "_mechs"
const REGROUP := "_regroup"
const REF := "Core p.82: full repair"
const HOURS := 10
## TownLife periods (dawn, day, evening, night) are about six hours: 10 hours is two of them.
const PERIODS := 2
const PLAIN := "Full Repair: 10 hours. Fixes everything and reprints a lost mech. Only somewhere safe."


static func condition(story: StoryState, pid: String) -> Dictionary:
	return story.flags.get(KEY, {}).get(pid, {})


static func wrecked(story: StoryState, pid: String) -> bool:
	return bool(condition(story, pid).get("wrecked", false))


## Whether any mech in the squad needs a Full Repair.
static func needed(story: StoryState) -> bool:
	return not (story.flags.get(KEY, {}) as Dictionary).is_empty()


## After a mission: how each squad mech came out of it (nothing kept for a mech in full shape).
static func record(story: StoryState, state: GameState) -> void:
	var all: Dictionary = (story.flags.get(KEY, {}) as Dictionary).duplicate(true)
	for u: Unit in state.units.values():
		if u.kind != Unit.KIND_MECH or u.side != Mission.PLAYERS:
			continue
		var pid := story.pilot_of_seat(u.controller)
		if pid == "":
			continue
		if u.destroyed:
			all[pid] = {"wrecked": true}
			continue
		var c := {}
		if u.hp < u.max_hp:
			c["hp"] = u.hp
		if u.structure < u.max_structure:
			c["structure"] = u.structure
		if u.stress < u.max_stress:
			c["stress"] = u.stress
		c["repairs"] = u.repairs
		c["core_power"] = int(u.counters.get("core_power", 1))
		var spent := false
		for k: String in ["weapons", "sources"]:
			var kept := {}
			for key: String in u.counters.get(k, {}):
				var st: Dictionary = u.counters[k][key]
				if bool(st.get("destroyed", false)) or int(st.get("uses", -1)) >= 0:
					kept[key] = {"destroyed": bool(st.get("destroyed", false)), "uses": int(st.get("uses", -1))}
					spent = spent or bool(st.get("destroyed", false))
			if not kept.is_empty():
				c[k] = kept
		var hurt := c.has("hp") or c.has("structure") or c.has("stress") or spent or int(c["core_power"]) <= 0
		if hurt or _limited_spent(u, c):
			all[pid] = c
		else:
			all.erase(pid)
	story.flags[KEY] = all


## Limited charges used up since the mission began (apply() noted what it started with).
static func _limited_spent(u: Unit, c: Dictionary) -> bool:
	var start: Dictionary = u.counters.get("_start_uses", {})
	for k: String in ["weapons", "sources"]:
		for key: String in c.get(k, {}):
			var now := int(c[k][key]["uses"])
			if now >= 0 and now < int(start.get(key, now)):
				return true
	return false


## Before a mission: the squad mech goes in as it came out of the last one.
static func apply(story: StoryState, pid: String, mech: Unit) -> void:
	var c := condition(story, pid)
	# Remember the Limited charges a fresh mech starts with, to tell later whether any were spent.
	var start := {}
	for k: String in ["weapons", "sources"]:
		for key: String in mech.counters.get(k, {}):
			start[key] = int(mech.counters[k][key].get("uses", -1))
	if c.is_empty() or bool(c.get("wrecked", false)):
		mech.counters["_start_uses"] = start
		return
	for f: String in ["hp", "structure", "stress", "repairs"]:
		if c.has(f):
			mech.set(f, int(c[f]))
	if c.has("core_power"):
		mech.counters["core_power"] = int(c["core_power"])
	for k: String in ["weapons", "sources"]:
		if not c.has(k):
			continue
		if not mech.counters.has(k):
			mech.counters[k] = {}
		for key: String in c[k]:
			var st: Dictionary = (mech.counters[k] as Dictionary).get(key, {"loaded": true})
			if not (mech.counters[k] as Dictionary).has(key) and int(c[k][key]["uses"]) >= 0:
				start[key] = int(c[k][key]["uses"])
			st["destroyed"] = bool(c[k][key]["destroyed"])
			st["uses"] = int(c[k][key]["uses"])
			mech.counters[k][key] = st
	mech.counters["_start_uses"] = start


# --- The Full Repair -------------------------------------------------------------------------

## Where the squad can do it: any hub (the gantries, a ship's hangar), or a safe point the flow
## marks with story.flags["_safe_point"] once its area is clear. Not with the alarm up.
static func secure_refusal(story: StoryState) -> String:
	if story.phase == "mission":
		return "Not in the middle of a mission. Between fights you can only Rest (spend Repairs)."
	if str(story.flags.get("_caught", "")) != "":
		return "Not with the alarm up. A Full Repair needs somewhere secure (Core p.82)."
	if story.hub.is_empty() and not bool(story.flags.get("_safe_point", false)):
		return "Not here: a Full Repair needs somewhere secure, with no enemies about (Core p.82)."
	if bool(story.hub.get("hostile", false)):
		return "Nobody here will let you work on your mechs in peace."
	return ""


static func refusal(story: StoryState, campaign: Campaign) -> String:
	var why := secure_refusal(story)
	if why != "":
		return why
	if not needed(story) and Economy.wrecked(story, campaign).is_empty():
		return "Every mech in the squad is already in full repair."
	return ""


## What it fixes, in plain words, for the bay's prompt.
static func summary(story: StoryState, campaign: Campaign) -> Array:
	var out: Array = []
	for pid: String in story.flags.get(KEY, {}):
		var c := condition(story, pid)
		var cs := str(campaign.pilots.get(pid, {}).get("callsign", "A pilot"))
		if bool(c.get("wrecked", false)):
			out.append("%s's mech was wrecked: it gets printed again." % cs)
			continue
		var parts: Array = []
		if c.has("hp") or c.has("structure"):
			parts.append("hull damage")
		if c.has("stress"):
			parts.append("reactor stress")
		if c.has("weapons") or c.has("sources"):
			parts.append("broken or spent gear")
		if int(c.get("core_power", 1)) <= 0:
			parts.append("CORE power used")
		parts.append("Repairs refilled")
		out.append("%s: %s." % [cs, ", ".join(PackedStringArray(parts))])
	return out


static func full_repair(story: StoryState, campaign: Campaign) -> Array:
	var fixed := summary(story, campaign)
	story.flags.erase(KEY)
	var events: Array = []
	# Wrecked mechs come off the printer (also under the printer-scarcity house rule: the bay is
	# a printer).
	for pid: String in Economy.wrecked(story, campaign).duplicate():
		var w: Array = (story.flags.get(Economy.WRECKED, []) as Array).duplicate()
		w.erase(pid)
		story.flags[Economy.WRECKED] = w
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			story.pilot_hp.erase(pid)
			story.down_and_out.erase(pid)
	events.append({"type": "full_repair_done", "fixed": fixed, "text": "Ten hours in the repair bay. Every mech is whole again%s." % (": " + " ".join(PackedStringArray(fixed)) if not fixed.is_empty() else ""),
		"rule_ref": REF, "gather": true})
	# The hours pass for everyone.
	events.append_array(TownLife.advance(story, PERIODS))
	if StoryHouseRules.on(campaign, Economy.R_FOOD):
		events.append_array(Economy.eat(story, campaign, 1))
	# The enemy uses the time too.
	if int(story.flags.get(REGROUP, 0)) < 1:
		story.flags[REGROUP] = 1
		events.append({"type": "regrouped", "text": "Out there, the other side had those ten hours too. Expect one more of them at the next fight.",
			"note": "The GM moves the world on while you rest (Core p.42)."})
	return events


## The next mission: enemies who regrouped while the squad repaired (then it's spent).
static func take_regroup(story: StoryState) -> int:
	var n := int(story.flags.get(REGROUP, 0))
	story.flags.erase(REGROUP)
	return n
