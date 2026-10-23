class_name Troops
extends RefCounted
## The squad's own troops (data/game/story/troops.json), once it has men of its own: a pirate
## crew, captains of a ship, a merc company's owners (campaign.options.troops, or a campaign
## script's "troops": {"if": cond}). Squads of ten with one shared HP pool (the rules session's
## soldier squad unit); a squad that comes out of a fight with 4 men has 4 until reinforced.
##   - Recruited in person, by talking (Dialogue: an extra reply to a bartender, a fixer or a
##     faction agent; story effects for freed prisoners or a beaten crew). Costs manna with the
##     wallet house rule, else a favour owed; refused if the place thinks badly of you.
##   - Upkeep: one ration per squad per day with the food-and-water house rule (Economy.eat).
##     Unfed, a squad loses heart (morale), then deserts; hungry squads side with a pilot with
##     a grudge (Agendas) when the squad splits (Decisions).
##   - In fights: up to deploy_max squads as allied units (the "allies" seat), losses kept.
## Kept in story.flags["_troops"] = {squads: [{id, name, men, morale, source}], next}.
##
## Effects {"recruit": {source, free, name}} and {"reinforce": true}.

const FILE := "res://data/game/story/troops.json"
const KEY := "_troops"
const LABEL := "Your own troops"
const REF_RESERVE := "Core p.48: reserves (Reinforcements)"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


## Whether the squad has men of its own in this campaign.
static func open(story: StoryState, campaign: Campaign) -> bool:
	if campaign == null:
		return false
	if bool(campaign.options.get("troops", false)) or not squads(story).is_empty():
		return true
	var t: Dictionary = CampaignScript.script(campaign).get("troops", {}) if CampaignScript.active(campaign) else {}
	return not t.is_empty() and CampaignScript.check(story, campaign, t.get("if"), {})


static func roster(story: StoryState) -> Dictionary:
	if not story.flags.has(KEY):
		story.flags[KEY] = {"squads": [], "next": 1}
	return story.flags[KEY]


static func squads(story: StoryState) -> Array:
	return story.flags.get(KEY, {}).get("squads", [])


static func men(story: StoryState) -> int:
	var n := 0
	for s: Dictionary in squads(story):
		n += int(s["men"])
	return n


# --- Recruiting --------------------------------------------------------------------------

## Extra replies in conversations: ask a bartender or a fixer for fighters (DESIGN: recruiting
## by talking, never a menu button).
static func options_for(story: StoryState, campaign: Campaign, ctx: Dictionary, node_id: String) -> Array:
	if node_id != "menu" or not open(story, campaign) or squads(story).size() >= int(data().get("max_squads", 4)):
		return []
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	var out: Array = []
	for src: String in data().get("sources", {}):
		var d: Dictionary = data()["sources"][src]
		if not (d.get("roles", []) as Array).has(str(npc.get("role", ""))):
			continue
		var asked := "recruited:%s" % ctx.get("npc", "")
		if story.flags.has(asked):
			continue
		out.append({"id": "recruit_" + src, "once": true, "text": str(d.get("text", "")), "tags": ["practical"], "priority": 2,
			"effects": [{"recruit": {"source": src}}, {"set_flag": asked}], "next": "menu"})
	return out


static func recruit_refusal(story: StoryState, campaign: Campaign, src: String, npc_id: String) -> String:
	var d: Dictionary = data().get("sources", {}).get(src, {})
	if squads(story).size() >= int(data().get("max_squads", 4)):
		return "You can't feed and lead more than %d squads." % int(data().get("max_squads", 4))
	var fac := str(story.npcs.get(npc_id, {}).get("faction", story.hub.get("faction", "")))
	if d.has("min_standing") and fac != "" and story.get_standing(fac) < int(d["min_standing"]):
		return str(data().get("lines", {}).get("refused", "Nobody here wants to fight under your name."))
	return ""


static func recruit(story: StoryState, campaign: Campaign, spec: Dictionary, ctx: Dictionary) -> Array:
	var src := str(spec.get("source", "bar"))
	var npc_id := str(ctx.get("npc", ""))
	var why := recruit_refusal(story, campaign, src, npc_id)
	if why != "":
		return [{"type": "recruit_refused", "text": why, "label": LABEL}]
	var d: Dictionary = data().get("sources", {}).get(src, {})
	var events: Array = []
	if not bool(spec.get("free", false)):
		if StoryHouseRules.on(campaign, Economy.R_WALLET):
			var price := int(data().get("price", 300))
			if int(Economy.wallet(story).get("manna", 0)) < price:
				return [{"type": "recruit_refused", "text": "Ten fighters want %d manna up front. You have %d." % [price, int(Economy.wallet(story).get("manna", 0))], "label": Economy.LABEL}]
			var w: Dictionary = Economy.wallet(story)
			w["manna"] = int(w["manna"]) - price
			story.flags[Economy.WALLET] = w
			events.append({"type": "paid", "text": "Paid %d manna to sign them on." % price, "label": Economy.LABEL})
		else:
			var fac := str(story.npcs.get(npc_id, {}).get("faction", story.hub.get("faction", "")))
			if fac != "":
				events.append_array(StoryEffects.apply({"obligation": {"to": fac, "what": "Fighters signed on through %s" % story.npcs.get(npc_id, {}).get("name", "them")}}, story, campaign, ctx))
	var names: Array = d.get("name", ["the volunteers"])
	var name := str(spec.get("name", names[story.dice.die(names.size()) - 1]))
	var r := roster(story)
	var sq := {"id": "sq%d" % int(r["next"]), "name": name, "men": int(data().get("squad_size", 10)), "morale": int(data().get("morale_max", 3)), "source": src, "where": str(story.hub.get("name", ""))}
	r["next"] = int(r["next"]) + 1
	(r["squads"] as Array).append(sq)
	events.append({"type": "recruited", "squad": sq.duplicate(), "text": _cap(str(d.get("signed", "{name} join you.")).replace("{name}", name)), "label": LABEL})
	return events


## First letter up, the rest as written ("the old hands" -> "The old hands").
static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


## Brings every squad back up to ten (paid per man with the wallet, else a favour).
static func reinforce(story: StoryState, campaign: Campaign) -> Array:
	var lost := 0
	for s: Dictionary in squads(story):
		lost += int(data().get("squad_size", 10)) - int(s["men"])
	if lost <= 0:
		return []
	var events: Array = []
	if StoryHouseRules.on(campaign, Economy.R_WALLET):
		var cost := lost * int(data().get("reinforce_price", 30))
		if int(Economy.wallet(story).get("manna", 0)) < cost:
			return [{"type": "recruit_refused", "text": "Replacing %d men costs %d manna." % [lost, cost], "label": Economy.LABEL}]
		Economy.wallet(story)["manna"] = int(Economy.wallet(story)["manna"]) - cost
	for s: Dictionary in squads(story):
		s["men"] = int(data().get("squad_size", 10))
	events.append({"type": "reinforced", "text": "%d new faces fill the gaps in your squads." % lost, "label": LABEL})
	return events


# --- Upkeep ------------------------------------------------------------------------------

## One ration per squad per day (Economy.eat, food-and-water house rule).
static func feed(story: StoryState, campaign: Campaign, nights: int) -> Array:
	var events: Array = []
	var sv: Dictionary = story.flags.get(Economy.SURVIVAL, {})
	var lines: Dictionary = data().get("lines", {})
	var r := roster(story)
	var keep: Array = []
	for s: Dictionary in r["squads"]:
		var fed := mini(int(sv.get("rations", 0)), nights)
		sv["rations"] = int(sv.get("rations", 0)) - fed
		if fed >= nights:
			s["morale"] = mini(int(s["morale"]) + 1, int(data().get("morale_max", 3)))
			s.erase("hungry")
			keep.append(s)
			continue
		s["morale"] = int(s["morale"]) - 1
		s["hungry"] = true
		if int(s["morale"]) <= 0:
			events.append({"type": "deserted", "squad": s["id"], "text": _cap(str(lines.get("desert", "")).replace("{name}", str(s["name"]))), "label": LABEL})
			continue
		events.append({"type": "troops_hungry", "squad": s["id"], "text": _cap(str(lines.get("hungry", "")).replace("{name}", str(s["name"]))), "label": LABEL})
		var sore := Agendas.anyone(story, "grievance")
		if sore != "":
			s["with"] = sore
			events.append({"type": "troops_side", "squad": s["id"], "pilot": sore,
				"text": _cap(str(lines.get("with_instigator", "")).replace("{name}", str(s["name"])).replace("{pilot}", str(campaign.pilots[sore].get("callsign", ""))))})
		keep.append(s)
	r["squads"] = keep
	story.flags[Economy.SURVIVAL] = sv
	return events


## When the squad splits (Decisions): which seat each squad stands with. Hungry squads follow
## the pilot with a grudge; the rest follow the lead human.
static func loyalties(story: StoryState) -> Dictionary:
	var out := {}
	var hs := Decisions.humans(story)
	for s: Dictionary in squads(story):
		var seat := story.seat_of(str(s.get("with", "")))
		if seat == "" or not story.seats.has(seat):
			seat = str(hs[0]) if not hs.is_empty() else ""
		if story.is_ai(seat):
			seat = Decisions.leader_of(story, seat)
		if seat != "":
			out[seat] = (out.get(seat, []) as Array) + [s["id"]]
	return out


# --- In fights ---------------------------------------------------------------------------

## Up to deploy_max squads fight at the squad's side (allied units), as many men as they have.
static func deploy(story: StoryState, state: GameState, mission: Mission, seed_value: int) -> void:
	var tid := str(Garrisons.data().get("unit_template", ""))
	var templates := UnitFactory.npc_templates()
	if squads(story).is_empty():
		return
	if not templates.has(tid):
		mission.flavor["troops_note"] = "Your troops wait aboard: there's no soldier squad unit yet (PROVISIONAL)."
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "troops"])
	var free := MissionGenerator._free_cells(mission.deployment.get(Mission.PLAYERS, []), rng)
	state.seats["allies"] = {"name": "Allies", "side": Mission.PLAYERS}
	var n := 0
	var sent: Array = []
	for s: Dictionary in squads(story):
		if n >= int(data().get("deploy_max", 2)) or int(s["men"]) <= 0:
			continue
		n += 1
		var u := MissionGenerator.build_enemy({"template": tid}, templates, "troop_" + str(s["id"]), 80 + n)
		u.name = _cap(str(s["name"]))
		u.side = Mission.PLAYERS
		u.controller = "allies"
		u.hp = mini(int(s["men"]), u.max_hp)
		if MissionGenerator._place(state, u, free):
			sent.append(s["id"])
	mission.flavor["troops"] = sent


## After a fight: men lost stay lost.
static func after_battle(story: StoryState, state: GameState) -> Array:
	var events: Array = []
	var lines: Dictionary = data().get("lines", {})
	var r := roster(story)
	var keep: Array = []
	for s: Dictionary in r["squads"]:
		var u := state.unit("troop_" + str(s["id"]))
		if u == null:
			keep.append(s)
			continue
		var left := 0 if u.destroyed else clampi(u.hp, 0, int(s["men"]))
		if left <= 0:
			events.append({"type": "troops_lost", "squad": s["id"], "text": _cap(str(lines.get("lost", "")).replace("{name}", str(s["name"]))), "label": LABEL})
			continue
		if left < int(s["men"]):
			events.append({"type": "troops_losses", "squad": s["id"], "men": left, "text": _cap(str(lines.get("losses", "")).replace("{name}", str(s["name"])).replace("{men}", str(left))), "label": LABEL})
		s["men"] = left
		keep.append(s)
	r["squads"] = keep
	return events
