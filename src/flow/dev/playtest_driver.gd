class_name PlaytestDriver
extends Node
## QA: plays the real game window like a person would, sending genuine mouse clicks and key
## presses to what's on screen (buttons, the board, enemy mechs, portraits), and saves a
## screenshot at each step plus a log. Development only: attached by the main menu when the
## game is launched with a "qa:<mode>" argument:
##   godot --path . -- qa:solo qa_out:C:/path/to/folder
## Modes: solo, hotseat, host (opens an online room, writes room.txt), join (reads room.txt).
## The driver never calls game logic to act: if a click doesn't work, that's a bug it logs.

var mode := "solo"
var out_dir := "user://qa"
var shots := 0
var log_lines := PackedStringArray()
var turns_played := 0
var issues := PackedStringArray()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("qa:"):
			mode = a.substr(3)
		elif a.begins_with("qa_out:"):
			out_dir = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# QA campaigns go to their own save folder, never the player's saves.
	var saves := "user://qa_saves_%s/" % mode
	_remove_dir(saves)
	MenuSession.store = SaveStore.new(saves)
	get_tree().reload_current_scene.call_deferred()
	_run.call_deferred()


func _run() -> void:
	note("QA run '%s' started" % mode)
	await wait(1.5)
	match mode:
		"solo", "hotseat":
			await _campaign_loop()
		"story":
			await _story_loop()
		"host":
			await _host_online()
		"join":
			await _join_online()
	note("QA run finished. %d turns played, %d issues." % [turns_played, issues.size()])
	_flush()
	await wait(0.5)
	get_tree().quit()


# --- The scripted playthroughs ----------------------------------------------------------------

## A story campaign the way a new player would: session zero, the hub (sector map, codex,
## talking, the builder), a job, the battle (call for terms, barks), debrief, level up,
## downtime, save and quit, continue.
func _story_loop() -> void:
	await shot("main_menu")
	if not await click_text("New campaign"):
		return
	await wait(0.6)
	await shot("new_campaign_form")
	if not await click_text("Create campaign"):
		return
	if not await wait_scene("HubScreen", 20.0):
		return
	await wait(2.5)
	await shot("session_zero")
	await click_text("Roll")
	await wait(0.3)
	if not await click_text("Start the campaign"):
		return
	await wait(2.0)
	await shot("hub_first_look")
	var hs: Node = current()
	var hub: HubScene = hs.hub
	# The sector map and the codex.
	await key(KEY_M)
	await wait(1.0)
	await shot("sector_map")
	if not hub.map.visible:
		issue("story", "M didn't open the sector map", "sector_map")
	await key(KEY_ESCAPE)
	await wait(0.5)
	await click_text("Codex")
	await wait(0.8)
	await shot("hub_codex")
	await key(KEY_ESCAPE)
	await wait(0.4)
	# Talk to someone at the hub.
	var npcs: Array = hub.story.hub.get("npcs", [])
	if not npcs.is_empty():
		hub.talk_to(str(npcs[0]))
		await _dialogue_through(hub, "talk")
	# The builder from the hub menu: look creator, paint, automation list.
	await click_text("Menu")
	await wait(0.6)
	await shot("hub_menu")
	if await click_text("Pilot builder"):
		await wait_scene("BuilderScreen")
		await wait(2.0)
		await shot("builder")
		if await click_text("Edit look"):
			await wait(1.0)
			await shot("creator")
			await click_text("Randomize all")
			await wait(0.5)
			await click_text("Confirm")
			await wait(0.8)
		await click_text("Randomize")
		await wait(1.0)
		await shot("builder_painted")
		await click_text("Done")
		await wait_scene("HubScreen", 15.0)
		await wait(2.0)
		hs = current()
		hub = hs.hub
	# A job from the board, the briefing, deploy.
	await key(KEY_J)
	await wait(0.8)
	await shot("job_board")
	if not await click_text("Take this job"):
		return
	await _dialogue_through(hub, "briefing")
	await shot("reserves")
	if not await click_text("Deploy"):
		return
	if not await wait_scene("BattleScreen", 30.0):
		return
	var bs: Node = current()
	await wait(3.0)
	await shot("battle_objectives")
	if bs.terms_button != null and bs.terms_button.visible:
		await click(bs.terms_button)
		await wait(0.8)
		await shot("call_for_terms_early")
	await _play_battle(-1)
	if not await wait_scene("HubScreen", 40.0):
		return
	await wait(2.5)
	hs = current()
	hub = hs.hub
	await shot("after_battle_hub")
	await _dialogue_through(hub, "debrief")
	await shot("debrief_done")
	await click_text("Level up")
	await wait(1.0)
	await shot("level_up")
	await click_text("Confirm")
	await wait(0.5)
	await click_text("On to downtime")
	await wait(1.0)
	await shot("downtime")
	await click_text("Menu")
	await wait(0.5)
	await click_text("Save and quit")
	if not await wait_scene("MainMenu", 15.0):
		return
	await wait(1.0)
	await click_text("Continue")
	await wait(0.5)
	await shot("continue_list")
	await click_text("Campaign 1")
	if await wait_scene("HubScreen", 20.0):
		await wait(2.5)
		await shot("continued_hub")


## Clicks through a conversation: the first reply when there's a choice, Space otherwise.
func _dialogue_through(hub: HubScene, tag: String) -> void:
	var shot_line := false
	var shot_choice := false
	for i in range(80):
		await wait(0.35)
		if not hub.dialogue.visible:
			if i > 2:
				return
			continue
		var options: Array = []
		for b in find_all_type("BaseButton"):
			var t := str(b.get("text"))
			if t.length() > 2 and t[0].is_valid_int() and t.substr(1, 2) == ". " and b.is_visible_in_tree():
				options.append(b)
		if not options.is_empty():
			if not shot_choice:
				await shot("%s_choice" % tag)
			# A player asks one thing, then picks the way out (the last reply) to move on.
			await click(options[0] if not shot_choice else options[options.size() - 1])
			shot_choice = true
		else:
			if not shot_line:
				await shot("%s_line" % tag)
				shot_line = true
			await key(KEY_SPACE)
	issue("story", "The %s conversation didn't end after 80 steps" % tag, await shot("%s_stuck" % tag))

func _campaign_loop() -> void:
	await shot("main_menu")
	if not await click_text("New campaign"):
		return
	await wait(0.6)
	var name_edit := find_type("LineEdit") as LineEdit
	if name_edit:
		name_edit.text = "QA %s %d" % [mode, Time.get_unix_time_from_system()]
		name_edit.text_changed.emit(name_edit.text)
	await shot("new_campaign_form")
	await click_text("Missions only")  # the lobby-to-battle loop (story campaigns open the hub)
	if not await click_text("Create campaign"):
		return
	await wait_scene("LobbyScreen")
	await wait(1.0)
	await shot("lobby")
	if mode == "hotseat":
		var modes := find_all_type("OptionButton").filter(func(o: OptionButton) -> bool: return o.item_count == 4 and o.get_item_text(0).begins_with("You"))
		if modes.size() >= 2:
			(modes[1] as OptionButton).select(0)
			(modes[1] as OptionButton).item_selected.emit(0)
			await wait(1.0)
			await shot("lobby_hotseat_two_players")
	# Builder: spend the starting points like a new player.
	if await click_text("Edit build"):
		await wait_scene("BuilderScreen")
		await wait(1.0)
		await shot("builder")
		for i in range(3):
			# The builder redraws after every change: look the buttons up again each time.
			var plus := _enabled_plus()
			if i < plus.size():
				await click(plus[i])
				await wait(0.3)
		await click_tab("Talents")
		await wait(0.4)
		var tplus := _enabled_plus()
		if not tplus.is_empty():
			await click(tplus[tplus.size() / 2])
		await wait(0.5)
		await shot("builder_after_choices")
		await click_text("Done")
		await wait_scene("LobbyScreen")
		await wait(0.8)
	if not await click_text("Ready"):
		return
	await wait(0.5)
	await shot("lobby_ready")
	if not await click_text("Start mission"):
		issue("lobby", "START MISSION didn't work after Ready", "lobby_ready")
		return
	if not await wait_scene("BattleScreen", 20.0):
		return
	await _play_battle(-1)
	if not await wait_scene("DebriefScreen", 30.0):
		return
	await wait(1.0)
	await shot("debrief")
	if await click_text("Spend points"):
		await wait_scene("BuilderScreen")
		await wait(1.0)
		await shot("builder_level_up")
		await click_text("Done")
		await wait_scene("DebriefScreen")
		await wait(0.5)
	if not await click_text("Next mission"):
		return
	await wait_scene("LobbyScreen")
	await wait(1.0)
	await shot("lobby_next_mission")
	await click_text("Ready")
	await wait(0.4)
	await click_text("Start mission")
	if not await wait_scene("BattleScreen", 20.0):
		return
	await _play_battle(1)
	# Quit mid-mission from the in-battle menu, then Continue.
	await click_text("Menu")
	await wait(0.6)
	await shot("battle_menu")
	await click_text("Save and quit")
	if not await wait_scene("MainMenu", 10.0):
		return
	await wait(1.0)
	await shot("main_menu_after_quit")
	await click_text("Continue")
	await wait(0.5)
	var resume := find_all_type("Button").filter(func(b: Button) -> bool: return "mission in progress" in b.text)
	if resume.is_empty():
		issue("main menu", "No saved campaign shows 'mission in progress' after Save and quit", "main_menu_after_quit")
		return
	await click(resume[0])
	if not await wait_scene("BattleScreen", 20.0):
		issue("continue", "Continue didn't reopen the battle", "main_menu_after_quit")
		return
	await wait(3.0)
	await shot("battle_resumed")
	await _play_battle(1)


## Plays the battle on screen. `max_turns` < 0: until the mission ends.
func _play_battle(max_turns: int) -> void:
	var bs := current()
	await wait(2.0)
	await shot("battle_start")
	var my_turns := 0
	var last_progress := Time.get_ticks_msec()
	var last_key := ""
	var picks_shot := false
	var tried_ai := false
	while is_instance_valid(bs) and bs == current() and not bs.get("_ended"):
		await wait(0.25)
		var s: BattleSession = bs.session
		var key := "%s|%s|%s|%s" % [s.view.get("round", 0), s.view.get("active_unit", ""), (s.view.get("acted", []) as Array).size(), s.waiting().get("state", "")]
		if key != last_key:
			last_key = key
			last_progress = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_progress > 15000 and _friend_away(s) and not tried_ai:
			# A friend dropped out: hand their mech to the AI from the in-battle menu.
			tried_ai = true
			await click_text("Menu")
			await wait(0.6)
			await shot("menu_friend_away")
			if await click_text("until"):
				note("Handed the absent friend's mech to the AI")
				last_progress = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_progress > 45000:
			issue("battle", "Nothing happened for 45 s. Waiting on: %s" % s.waiting(), await shot("stuck"))
			return
		if bs.narration.visible:
			await shot("gm_narration")
			await click_text("Continue")
			continue
		if bs.dialogue != null and bs.dialogue.visible:
			await shot("battle_dialogue")
			var opts: Array = []
			for b in find_all_type("BaseButton"):
				var t := str(b.get("text"))
				if t.length() > 2 and t[0].is_valid_int() and t.substr(1, 2) == ". " and b.is_visible_in_tree():
					opts.append(b)
			if opts.is_empty():
				await key(KEY_SPACE)
			else:
				await click(opts[0])
			await wait(0.4)
			continue
		var handoff: Control = bs.handoff_layer
		if handoff.visible:
			await shot("hotseat_pass_screen")
			await click_text("Ready")
			continue
		if bs.reaction_panel.visible:
			await shot("reaction_prompt")
			var answer: Variant = find_text_button("Yes,")
			if answer == null:
				answer = find_text_button("Overwatch with")
			if answer == null:
				issue("battle", "Reaction prompt has no button to answer it", "reaction_prompt")
			else:
				await click(answer)
				await wait(0.5)
			continue
		if s.my_pick() and not bs.turn.active and not s.busy and not bs._draining and bs.status.visible:
			if not picks_shot:
				await shot("squad_pick")
				picks_shot = true
			await _press_ill_go(bs)
			await wait(1.0)
			continue
		if bs.turn.active and not bs.turn.busy:
			if max_turns >= 0 and my_turns >= max_turns:
				return
			await _play_turn(bs, my_turns)
			my_turns += 1
			turns_played += 1


func _friend_away(s: BattleSession) -> bool:
	if not s.is_host:
		return false
	for row: Dictionary in s.host.seat_table().values():
		if row.get("where", "") == "remote" and not row.get("connected", false) and not row.get("ai", false):
			return true
	return false


func _press_ill_go(bs: Node) -> void:
	var data: Dictionary = bs.order_bar.data
	var mine: Array = bs._local_units()
	var buttons := find_all_type("Button").filter(func(b: Button) -> bool: return b.text == "I'll go" and b.is_visible_in_tree())
	if buttons.is_empty():
		issue("battle", "It's the squad's pick but there are no I'll go buttons", await shot("no_ill_go"))
		return
	# Portraits run in the bar's unit order (players first); pick my first waiting mech.
	var players: Array = (data.get("units", []) as Array).filter(func(u: Dictionary) -> bool: return u.get("side") == "players")
	var waiting_players: Array = players.filter(func(u: Dictionary) -> bool: return not u.get("acted", false))
	# Only my own mechs or AI squadmates can be picked (not another player's).
	var idx := -1
	for i in range(waiting_players.size()):
		if waiting_players[i]["id"] in mine:
			idx = i
			break
	if idx < 0:
		var s: BattleSession = bs.session
		for i in range(waiting_players.size()):
			var u: Unit = s.mirror.unit(waiting_players[i]["id"])
			if u != null and s.is_host and s.host.is_ai_seat(u.controller):
				idx = i
				break
	if idx < 0:
		return  # Nothing of ours to send: the other player picks.
	await click(buttons[mini(idx, buttons.size() - 1)])


## One turn the way a player plays it: move toward the enemy, attack (Lock On first on the
## first turn, Overcharge on the second), End Turn.
func _play_turn(bs: Node, n: int) -> void:
	var t: PlayerTurn = bs.turn
	var s: BattleSession = bs.session
	var me := s.mirror.unit(t.unit_id)
	await shot("my_turn_%d" % n)
	var target := _nearest_enemy(s.mirror, me)
	# Move.
	var dest: Variant = _move_target(s.mirror, me, target)
	if dest != null:
		var pos := screen_of_cell(bs, dest)
		await hover(pos)
		await wait(0.3)
		if n == 0:
			await shot("move_preview")
		await click_at(pos)
		await wait(0.3)
		await key(KEY_ENTER)
		await wait_idle(bs)
	# Tech: Lock On on the first turn.
	if n % 3 == 0 and target != null:
		if await press_action(bs, "lock_on"):
			await click_unit(bs, target.id)
			await key(KEY_ENTER)
			await wait_idle(bs)
	# Overcharge on the second turn.
	if n % 3 == 1:
		if await press_action(bs, "overcharge"):
			await shot("overcharge_prompt")
			await key(KEY_ENTER)
			await wait_idle(bs)
	# Attack with the first weapon that can.
	target = _nearest_enemy(s.mirror, s.mirror.unit(t.unit_id))
	if target != null:
		for a: Dictionary in t.bar.actions:
			if a.get("kind", "") == "attack" and a.get("enabled", true):
				if await press_action(bs, str(a.get("id", ""))):
					await click_unit(bs, target.id, n == 0)
					await wait(0.3)
					await key(KEY_ENTER)
					await wait_idle(bs)
				break
	await shot("before_end_turn_%d" % n)
	var end: Variant = find_text_button("END TURN")
	if end == null:
		issue("battle", "No END TURN button during my turn", await shot("no_end_turn"))
		return
	await click(end)
	await wait_idle(bs)


func _nearest_enemy(m: GameState, me: Unit) -> Unit:
	if me == null:
		return null
	var best: Unit = null
	for u: Unit in m.units.values():
		if u.side != me.side and not u.destroyed:
			if best == null or m.map.grid.distance(me.cell, u.cell) < m.map.grid.distance(me.cell, best.cell):
				best = u
	return best


func _move_target(m: GameState, me: Unit, toward: Unit) -> Variant:
	if me == null:
		return null
	var best: Variant = null
	var best_d := 99999
	for sp: Dictionary in RulesQueries.reachable(m, me.id)["spaces"]:
		var c := Vector2i(int(sp["cell"][0]), int(sp["cell"][1]))
		var d: int = m.map.grid.distance(c, toward.cell) if toward != null else 0
		# Close in, but stop a few spaces short so guns can still fire.
		var score := absi(d - 4)
		if score < best_d:
			best_d = score
			best = c
	return best


func _host_online() -> void:
	await shot("main_menu")
	await click_text("New campaign")
	await wait(0.5)
	await click_text("Missions only")
	await click_text("Create campaign")
	await wait_scene("LobbyScreen")
	await wait(1.0)
	var modes := find_all_type("OptionButton").filter(func(o: OptionButton) -> bool: return o.item_count == 4 and o.get_item_text(0).begins_with("You"))
	if modes.size() >= 2:
		(modes[1] as OptionButton).select(2)
		(modes[1] as OptionButton).item_selected.emit(2)
	await wait(0.5)
	await click_text("Invite friends online")
	var ok := await wait_until(func() -> bool: return find_label_containing("Room code:") != null, 30.0)
	if not ok:
		issue("online", "No room code after Invite friends online", await shot("no_room"))
		return
	var code := str(find_label_containing("Room code:").text).split(":")[1].strip_edges().left(6)
	var f := FileAccess.open(out_dir.path_join("room.txt"), FileAccess.WRITE)
	f.store_string(code)
	f.close()
	note("Hosting room %s" % code)
	await shot("host_lobby_waiting")
	ok = await wait_until(func() -> bool: return current().lobby.rows()[1]["connected"] and current().lobby.rows()[1]["ready"], 90.0)
	await shot("host_lobby_friend_joined")
	if not ok:
		issue("online", "The friend didn't show up connected and ready in the host's lobby", "host_lobby_friend_joined")
		return
	await click_text("Ready")
	await wait(0.5)
	await click_text("Start mission")
	if await wait_scene("BattleScreen", 20.0):
		await _play_battle(5)


func _join_online() -> void:
	var path := out_dir.path_join("room.txt")
	await wait_until(func() -> bool: return FileAccess.file_exists(path), 90.0)
	await wait(1.0)
	var code := FileAccess.get_file_as_string(path).strip_edges()
	await click_text("Join online")
	await wait(0.5)
	var edits := find_all_type("LineEdit")
	if edits.size() >= 2:
		(edits[0] as LineEdit).text = code
		(edits[1] as LineEdit).text = "QA friend"
	await shot("join_form")
	await click_text("Join  ›")
	if not await wait_scene("LobbyScreen", 40.0):
		issue("online", "Joining room %s never reached the lobby" % code, await shot("join_failed"))
		return
	await wait(1.0)
	await shot("client_lobby")
	await click_text("Ready")
	if await wait_scene("BattleScreen", 120.0):
		await _play_battle(3)


# --- Input --------------------------------------------------------------------------------

func click(c: Control) -> void:
	if not is_instance_valid(c):
		issue("driver", "Tried to click a control that was already gone", "")
		return
	# Like a player: scroll it into view first.
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			await get_tree().process_frame
			await get_tree().process_frame
			break
		p = p.get_parent()
	await click_at(c.get_global_rect().get_center())


func _enabled_plus() -> Array:
	return find_all_type("Button").filter(func(b: Button) -> bool: return b.text == "+" and not b.disabled and b.is_visible_in_tree() and not b.is_queued_for_deletion())


func click_at(pos: Vector2) -> void:
	await hover(pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev)
		await get_tree().process_frame


func hover(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	get_viewport().push_input(m)
	await get_tree().process_frame


func key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		get_viewport().push_input(ev)
		await get_tree().process_frame


func click_text(text: String) -> bool:
	var b: Variant = find_text_button(text)
	if b == null:
		issue("ui", "Couldn't find a button '%s' on %s" % [text, current().name if current() else "?"], await shot("missing_" + text.to_lower().replace(" ", "_").left(20)))
		return false
	await click(b)
	return true


func click_tab(title: String) -> bool:
	for tc in find_all_type("TabContainer"):
		var bar := (tc as TabContainer).get_tab_bar()
		for i in range(bar.tab_count):
			if bar.get_tab_title(i).to_lower() == title.to_lower():
				var r := bar.get_tab_rect(i)
				await click_at(bar.get_global_transform() * r.get_center())
				return true
	issue("ui", "No tab '%s'" % title, await shot("missing_tab"))
	return false


func press_action(bs: Node, id: String) -> bool:
	for b in find_all_type("ActionButton"):
		if str(b.action.get("id", "")) == id or str(b.action.get("type", "")) == id:
			if not b.action.get("enabled", true):
				return false
			await click(b)
			await wait(0.3)
			return true
	return false


func click_unit(bs: Node, id: String, snap := false) -> void:
	var mv: MechView = bs.view.units.get(id)
	if mv == null:
		return
	var pos := (bs.view.get_viewport().get_camera_3d() as Camera3D).unproject_position(mv.body_center())
	await hover(pos)
	await wait(0.4)
	if snap:
		await shot("target_preview")
	await click_at(pos)


func screen_of_cell(bs: Node, c: Vector2i) -> Vector2:
	var cam := bs.view.get_viewport().get_camera_3d() as Camera3D
	return cam.unproject_position(bs.view.cell_pos(c, bs.view.map.ground_height(c)))


# --- Waiting and finding ----------------------------------------------------------------------

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await wait(0.25)
		t += 0.25
	return false


func wait_idle(bs: Node) -> void:
	await wait(0.3)
	await wait_until(func() -> bool: return not is_instance_valid(bs) or (not bs.turn.busy and not bs.player.playing and not bs._draining), 30.0)
	await wait(0.2)


func wait_scene(name: String, timeout: float = 10.0) -> bool:
	var ok := await wait_until(func() -> bool: return current() != null and current().name == name, timeout)
	if not ok:
		issue("flow", "Expected the %s screen, still on %s" % [name, current().name if current() else "?"], await shot("expected_" + name.to_lower()))
	return ok


func current() -> Node:
	return get_tree().current_scene


func find_text_button(text: String) -> Variant:
	var want := text.to_lower()
	for b in find_all_type("BaseButton"):
		var t := str(b.get("text")).to_lower()
		if want in t and b.is_visible_in_tree() and not (b as BaseButton).disabled and not b.is_queued_for_deletion():
			return b
	return null


func find_label_containing(text: String) -> Label:
	for l in find_all_type("Label"):
		if text in (l as Label).text and (l as Label).is_visible_in_tree():
			return l
	return null


func find_type(type: String) -> Node:
	var all := find_all_type(type)
	return all[0] if not all.is_empty() else null


func find_all_type(type: String) -> Array:
	var out: Array = []
	_collect(get_tree().root, type, out)
	return out


func _collect(n: Node, type: String, out: Array) -> void:
	if n.is_class(type) or (n.get_script() != null and (n.get_script() as Script).get_global_name() == type):
		out.append(n)
	for c in n.get_children():
		_collect(c, type, out)


# --- Reporting --------------------------------------------------------------------------------

func shot(name: String) -> String:
	await RenderingServer.frame_post_draw
	shots += 1
	var file := "%s_%02d_%s.png" % [mode, shots, name]
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	note("screenshot %s" % file)
	return file


func note(text: String) -> void:
	var line := "[%7.1fs] %s" % [Time.get_ticks_msec() / 1000.0, text]
	log_lines.append(line)
	print("QA ", line)


func issue(area: String, text: String, screenshot: String) -> void:
	issues.append("%s | %s | %s" % [area, text, screenshot])
	note("ISSUE (%s): %s  [%s]" % [area, text, screenshot])


static func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(d))
	DirAccess.remove_absolute(path)


func _flush() -> void:
	var f := FileAccess.open(out_dir.path_join("%s_log.txt" % mode), FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n\nISSUES\n" + "\n".join(issues) + "\n")
	f.close()
