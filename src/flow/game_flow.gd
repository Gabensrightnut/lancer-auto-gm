class_name GameFlow
extends RefCounted
## The campaign loop (DESIGN.md milestone 1): menu → new campaign / continue / join → lobby →
## builder → GM-generated mission → battle → mission end → debrief and level up → save → next
## mission. Screens call these; tests drive them directly.
##
## Leveling: every pilot in the squad gains a License Level after every mission, whether it
## succeeded or failed (Core p.18 "Leveling Up"), and may reallocate once (BuilderModel).

## The battle in progress (screens hand it to each other).
static var session: BattleSession
## The last debrief (debrief screen).
static var debrief: Dictionary = {}
## Seats played on this computer in the current battle.
static var local_seats: Array = []
## Room code of the last resumed mission (reopened so friends can rejoin).
static var last_room := ""
## Story campaigns (between missions the squad is at a hub: briefing, job board, debrief,
## level up, downtime; the tutorial is one): the open campaign's story and its engine.
static var story: StoryState
static var story_engine: StoryEngine
## Story events for the hub to show when it opens (the tutorial's first lesson, the debrief).
static var story_events: Array = []
static var _story_campaign := ""


static func is_story(campaign: Campaign) -> bool:
	return campaign != null and bool(campaign.options.get("story", false))


## The campaign's story (loaded from its save the first time). Every campaign has one: in a
## plain campaign it only remembers which first-time tips were shown.
static func open_story(campaign: Campaign, db: ContentDB) -> StoryState:
	if story == null or _story_campaign != campaign.id:
		story = StoryState.of(campaign)
		story_engine = StoryEngine.new(db)
		_story_campaign = campaign.id
		story_events = []
	return story


## A new campaign opened the guided way (CampaignLoop.start_tutorial, DESIGN.md section 8):
## your pilot and an AI squadmate at a Union training base, briefing first. Teaching hints
## (first-time rule tips) start on or off as asked. Saved before it returns.
static func start_tutorial(store: SaveStore, db: ContentDB, pilot_name: String = "", callsign: String = "", hints: bool = true) -> Campaign:
	var c := Campaign.create("Tutorial", {"start_ll": 0, "gm_preset": "Teaching"})
	c.options["story"] = true
	c.options["teaching_hints"] = hints
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.id, "names"])
	var names := NameGen.new(rng)
	var me := c.new_pilot(pilot_name if pilot_name != "" else names.pilot_name(), callsign if callsign != "" else names.callsign())
	var mate := c.new_pilot(names.pilot_name(), names.callsign())
	open_story(c, db)
	story_engine.submit(story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": me["id"]}})
	story_engine.submit(story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": mate["id"], "ai": true, "persona": "steady"}})
	story_events = CampaignLoop.start_tutorial(c, story, story_engine)
	save_story(c, store)
	return c


## Writes the story into the campaign and saves it.
static func save_story(campaign: Campaign, store: SaveStore) -> void:
	if story != null and _story_campaign == campaign.id:
		story.save_to(campaign)
	store.save_campaign(campaign)


## The job the squad took at the hub, as a battle (CampaignLoop.build_mission): the story's
## seats, AI squadmates flown by the AI, everyone else at this screen.
static func start_story_mission(campaign: Campaign, db: ContentDB, store: SaveStore) -> BattleSession:
	open_story(campaign, db)
	var modes := {}
	var pilots := {}
	for entry: Dictionary in CampaignLoop.squad(campaign, story):
		var seat := str(entry["seat"])
		modes[seat] = "ai" if story.is_ai(seat) else "you"
		pilots[seat] = str(entry["pilot"].get("id", ""))
	var the_story := story
	var lobby := LobbyModel.for_mission(campaign, db, modes, pilots, func(opts: Dictionary) -> Dictionary:
		return CampaignLoop.build_mission(campaign, the_story, db, {"shape": opts.get("shape", "hex")}))
	lobby.set_local_ready(true)
	story.save_to(campaign)
	return start_mission(lobby, store)


## Starts the lobby's mission. Returns the session, or null with `error` set on the lobby.
static func start_mission(lobby: LobbyModel, store: SaveStore) -> BattleSession:
	var r := lobby.start()
	if r.has("error"):
		lobby.messages.append({"kind": "error", "text": r["error"]})
		return null
	store.save_campaign(lobby.campaign)
	var settings := GmSettings.from_preset(str(lobby.options.get("preset", "Standard")))
	var save := MissionAutosave.new(r["host"], r["mission"], store, lobby.campaign.id, settings)
	local_seats = []
	for seat: String in lobby.modes:
		if lobby.modes[seat] == "you":
			local_seats.append(seat)
	local_seats.sort()
	session = BattleSession.for_host(r["host"], r["director"], r["mission"], local_seats, save)
	save.save_now()  # Even quitting before the first turn ends can be continued.
	return session


## Picks a saved mission back up (host). Returns the session or null.
static func resume_mission(store: SaveStore, campaign: Campaign) -> BattleSession:
	var r := MissionAutosave.resume(store, campaign.id)
	if r.get("error", "") != "":
		return null
	last_room = str(r.get("room", ""))
	var host: NetHost = r["host"]
	var director := AiDirector.new(host, r["settings"], r["mission"])
	var save := MissionAutosave.new(host, r["mission"], store, campaign.id, r["settings"])
	local_seats = Array(host.local_seats)
	session = BattleSession.for_host(host, director, r["mission"], local_seats, save)
	host.hold_until_back()
	return session


## After the mission: record it, level the squad up, save. Returns what the debrief shows:
## {outcome, reason, title, sitrep, operation, rounds, pilots: [{id, callsign, name, old_ll,
##  new_ll, mech, mech_destroyed}], campaign}
static func finish_mission(s: BattleSession, campaign: Campaign, store: SaveStore, db: ContentDB = null) -> Dictionary:
	var state := s.host.state
	var m := s.mission
	if is_story(campaign):
		return _finish_story_mission(s, campaign, store, db)
	campaign.record_mission(state, m)
	var pilots: Array = []
	for seat: String in state.seats:
		var info: Dictionary = state.seats[seat]
		var pid := str(info.get("pilot_id", ""))
		if pid == "" or not campaign.pilots.has(pid):
			continue
		var old := int(campaign.pilots[pid]["ll"])
		campaign.level_up(pid)
		var u := state.unit(seat)
		pilots.append({"id": pid, "callsign": str(info.get("callsign", "")), "name": str(info.get("pilot", "")),
			"old_ll": old, "new_ll": int(campaign.pilots[pid]["ll"]), "mech": str(info.get("mech", "")),
			"mech_destroyed": u != null and u.destroyed})
	save_story(campaign, store)
	store.clear_mission(campaign.id)
	debrief = {"outcome": m.outcome, "reason": m.outcome_reason, "title": title_for(m.outcome),
		"sitrep": m.sitrep_name, "operation": str(m.flavor.get("operation", "")), "rounds": state.round_number,
		"pilots": pilots, "campaign": campaign.name}
	session = null
	return debrief


## Story campaigns: the story takes the result (debrief conversation, consequences, the
## twist's fallout); leveling up happens at the hub afterwards (StoryEngine level_up).
## Returns {story: true, outcome, reason, title}; the hub shows the rest (story_events).
static func _finish_story_mission(s: BattleSession, campaign: Campaign, store: SaveStore, db: ContentDB) -> Dictionary:
	open_story(campaign, db if db != null else ContentDB.new())
	var m := s.mission
	var r := CampaignLoop.finish_mission(campaign, story, story_engine, s.host.state, m, s.damage_events)
	story_events = r.get("events", [])
	save_story(campaign, store)
	store.clear_mission(campaign.id)
	debrief = {"story": true, "outcome": m.outcome, "reason": m.outcome_reason, "title": title_for(m.outcome), "campaign": campaign.name}
	session = null
	return debrief


## The next mission's lobby: same squad and seats, a new battlefield.
static func next_lobby(previous: LobbyModel, campaign: Campaign, db: ContentDB) -> LobbyModel:
	var l := LobbyModel.for_host(campaign, db)
	if previous != null:
		for seat: String in previous.modes:
			if l.modes.has(seat):
				l.modes[seat] = previous.modes[seat]
		l._apply_modes()
		l.set_fill_empty(bool(previous.options.get("fill_empty_with_ai", false)))
		l.options["shape"] = previous.options.get("shape", "hex")
		l.set_preset(str(previous.options.get("preset", "Standard")))  # rebuilds the mission
	return l


static func title_for(the_outcome: String) -> String:
	match the_outcome:
		"players":
			return "Mission complete"
		"enemies":
			return "Mission failed"
	return "Withdrawn"
