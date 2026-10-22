extends SceneTree
## GM difficulty check (development tool, not shipped): plays seeded story missions AI vs AI
## (the same ten first jobs for every preset)
## with four AI pilots per GM preset and reports the squad's win rate, mechs lost and pilot
## deaths. Story missions, so pilots ride in their mechs and can die.
##
##   godot --headless --path . -s res://tools/gm_balance.gd -- [missions per preset] [preset,...]

const PRESETS := ["Teaching", "Standard", "Cautious", "Chaotic", "Ruthless"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 10
	var presets: Array = Array(args[1].split(",")) if args.size() > 1 else PRESETS
	StorySettings.persist = false
	var db := ContentDB.new()
	db.load_all()
	var store := SaveStore.new("user://gm_balance")
	var rows: Array = []
	for preset: String in presets:
		var res := {"preset": preset, "missions": 0, "wins": 0, "losses": 0, "draws": 0, "mechs_lost": 0, "pilots_dead": 0, "rounds": 0, "ms": 0}
		for i in range(n):
			var t0 := Time.get_ticks_msec()
			var r := _one(db, store, preset, 1000 + i)
			res["ms"] += Time.get_ticks_msec() - t0
			if r.is_empty():
				continue
			res["missions"] += 1
			match str(r["outcome"]):
				Mission.PLAYERS:
					res["wins"] += 1
				Mission.ENEMIES:
					res["losses"] += 1
				_:
					res["draws"] += 1
			res["mechs_lost"] += int(r["mechs_lost"])
			res["pilots_dead"] += int(r["pilots_dead"])
			res["rounds"] += int(r["rounds"])
			print("  %s #%d: %s, round %d, mechs lost %d, pilots dead %d, %d enemies (%s)" % [preset, i, r["outcome"], r["rounds"], r["mechs_lost"], r["pilots_dead"], r["enemies"], r["sitrep"]])
		rows.append(res)
	print("\npreset     missions  win%  loss%  draw%  mechs lost/mission  pilot deaths/mission  avg rounds  s/mission")
	for res: Dictionary in rows:
		var m := maxi(1, int(res["missions"]))
		print("%-10s %8d  %4d  %5d  %5d  %18.2f  %20.2f  %10.1f  %9.1f" % [res["preset"], res["missions"], 100 * res["wins"] / m, 100 * res["losses"] / m,
			100 * res["draws"] / m, float(res["mechs_lost"]) / m, float(res["pilots_dead"]) / m, float(res["rounds"]) / m, res["ms"] / 1000.0 / m])
	quit()


## One story mission: a new campaign with four LL0 pilots, all AI, the first job on the board.
func _one(db: ContentDB, store: SaveStore, preset: String, seed_value: int) -> Dictionary:
	GameFlow.story = null
	var c := GameFlow.start_story_campaign(store, db, "Balance %d" % seed_value, 4, 0, preset, GameFlow.DEFAULT_ARCS, "c_balance_%d" % seed_value)
	var story := GameFlow.story
	GameFlow.story_engine.submit(story, c, {"type": "session_zero", "seat": "gm", "params": {}})
	GameFlow.finish_session_zero(c, store)
	if story.hooks.is_empty():
		return {}
	story.seats["p1"]["ai"] = true
	var e := GameFlow.story_engine
	e.submit(story, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": story.hooks[0]["id"]}})
	var guard := 0
	while Dialogue.is_open(story) and guard < 60:
		guard += 1
		var o := Dialogue.offered(story)
		e.submit(story, c, {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}})
	e.submit(story, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	var s := GameFlow.start_story_mission(c, db, store)
	if s == null:
		return {}
	for seat: String in s.host.state.seats:
		if seat != NetHost.GM_SEAT:
			s.host.set_seat_ai(seat, true)
	s.director.run(20000)
	var state := s.host.state
	var mechs_lost := 0
	var pilots_dead := 0
	var enemies := 0
	for u: Unit in state.units.values():
		if u.side == Mission.PLAYERS and u.kind == Unit.KIND_MECH and u.destroyed:
			mechs_lost += 1
		if u.side == Mission.PLAYERS and u.kind == Unit.KIND_PILOT and u.destroyed:
			pilots_dead += 1
		if u.side == Mission.ENEMIES and u.kind != Unit.KIND_DEPLOYABLE:
			enemies += 1
	store.clear_mission(c.id)
	return {"outcome": s.mission.outcome if s.mission.outcome != "" else "unfinished", "rounds": state.round_number, "mechs_lost": mechs_lost,
		"pilots_dead": pilots_dead, "enemies": enemies, "sitrep": s.mission.sitrep_name}
