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
static var _story_db: ContentDB
## Online story campaigns. Host: `story_session` shares the story over `story_host`'s lobby
## channel (StorySession.attach_net_host); the NetHost holds the story's seats at the hub and
## the battle during a mission, so friends stay connected throughout. A friend:
## `story_client` (StoryClient.attach_net_client), whose mirror the hub shows.
static var story_session: StorySession
static var story_host: NetHost
static var story_client: StoryClient
static var _story_store: SaveStore


static func is_story(campaign: Campaign) -> bool:
	return campaign != null and bool(campaign.options.get("story", false))


## The campaign's story (loaded from its save the first time). Every campaign has one: in a
## plain campaign it only remembers which first-time tips were shown.
static func open_story(campaign: Campaign, db: ContentDB) -> StoryState:
	if story == null or _story_campaign != campaign.id:
		story = StoryState.of(campaign)
		story_engine = StoryEngine.new(db)
		_story_campaign = campaign.id
		_story_db = db
		story_events = []
		story_session = null
		story_host = null
	return story


## The host's StorySession for the open story campaign (made on first use). The hub UI talks
## to `StoryHostEngine.new(db, session)` so friends online see every change.
static func open_story_session(campaign: Campaign, db: ContentDB, local: Array) -> StorySession:
	open_story(campaign, db)
	if story_session == null:
		story_session = StorySession.new(story_engine, story, campaign)
	story_session.local_seats = local.duplicate()
	return story_session


## Host: opens the story campaign to friends. A NetHost carries the story's seats while the
## squad is at the hub (no battle yet); friends who join take AI squadmates' seats, and the AI
## picks a seat back up if its friend leaves. Then Net.open_online(host).
static func host_story_online(campaign: Campaign, db: ContentDB, store: SaveStore, local: Array) -> NetHost:
	var session := open_story_session(campaign, db, local)
	_story_store = store
	if story_host != null:
		return story_host
	var state := GameState.new()
	state.packs = campaign.packs.duplicate(true)
	for seat: String in story.seats:
		var pid := story.pilot_of_seat(seat)
		var p: Dictionary = campaign.pilots.get(pid, {})
		state.seats[seat] = {"name": str(p.get("callsign", seat)), "side": Mission.PLAYERS, "callsign": str(p.get("callsign", "")),
			"pilot": str(p.get("name", "")), "pilot_id": pid}
	story_host = NetHost.new(state, RulesEngine.new())
	for seat: String in story.seats:
		if seat in local:
			story_host.add_local_seat(seat)
		elif story.is_ai(seat):
			story_host.set_seat_ai(seat, true)
	session.attach_net_host(story_host)
	story_host.seats_changed.connect(func(_t: Dictionary) -> void: _sync_story_seats(campaign))
	story_host.lobby_message.connect(func(seat: String, msg: Dictionary) -> void: _on_story_message(campaign, seat, msg))
	return story_host


## A friend in a seat plays that pilot; an empty seat goes back to its AI squadmate.
static func _sync_story_seats(campaign: Campaign) -> void:
	if story_host == null or story_session == null:
		return
	var table := story_host.seat_table()
	for seat: String in story.seats:
		var row: Dictionary = table.get(seat, {})
		var human: bool = row.get("where", "") == "local" or (row.get("where", "") == "remote" and row.get("connected", false))
		if human == story.is_ai(seat):
			var info: Dictionary = story.seats[seat]
			story_session.submit("gm", {"type": "set_seat", "seat": "gm", "params": {"seat": seat, "pilot": info["pilot"], "ai": not human, "persona": info.get("persona", "steady")}})
	if _story_store != null:
		save_story(campaign, _story_store)


## Lobby-channel messages for the host beyond story actions: a friend's pilot build from the
## builder ({"pilot_update": pilot}). Taken only for the friend's own pilot and only if it's
## legal (BuilderModel); what was spent at earlier License Levels stays the host's record.
static func _on_story_message(campaign: Campaign, seat: String, msg: Dictionary) -> void:
	if not msg.get("pilot_update") is Dictionary or story_session == null:
		return
	var why := apply_pilot_update(campaign, seat, msg["pilot_update"])
	if why != "" and story_session.broadcast.is_valid():
		story_session.broadcast.call({"story": {"refused": {"seat": seat, "id": 0, "reason": why, "rule_ref": BuilderModel.REF}}})
	elif why == "":
		story_session.resync()


static func apply_pilot_update(campaign: Campaign, seat: String, update: Dictionary) -> String:
	var pid := str(update.get("id", ""))
	if not campaign.pilots.has(pid) or story.pilot_of_seat(seat) != pid:
		return "You can only change your own pilot."
	var old: Dictionary = campaign.pilots[pid]
	var p := update.duplicate(true)
	p["ll"] = old.get("ll", 0)
	# Spent points stay spent (Core p.18); a reallocation may move them, never remove them.
	var realloc_used: bool = old.get("realloc_pending", false) and not p.get("realloc_pending", false)
	if not realloc_used or not _same_locked_totals(old.get("locked", {}), p.get("locked", {})):
		p["locked"] = (old.get("locked", {}) as Dictionary).duplicate(true)
		p["realloc_pending"] = old.get("realloc_pending", false)
	var m := BuilderModel.new(_story_db, p)
	if not m.is_legal():
		return "Your build wasn't saved: %s" % m.problems()[0]
	campaign.pilots[pid] = m.pilot
	sync_story_picks(campaign, pid, m.picks_left())
	if _story_store != null:
		save_story(campaign, _story_store)
	return ""


static func _same_locked_totals(a: Dictionary, b: Dictionary) -> bool:
	for k: String in ["talents", "licenses"]:
		var x := 0
		var y := 0
		for v: Variant in (a.get(k, {}) as Dictionary).values():
			x += int(v)
		for v: Variant in (b.get(k, {}) as Dictionary).values():
			y += int(v)
		if x != y:
			return false
	return (a.get("core_bonuses", []) as Array).size() == (b.get("core_bonuses", []) as Array).size() and a.get("skills", {}) == b.get("skills", {}) and a.get("hase", {}) == b.get("hase", {})


## The builder was closed on a story campaign's pilot: the level-up picks made there are no
## longer waiting (story.pending_picks). A friend's build is sent to the host instead.
static func builder_done(campaign: Campaign, model: BuilderModel, store: SaveStore) -> void:
	if story_client != null and story_client.send.is_valid():
		story_client.send.call({"pilot_update": model.pilot})
		return
	if story == null or _story_campaign != campaign.id:
		open_story(campaign, model.db)
	sync_story_picks(campaign, str(model.pilot["id"]), model.picks_left())
	save_story(campaign, store)
	if story_session != null:
		story_session.resync()


## Talent, license and core bonus picks still waiting for a pilot = what's left to spend.
static func sync_story_picks(_campaign: Campaign, pid: String, left: Dictionary) -> void:
	if story == null or not story.pending_picks.has(pid):
		return
	var picks: Dictionary = story.pending_picks[pid]
	for k: String in ["talent", "license", "core_bonus"]:
		picks[k] = mini(int(picks.get(k, 0)), int(left.get(k, 0)))


## A friend joined a host who is at the hub of a story campaign (the first story payload came
## through the lobby channel). Returns the StoryClient whose mirror the hub shows.
static func join_story(client: NetClient, db: ContentDB, first_payload: Dictionary) -> StoryClient:
	story_client = StoryClient.new(db, client.seat)
	story_client.attach_net_client(client)
	if not first_payload.is_empty():
		story_client.receive(first_payload)
	return story_client


## A story battle's rules events for the story (StoryEngine "battle_events": the enemy
## commander keeps count and may open a parley). Friends online get any story events.
## Returns the story events.
static func story_battle_events(campaign: Campaign, events: Array) -> Array:
	if story == null or _story_campaign != campaign.id:
		return []
	var r := story_engine.submit(story, campaign, {"type": "battle_events", "seat": "gm", "params": {"events": events}})
	var out: Array = r.get("events", []) if r.get("ok", false) else []
	if not out.is_empty() and story_session != null:
		story_session._send(out)
	return out


## Copies every script variable of `src` onto `dst` (same class), keeping `dst` the object
## other code holds (a friend's StoryClient mirror into the objects the story UI shows).
static func copy_into(dst: Object, src: Object) -> void:
	for prop: Dictionary in src.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			dst.set(prop["name"], src.get(prop["name"]))


## Leaving an online story game (either side).
static func leave_story_online() -> void:
	story_client = null
	story_host = null
	story_session = null


## A new campaign opened the guided way (CampaignLoop.start_tutorial, DESIGN.md section 8):
## your pilot and an AI squadmate at a Union training base, briefing first. Teaching hints
## (first-time rule tips) start on or off as asked. Saved before it returns.
static func start_tutorial(store: SaveStore, db: ContentDB, pilot_name: String = "", callsign: String = "", hints: bool = true, portrait: Dictionary = {}, arcs: int = DEFAULT_ARCS) -> Campaign:
	var c := Campaign.create("Tutorial", {"start_ll": 0, "gm_preset": "Teaching"})
	c.options["story"] = true
	c.options["campaign_arcs"] = arcs
	c.options["teaching_hints"] = hints
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.id, "names"])
	var names := NameGen.new(rng)
	var me := c.new_pilot(pilot_name if pilot_name != "" else names.pilot_name(), callsign if callsign != "" else names.callsign())
	if not portrait.is_empty():
		me["portrait"] = portrait.duplicate(true)
	var mate := c.new_pilot(names.pilot_name(), names.callsign())
	open_story(c, db)
	story_engine.submit(story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": me["id"]}})
	story_engine.submit(story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": mate["id"], "ai": true, "persona": "steady"}})
	story_events = CampaignLoop.start_tutorial(c, story, story_engine)
	save_story(c, store)
	return c


## How many stories (situations, story arcs) a campaign tells before it ends (Ending.due).
const DEFAULT_ARCS := 3
const ARC_CHOICES := {1: "Short: 1 story", 2: "2 stories", 3: "Standard: 3 stories", 5: "Long: 5 stories"}


## A new story campaign (no tutorial): the squad at a town hub, briefing first. Seat p1 is
## played here; the other pilots are AI squadmates with personas that fit them (friends can
## take their seats online). `arcs` = campaign length. Session zero comes first (Core p.40-41,
## the hub shows SessionZeroScreen): the job board fills only after it, so the table's choices
## (focus, content left out) shape the first jobs. Saved before it returns.
static func start_story_campaign(store: SaveStore, db: ContentDB, campaign_name: String, pilots: int, start_ll: int, preset: String, arcs: int = DEFAULT_ARCS, campaign_id: String = "", fight_length: String = "standard") -> Campaign:
	var c := Campaign.create(campaign_name, {"start_ll": start_ll, "gm_preset": preset})
	c.gm_settings["fight_length"] = fight_length
	if campaign_id != "":
		c.id = campaign_id  # a fixed id gives the same story every time (tests, balance runs)
	c.options["story"] = true
	c.options["campaign_arcs"] = arcs
	c.options["teaching_hints"] = true
	c.options["session_zero_pending"] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.id, "names"])
	var names := NameGen.new(rng)
	for i in range(maxi(pilots, 1)):
		c.new_pilot(names.pilot_name(), names.callsign())
	open_story(c, db)
	var ids := c.pilots.keys()
	var events: Array = []
	for i in range(ids.size()):
		var p: Dictionary = c.pilots[ids[i]]
		events.append_array(story_engine.submit(story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p%d" % (i + 1), "pilot": p["id"],
			"ai": i > 0, "persona": Squadmate.suggest(p)}})["events"])
	events.append_array(story_engine.submit(story, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": _first_hub_seed(c), "no_jobs": true}})["events"])
	story_events = events
	save_story(c, store)
	return c


static func _first_hub_seed(c: Campaign) -> int:
	return int(hash([c.id, "hub"])) % 100000


## True while a new story campaign waits for its session zero.
static func session_zero_pending(campaign: Campaign) -> bool:
	return campaign != null and bool(campaign.options.get("session_zero_pending", false))


## Session zero was applied (SessionZeroScreen.done): the first jobs go on the board now.
## Returns their events. `engine` = the hub's engine (so friends online see the board too).
static func finish_session_zero(campaign: Campaign, store: SaveStore, engine: StoryEngine = null) -> Array:
	campaign.options.erase("session_zero_pending")
	var e: StoryEngine = engine if engine != null else story_engine
	var r := e.submit(story, campaign, {"type": "enter_hub", "seat": "gm", "params": {"kind": str(story.hub.get("kind", "town")), "seed": int(story.hub.get("seed", _first_hub_seed(campaign)))}})
	save_story(campaign, store)
	return r.get("events", [])


## After a campaign ends: a new one with the same living pilots (CampaignLoop.sequel), saved
## and opened. The old campaign stays in the save list with its ending.
static func start_sequel(campaign: Campaign, store: SaveStore, db: ContentDB) -> Campaign:
	open_story(campaign, db)
	save_story(campaign, store)
	var next := CampaignLoop.sequel(campaign, story, story_engine)
	var c: Campaign = next["campaign"]
	story = next["story"]
	_story_campaign = c.id
	story_session = null
	story_host = null
	story_events = next.get("events", [])
	save_story(c, store)
	return c


## Retires the squad (StoryEngine end_campaign): {} if allowed now, else {reason, rule_ref}.
static func retire_refusal(campaign: Campaign) -> Dictionary:
	if story == null or _story_campaign != campaign.id:
		return {"reason": "No story is open."}
	return story_engine.validate(story, campaign, {"type": "end_campaign", "seat": "gm", "params": {}})


## Writes the story into the campaign and saves it.
static func save_story(campaign: Campaign, store: SaveStore) -> void:
	if story != null and _story_campaign == campaign.id:
		story.save_to(campaign)
	store.save_campaign(campaign)


## The job the squad took at the hub, as a battle (CampaignLoop.build_mission): the story's
## seats, AI squadmates flown by the AI, friends online in their own seats (on the same
## NetHost, so they move into the battle with everyone), everyone else at this screen.
static func start_story_mission(campaign: Campaign, db: ContentDB, store: SaveStore, local: Array = [], squad_auto: bool = true) -> BattleSession:
	open_story(campaign, db)
	var table: Dictionary = story_host.seat_table() if story_host != null else {}
	var modes := {}
	var pilots := {}
	for entry: Dictionary in CampaignLoop.squad(campaign, story):
		var seat := str(entry["seat"])
		if story.is_ai(seat):
			modes[seat] = "ai"
		elif table.get(seat, {}).get("where", "") == "remote":
			modes[seat] = "open"
		else:
			modes[seat] = "you" if local.is_empty() or seat in local else "open"
		pilots[seat] = str(entry["pilot"].get("id", ""))
	var the_story := story
	var lobby := LobbyModel.for_mission(campaign, db, modes, pilots, func(opts: Dictionary) -> Dictionary:
		return CampaignLoop.build_mission(campaign, the_story, db, {"shape": opts.get("shape", "hex")}), story_host)
	lobby.set_fill_empty(true)  # a friend who dropped out: the AI flies until they're back
	lobby.options["ai_squad_auto"] = squad_auto and story_host == null  # off online
	for seat: String in modes:
		lobby.ready[seat] = true  # the squad deployed together at the hub
	story.save_to(campaign)
	var s := start_mission(lobby, store)
	apply_squad_orders(s, campaign, db)
	return s


## AI squadmates fight the way their character would (Squadmate.orders: a stance from their
## frame's role or persona), given to the AI director when a story battle starts or resumes.
static func apply_squad_orders(s: BattleSession, campaign: Campaign, db: ContentDB) -> void:
	if s == null or s.director == null or not is_story(campaign):
		return
	open_story(campaign, db)
	var by_seat := Squadmate.orders(story, campaign, db)
	for u: Unit in s.host.state.units.values():
		if u.kind == Unit.KIND_MECH and by_seat.has(u.controller):
			s.director.set_orders(u.id, by_seat[u.controller])


## Starts the lobby's mission. Returns the session, or null with `error` set on the lobby.
static func start_mission(lobby: LobbyModel, store: SaveStore) -> BattleSession:
	var r := lobby.start()
	if r.has("error"):
		lobby.messages.append({"kind": "error", "text": r["error"]})
		return null
	store.save_campaign(lobby.campaign)
	var settings := LobbyModel.gm_settings_for(str(lobby.options.get("preset", "Standard")), str(lobby.options.get("fight_length", "standard")))
	var save := MissionAutosave.new(r["host"], r["mission"], store, lobby.campaign.id, settings)
	local_seats = []
	for seat: String in lobby.modes:
		if lobby.modes[seat] == "you":
			local_seats.append(seat)
	local_seats.sort()
	session = BattleSession.for_host(r["host"], r["director"], r["mission"], local_seats, save)
	(r["host"] as NetHost).ai_squad_auto = bool(lobby.options.get("ai_squad_auto", true))
	save.save_now()  # Even quitting before the first turn ends can be continued.
	return session


## Picks a saved mission back up (host). Returns the session or null.
static func resume_mission(store: SaveStore, campaign: Campaign, db: ContentDB = null) -> BattleSession:
	var r := MissionAutosave.resume(store, campaign.id)
	if r.get("error", "") != "":
		return null
	last_room = str(r.get("room", ""))
	var host: NetHost = r["host"]
	var director := AiDirector.new(host, r["settings"], r["mission"])
	var save := MissionAutosave.new(host, r["mission"], store, campaign.id, r["settings"])
	local_seats = Array(host.local_seats)
	session = BattleSession.for_host(host, director, r["mission"], local_seats, save)
	host.ai_squad_auto = (host.export_seats()["tokens"] as Dictionary).is_empty()  # off if friends played
	host.hold_until_back()
	if is_story(campaign) and db != null:
		apply_squad_orders(session, campaign, db)
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
	var r := CampaignLoop.finish_mission(campaign, story, story_engine, s.host.state, m, s.battle_events)
	story_events = r.get("events", [])
	save_story(campaign, store)
	if story_session != null:
		story_session._send(story_events)  # friends online get the debrief too
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
