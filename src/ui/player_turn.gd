class_name PlayerTurn
extends Node
## Runs one human-controlled turn (DESIGN "Play feel"): the camera moves to your mech and the
## action bar comes up; hover the board to preview a move (path, cost, warnings), click to
## plan it; pick an action, hover a target for hit chance and cover, click it; every action
## waits for Confirm, and End Turn is its own button. All checks and previews come from the
## rules engine. Host-side controller (it reads the full GameState).

signal finished
signal acted

var state: GameState
var engine: RulesEngine
var db: ContentDB
var view: BattleView
var bar: ActionBar
var player: EventPlayer
var unit_id := ""
## "idle" (click the board to move), "boost" (click to Boost), "target" (click an enemy).
var mode := "idle"
var selected: Dictionary = {}
var pending: Dictionary = {}
var busy := false
var active := false
## Optional coroutine (action -> RuleResult) that submits and plays an action, handling any
## reactions the rules offer (DemoBattle.submit). Without it the engine is used directly.
var submitter: Callable

var _prompt: PanelContainer
var _prompt_text: RichTextLabel
## Attack options (duel, storm, collateral, delayed) shown under the confirm buttons.
var _opt_row: HBoxContainer
var _hint: Label
var _last_cell := Vector2i(99999, 99999)
var _hover_unit := ""
## Flight: on when the unit flies this move (T toggles); sky_level is the height to fly at
## (R / F raise and lower it).
var fly := false
var sky_level := -1
## First person (V): the mouse aims. Drag to turn the cockpit view; whatever is under the
## crosshair (screen centre) gets the usual hover info, and a click (without dragging) picks
## it, so the selected weapon or action goes to Confirm and the rules engine as usual. Aiming
## only picks the target: the roll is the normal attack roll.
var cockpit_hud: CockpitHUD
var aim_yaw := 0.0
var aim_pitch := 0.0
var _aim_press := false
var _aim_drag := false
var _aim_from := Vector2.ZERO
const AIM_SPEED := 0.005
const AIM_DRAG_START := 6.0
const AIM_PITCH_MAX := 1.2


func setup(ui_layer: CanvasLayer) -> void:
	_prompt = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	sb.border_color = Color(1.0, 0.82, 0.35, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(12)
	_prompt.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	_prompt.add_child(v)
	_prompt_text = RichTextLabel.new()
	_prompt_text.bbcode_enabled = true
	_prompt_text.fit_content = true
	_prompt_text.custom_minimum_size = Vector2(420, 0)
	_prompt_text.add_theme_font_size_override("normal_font_size", 17)
	v.add_child(_prompt_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	_opt_row = HBoxContainer.new()
	_opt_row.add_theme_constant_override("separation", 8)
	v.add_child(_opt_row)
	var ok := Button.new()
	ok.text = "Confirm  (Enter)"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(confirm)
	h.add_child(ok)
	var no := Button.new()
	no.text = "Cancel  (Esc)"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(cancel)
	h.add_child(no)
	_prompt.visible = false
	ui_layer.add_child(_prompt)
	_prompt.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_hint = Label.new()
	_hint.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_layer.add_child(_hint)
	bar.action_pressed.connect(_on_action)
	bar.end_turn_pressed.connect(end_turn)


func begin(uid: String) -> void:
	unit_id = uid
	view.tactical.focus_target = func() -> Variant: return (view.units[unit_id] as MechView).global_position if view.units.has(unit_id) else null
	var bu := state.unit(uid)
	fly = bu != null and bu.flying
	sky_level = bu.level if bu else -1
	view.labels.active_unit = uid
	active = true
	mode = "idle"
	selected = {}
	pending = {}
	bar.visible = true
	var mv: MechView = view.units.get(uid)
	if mv:
		view.tactical.look_at_point(mv.global_position + Vector3.UP * 0.6, 9.0)
		view.tactical.pitch = -48.0
	refresh()


func refresh() -> void:
	bar.set_actions(ActionCatalog.for_unit(state, engine, db, unit_id), unit_id)
	bar.resources.set_data(ActionCatalog.resources(state, state.unit(unit_id)))
	_set_hint()


func _set_hint() -> void:
	var vp := _hint.get_viewport_rect().size
	match mode:
		"target":
			_hint.text = "Pick a target for %s  ·  right-click to cancel" % selected.get("name", "")
		"boost":
			_hint.text = "Boost: click where to move  ·  right-click to cancel"
		"pick":
			_hint.text = _pick_hint()
		_:
			_hint.text = "Click the board to move  ·  pick an action below  ·  End Turn when done" if active else ""
			if active and can_fly():
				_hint.text += "
" + ("FLYING at height %d  ·  R / F: up / down  ·  T: land" % sky_level if fly else "T: take off and fly")
	if in_cockpit() and active:
		_hint.text += "
FIRST PERSON  ·  drag to look around  ·  click to aim at what's under the crosshair  ·  V to leave"
	# Under the turn-order bar's round banner, clear of hover cards; sized to its text so
	# nameplates only fade right under it.
	_hint.size = Vector2.ZERO
	_hint.reset_size()
	_hint.position = Vector2((vp.x - _hint.size.x) * 0.5, vp.y * 0.163 + 6)


# --- input -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or busy:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if in_cockpit() and (event is InputEventMouseMotion or (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)):
		_cockpit_mouse(event)
		return
	if event.is_action_pressed("confirm"):
		if not pending.is_empty():
			confirm()
		elif mode == "pick":
			_pick_finish_step()
	elif event.is_action_pressed("cancel"):
		cancel()
	elif event.is_action_pressed("tactical_view"):
		if mode == "pick":
			_pick_finish_step()  # Space also finishes an "up to" pick
		else:
			set_tactical_view(true)
	elif event.is_action_released("tactical_view"):
		set_tactical_view(false)
	elif event.is_action_pressed("first_person"):
		toggle_first_person()
	elif event.is_action_pressed("next_target"):
		next_target()
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("fly_toggle"):
		toggle_fly()
	elif event.is_action_pressed("sky_up"):
		change_sky(1)
	elif event.is_action_pressed("sky_down"):
		change_sky(-1)
	elif event is InputEventMouseMotion:
		hover_screen((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mode == "idle" or mode == "boost":
				# Drag to move: press, drag to see the path, release to plan the move there.
				if not mb.pressed:
					click_screen(mb.position)
			elif mb.pressed:
				click_screen(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "idle" or not pending.is_empty():
				cancel()
			else:
				context_menu(mb.position)


# --- keyboard and menus ------------------------------------------------------------------

var _menu: PopupMenu
var _menu_calls: Array = []
var _tactical := false


## Hold Space: the camera stays on your mech, every enemy's threat and your weapons' reach
## are drawn, and a quick summary of the field shows. Release to go back.
func set_tactical_view(on: bool) -> void:
	if on == _tactical:
		return
	_tactical = on
	var mv: MechView = view.units.get(unit_id)
	view.tactical.tether = mv if on else null
	if not on:
		view.overlays.clear()
		_set_hint()
		return
	var u := state.unit(unit_id)
	var threat: Array = []
	var mine: Array = []
	var lines: Array = []
	var my_reach := 0
	for w: Dictionary in u.loadout.get("weapons", []):
		for r: Dictionary in w.get("range", []):
			var v: Variant = r.get("val", 0)
			if v is int or v is float:
				my_reach = maxi(my_reach, int(v))
	for c: Vector2i in state.map.grid.cells_within(u.cell, my_reach):
		if state.map.has_cell(c):
			mine.append([c.x, c.y])
	for o: Unit in state.units.values():
		if o.side == u.side or o.destroyed or not view.units.has(o.id):
			continue
		var reach := 1
		for w: Dictionary in o.loadout.get("weapons", []):
			if Weapons.is_melee(w):
				reach = maxi(reach, Weapons.threat_for(o, w))
		for c: Vector2i in state.map.grid.cells_within(o.cell, reach):
			if state.map.has_cell(c):
				threat.append([c.x, c.y])
		var d := state.map.grid.distance(u.cell, o.cell)
		var los := RulesQueries.line_of_sight(state, unit_id, o.id)
		var cov := String(RulesQueries.cover(state, unit_id, o.id).get("cover", "none")) if los else "-"
		var hp := "HP %d/%d" % [o.hp, o.max_hp] if (view.units[o.id] as MechView).unit.has("hp") else "HP ??"
		var line := "%s  ·  %s  ·  %d away" % [o.name, hp, d]
		if not los:
			line += "  ·  no line of sight"
		elif cov != "none":
			line += "  ·  %s cover" % cov
		lines.append(line)
	view.overlays.show_plan({"threat": threat, "my_range": mine})
	_hint.text = "TACTICAL VIEW  (release Space)\n" + "\n".join(lines) + "\nRed: enemy melee threat   ·   Blue: your weapons' reach"
	_hint.size = Vector2.ZERO
	_hint.reset_size()


func toggle_first_person() -> void:
	if view.camera_mode == "tactical":
		view.set_camera_mode("cockpit", unit_id, _hover_unit)
		# Start aiming where the cockpit looks (at the hovered enemy, else straight ahead).
		var ang := aim_angles(-view.cockpit_cam.global_transform.basis.z)
		aim_yaw = ang.x
		aim_pitch = ang.y
		view.cockpit_aim = aim_dir(aim_yaw, aim_pitch)
		if cockpit_hud == null and _prompt != null and _prompt.get_parent() != null:
			cockpit_hud = CockpitHUD.new()
			_prompt.get_parent().add_child(cockpit_hud)
			_prompt.get_parent().move_child(cockpit_hud, 0)
		if cockpit_hud:
			cockpit_hud.battle = view
			cockpit_hud.unit_id = unit_id
			cockpit_hud.visible = true
		_aim_update()
	else:
		view.set_camera_mode("tactical")
		if cockpit_hud:
			cockpit_hud.visible = false
	_aim_press = false
	_aim_drag = false
	_set_hint()


func in_cockpit() -> bool:
	return view != null and view.camera_mode == "cockpit"


## The look direction for a yaw (turning, 0 = toward -Z) and pitch (up is positive).
static func aim_dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


static func aim_angles(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


## Turns the cockpit view by a mouse drag (pixels).
func turn_view(drag: Vector2) -> void:
	aim_yaw = wrapf(aim_yaw - drag.x * AIM_SPEED, -PI, PI)
	aim_pitch = clampf(aim_pitch - drag.y * AIM_SPEED, -AIM_PITCH_MAX, AIM_PITCH_MAX)
	view.cockpit_aim = aim_dir(aim_yaw, aim_pitch)
	_aim_update()


## The crosshair's ray: from your mech's eye along the aim (not the smoothed camera).
func aim_ray() -> Array:
	var mv: MechView = view.units.get(unit_id)
	var eye: Vector3 = view.cockpit_cam.global_position if view.cockpit_cam.is_inside_tree() else Vector3.ZERO
	if mv != null and mv.is_inside_tree():
		eye = mv.model.eye.global_position if mv.model.eye else mv.body_center()
	return [eye, aim_dir(aim_yaw, aim_pitch)]


## Press, then drag to turn the view; release without dragging to click at the crosshair.
func _cockpit_mouse(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_aim_press = true
			_aim_drag = false
			_aim_from = mb.position
		else:
			if _aim_press and not _aim_drag:
				cockpit_click()
			_aim_press = false
			_aim_drag = false
		return
	var mm := event as InputEventMouseMotion
	if _aim_press:
		if not _aim_drag and mm.position.distance_to(_aim_from) > AIM_DRAG_START:
			_aim_drag = true
		if _aim_drag:
			turn_view(mm.relative)


## What's under the crosshair gets the same hover as from above (hit chance, cover, range,
## line of sight, or the reason it can't be targeted).
func _aim_update() -> void:
	if cockpit_hud:
		cockpit_hud.target_id = unit_at_screen(Vector2.ZERO)
		cockpit_hud.weapon_name = String(selected.get("name", ""))
	if pending.is_empty():
		hover_screen(Vector2.ZERO)  # in the cockpit every screen point means the crosshair


func cockpit_click() -> void:
	if mode == "idle" and pending.is_empty():
		var id := unit_at_screen(Vector2.ZERO)
		var me := state.unit(unit_id)
		if id != "" and state.unit(id) != null and me != null and state.unit(id).side != me.side:
			_ask("Choose a weapon or action first, then click to aim it at %s." % state.unit(id).name, {})
			return
	click_screen(Vector2.ZERO)


## Tab: the next enemy, nearest first (while picking a target it becomes the target).
func next_target() -> void:
	var u := state.unit(unit_id)
	var ids: Array = []
	for o: Unit in state.units.values():
		if o.side != u.side and not o.destroyed and view.units.has(o.id):
			ids.append(o.id)
	if ids.is_empty():
		return
	ids.sort_custom(func(a: String, b: String) -> bool: return state.map.grid.distance(u.cell, state.unit(a).cell) < state.map.grid.distance(u.cell, state.unit(b).cell))
	var i := (ids.find(_hover_unit) + 1) % ids.size()
	_hover_unit = ids[i]
	view.tactical.focus = (view.units[ids[i]] as MechView).global_position
	if mode == "target":
		hover_target(ids[i])
	else:
		view.labels.hover_unit = ids[i]


## R: a reload system if there is one, else Stabilize (which reloads all Loading weapons).
func reload() -> void:
	var pick: Dictionary = {}
	for a: Dictionary in bar.actions:
		if a.get("enabled", true) and "reload" in String(a.get("name", "")).to_lower():
			pick = a
	if pick.is_empty():
		for a: Dictionary in bar.actions:
			if String(a.get("type", "")) == "stabilize":
				pick = a
	if not pick.is_empty():
		_on_action(pick)


## Right click on a unit or a space: what you can do with it.
func context_menu(screen: Vector2) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.id_pressed.connect(func(i: int) -> void: (_menu_calls[i] as Callable).call())
		_hint.get_parent().add_child(_menu)
	_menu.clear()
	_menu_calls.clear()
	var id := unit_at_screen(screen)
	var u := state.unit(unit_id)
	if id != "" and id != unit_id and state.unit(id) and state.unit(id).side != u.side:
		_menu.add_separator(state.unit(id).name)
		for a: Dictionary in bar.actions:
			if String(a.get("kind", "")) in ["attack", "tech"]:
				_menu_item(String(a.get("name", "")), _attack_from_menu.bind(a, id), bool(a.get("enabled", true)))
		_menu_item("Focus camera", _focus_unit.bind(id))
	elif id != "":
		_menu.add_separator(String((view.units[id] as MechView).unit.get("name", id)))
		_menu_item("Focus camera", _focus_unit.bind(id))
		if id == unit_id:
			_menu_item("First person", toggle_first_person)
	else:
		var c: Variant = cell_at_screen(screen)
		if c == null:
			return
		_menu.add_separator("Space %d, %d" % [(c as Vector2i).x, (c as Vector2i).y])
		_menu_item("Move here", plan_move.bind(c))
		_menu_item("Boost here", _boost_to.bind(c))
		_menu_item("Focus camera here", _focus_cell.bind(c))
	_menu.position = Vector2i(screen)
	_menu.popup()


func _menu_item(text: String, c: Callable, enabled: bool = true) -> void:
	_menu.add_item(text, _menu_calls.size())
	_menu.set_item_disabled(_menu.item_count - 1, not enabled)
	_menu_calls.append(c)


func _attack_from_menu(a: Dictionary, id: String) -> void:
	_on_action(a)
	if mode == "target":
		choose_target(id)


func _focus_unit(id: String) -> void:
	if view.units.has(id):
		view.tactical.focus = (view.units[id] as MechView).global_position


func _focus_cell(c: Vector2i) -> void:
	view.tactical.focus = view.cell_pos(c, state.map.ground_height(c))


func _boost_to(c: Vector2i) -> void:
	mode = "boost"
	plan_move(c)


func _ray(screen: Vector2) -> Array:
	if in_cockpit():
		return aim_ray()
	var cam := view.get_viewport().get_camera_3d()
	return [cam.project_ray_origin(screen), cam.project_ray_normal(screen)]


## The board cell under a screen point (highest standable surface the ray hits).
func cell_at_screen(screen: Vector2) -> Variant:
	var r := _ray(screen)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 0.0001:
		return null
	for lv in range(8, -1, -1):
		var t := (lv * GridLayout.LEVEL_HEIGHT - o.y) / d.y
		if t <= 0.0:
			continue
		var c := view.map.grid.from_world(o + d * t)
		if view.map.has_cell(c) and view.map.ground_height(c) == lv:
			return c
	return null


func unit_at_screen(screen: Vector2) -> String:
	var r := _ray(screen)
	var cands: Array = []
	for id: String in view.units:
		var mv: MechView = view.units[id]
		if mv.destroyed or (in_cockpit() and id == unit_id):
			continue  # from the cockpit you never aim at yourself
		cands.append({"id": id, "center": mv.body_center(), "height": mv.model.height})
	return unit_on_ray(r[0], r[1], cands)


## The unit whose body the ray passes closest to (relative to its height), in front of the
## ray's start; "" if none is near enough. cands: [{id, center: Vector3, height}].
static func unit_on_ray(origin: Vector3, dir: Vector3, cands: Array) -> String:
	var best := ""
	var best_d := 0.6
	var d := dir.normalized()
	for c: Dictionary in cands:
		var to: Vector3 = (c["center"] as Vector3) - origin
		if to.dot(d) <= 0.0:
			continue
		var dist: float = to.cross(d).length() / maxf(0.5, float(c["height"]))
		if dist < best_d:
			best_d = dist
			best = String(c["id"])
	return best


func hover_screen(screen: Vector2) -> void:
	if mode == "pick":
		_pick_hover(screen)
		return
	if mode == "target":
		var id := unit_at_screen(screen)
		if id != _hover_unit:
			_hover_unit = id
			hover_target(id)
		return
	var c: Variant = cell_at_screen(screen)
	if c != null and c != _last_cell and pending.is_empty():
		_last_cell = c
		preview_move(c)


func click_screen(screen: Vector2) -> void:
	if mode == "pick":
		_pick_click(screen)
		return
	if mode == "target":
		var id := unit_at_screen(screen)
		if id != "":
			choose_target(id)
		return
	var c: Variant = cell_at_screen(screen)
	if c != null:
		plan_move(c)


# --- planning --------------------------------------------------------------------------

## Can the unit fly for the current kind of move (a flight system, or Boost with jump jets)?
func can_fly() -> bool:
	var u := state.unit(unit_id)
	return u != null and Movement.can_fly(u, "boost" if mode == "boost" else "move")


func toggle_fly() -> void:
	if not can_fly():
		fly = false
		return
	fly = not fly
	var u := state.unit(unit_id)
	if fly and sky_level <= state.map.ground_height(u.cell):
		sky_level = maxi(u.level, state.map.ground_height(u.cell)) + 1
	_refresh_preview()


func change_sky(d: int) -> void:
	if not fly:
		return
	var u := state.unit(unit_id)
	sky_level = clampi(sky_level + d, 0, state.map.ground_height(u.cell) + 12)
	_refresh_preview()


func _refresh_preview() -> void:
	_set_hint()
	if _last_cell.x < 99999 and pending.is_empty():
		preview_move(_last_cell)


## Draws the rules engine's move preview to `cell` (no state change). Flying moves go to
## the chosen sky level; walking ones let the engine pick the height.
func preview_move(cell: Vector2i) -> Dictionary:
	var u := state.unit(unit_id)
	var flying := fly and can_fly()
	var p := RulesQueries.preview_move(state, unit_id, cell, sky_level if flying else -1, "boost" if mode == "boost" else "move", flying)
	var plan := move_overlay(p, u)
	if flying:
		plan["fly"] = true
		var cells: Array = []
		for c: Vector2i in state.map.grid.cells_within(u.cell, int(p.get("budget", u.speed)) + 1):
			if state.map.has_cell(c):
				cells.append([c.x, c.y])
		plan["sky_layer"] = {"level": sky_level, "cells": cells}
	view.overlays.show_plan(plan)
	return p


## RulesQueries.preview_move result -> TurnOverlays plan.
static func move_overlay(p: Dictionary, u: Unit) -> Dictionary:
	var path: Array = p.get("path", [])
	var info: Array = [{}]
	var flags_at := {}
	for w: Dictionary in p.get("warnings", []):
		var at: Array = w.get("at", [])
		if at.is_empty():
			continue
		var key := "%d,%d" % [int(at[0]), int(at[1])]
		if not flags_at.has(key):
			flags_at[key] = []
		var f := String(w.get("type", ""))
		(flags_at[key] as Array).append({"engagement_stop": "provoke", "provokes": "provoke"}.get(f, f))
	for i in range(1, path.size()):
		var key := "%d,%d" % [int(path[i][0]), int(path[i][1])]
		var flags: Array = flags_at.get(key, [])
		var cost := 1
		if "difficult" in flags:
			cost = 2
		if "climb" in flags:
			cost += 2 * maxi(1, int(path[i][2]) - int(path[i - 1][2]))
		info.append({"cost": cost, "flags": flags})
	var plan := {"path": path, "path_info": info, "speed": int(p.get("budget", u.speed)), "boost": 0, "size": u.size}
	if not path.is_empty():
		var last: Array = path.back()
		plan["footprint"] = {"cell": [last[0], last[1]], "level": int(last[2]), "size": u.size, "ok": p.get("ok", false),
			"reason": String(p.get("reason", "")).to_upper().left(60)}
	return plan


func plan_move(cell: Vector2i) -> void:
	var boosting := mode == "boost"
	var p := preview_move(cell)
	if not p.get("ok", false):
		_ask("[color=#ff8877]Can't move there:[/color] %s" % p.get("reason", ""), {})
		return
	var warn := ""
	for w: Dictionary in p.get("warnings", []):
		warn += "\n[color=#ffc857]⚠ %s[/color]" % w.get("text", "")
	var type := "boost" if boosting else "move"
	_ask("%s here?  Cost [b]%d[/b] of %d movement.%s" % ["Boost" if boosting else "Move", int(p.get("cost", 0)), int(p.get("budget", 0)), warn],
		{"type": type, "actor": unit_id, "params": {"to": [cell.x, cell.y], "fly": fly and can_fly(), "level": sky_level if fly and can_fly() else -1}})


func _on_action(a: Dictionary) -> void:
	if busy or not active:
		return
	cancel()
	match String(a.get("kind", "")):
		"attack", "tech", "barrage":
			mode = "target"
			selected = a
		"move_boost":
			mode = "boost"
		"pick":
			_start_pick(a)
			if mode != "pick":
				return
		"self":
			var warn := ""
			for w: Variant in a.get("warnings", []):
				warn += "\n[color=#ffc857]⚠ %s[/color]" % (w as Dictionary).get("text", "")
			_ask("%s?%s" % [a.get("name", ""), warn], {"type": a.get("type", ""), "actor": unit_id, "params": a.get("params", {})})
		_:
			_ask("[color=#aab]%s: not playable in this demo yet.[/color]" % a.get("name", ""), {})
	_set_hint()
	if in_cockpit():
		_aim_update()  # the crosshair's target gets this action's hover at once


func hover_target(id: String) -> void:
	view.labels.hover_unit = id
	if id == "" or selected.is_empty():
		bar.card.visible = false
		view.overlays.clear()
		return
	var a := selected.duplicate(true)
	if a.get("kind") == "attack":
		var o := ActionCatalog.attack_outcome(state, unit_id, String(a["weapon"]), id)
		a["outcome"] = o
		if o.has("error"):
			a["warnings"] = [{"level": "danger", "text": o["error"]}]
		var cov := RulesQueries.cover(state, unit_id, id)
		var cells: Array = []
		for c: Array in cov.get("cover_cells", []):
			cells.append({"cell": c, "kind": cov.get("cover", "hard")})
		view.overlays.show_plan({"cover": cells})
	elif a.get("kind") == "tech":
		var tp := RulesQueries.tech_preview(state, unit_id, id)
		a["outcome"] = {"target": state.unit(id).name, "hit_chance": tp.get("hit_chance", 0.0)}
	bar.card.show_action(a, clampf(bar.get_viewport_rect().size.y / 1080.0, 0.75, 1.5))
	bar.card.position = Vector2((bar.get_viewport_rect().size.x - bar.card.size.x) / 2.0, bar.get_viewport_rect().size.y * 0.55)


func choose_target(id: String) -> void:
	var a := selected
	var t := state.unit(id)
	var action := {}
	var line := ""
	match String(a.get("kind", "")):
		"attack":
			action = {"type": "skirmish", "actor": unit_id, "params": {"weapon": a["weapon"], "target": id}}
			if engine != null:
				# Out of range, no line of sight and the like: say why, with the rule, before asking.
				var r := engine.validate(state, action)
				if not r.ok:
					_ask("[color=#ff8a7a]Can't fire %s at %s: %s[/color]\n[color=#8a93a0]%s[/color]" % [a.get("name", ""), t.name, r.reason, r.rule_ref], {})
					return
			var o := ActionCatalog.attack_outcome(state, unit_id, String(a["weapon"]), id)
			line = "Fire %s at %s?  [b]%d%%[/b] to hit" % [a.get("name", ""), t.name, roundi(float(o.get("hit_chance", 0)) * 100.0)]
		"tech":
			action = {"type": a.get("type", ""), "actor": unit_id, "params": {"target": id}}
			line = "%s %s?" % [a.get("name", ""), t.name]
		"barrage":
			var attacks: Array = []
			for w: Dictionary in state.unit(unit_id).loadout.get("weapons", []).slice(0, 2):
				attacks.append({"weapon": w["key"], "target": id})
			action = {"type": "barrage", "actor": unit_id, "params": {"attacks": attacks}}
			line = "Barrage %s with your first two weapons?" % t.name
	_ask(line, action)


# --- step-by-step picking (areas, several targets, spaces: ActionInputs) ----------------

var _steps: Array = []
var _step_i := 0
var _picks: Array = []
var _params: Dictionary = {}
var _pick_reason := ""


func _start_pick(a: Dictionary) -> void:
	_steps = ActionInputs.steps(state, engine, state.unit(unit_id), a)
	_step_i = 0
	_picks = []
	_params = (a.get("params", {}) as Dictionary).duplicate(true)
	_pick_reason = ""
	selected = a
	if _steps.is_empty():
		_ask_pick()
		return
	mode = "pick"
	view.overlays.clear()


func _step() -> Dictionary:
	return _steps[_step_i] if _step_i < _steps.size() else {}


func _pick_hint() -> String:
	var s := _step()
	var n := int(s.get("count", 1))
	var t := "%s: %s" % [selected.get("name", ""), s.get("label", "pick")]
	if n > 1:
		t += "  (%d/%d)" % [_picks.size(), n]
	if s.get("optional", false) or (n > 1 and _picks.size() > 0 and s.get("up_to", true)):
		t += "  ·  Space: done" if not s.get("optional", false) or _picks.size() > 0 else "  ·  Space: skip"
	if _pick_reason != "":
		t += "
" + _pick_reason
	return t + "  ·  right-click to cancel"


## The action as it would be with `value` as the current step's next pick.
func _pick_action(value: Variant) -> Dictionary:
	var p := _params.duplicate(true)
	var s := _step()
	var picks := _picks.duplicate()
	if value != null:
		picks.append(value)
	if not picks.is_empty():
		p[String(s["param"])] = ActionInputs.value_of(s, picks)
	return {"type": selected.get("type", ""), "actor": unit_id, "params": p}


func _pick_value(screen: Vector2) -> Variant:
	var s := _step()
	if String(s.get("pick", "")) == "unit":
		var id := unit_at_screen(screen)
		if id == "" and s.get("or_space", false):
			var c0: Variant = cell_at_screen(screen)
			return null if c0 == null else [(c0 as Vector2i).x, (c0 as Vector2i).y]
		return null if id == "" else id
	var c: Variant = cell_at_screen(screen)
	return null if c == null else [(c as Vector2i).x, (c as Vector2i).y]


## Only the last pick of the last step can be checked fully; earlier ones are checked when
## the action is complete.
func _pick_check(value: Variant) -> RuleResult:
	var s := _step()
	var last := _step_i == _steps.size() - 1 and _picks.size() + 1 >= int(s.get("count", 1))
	if not last:
		return RuleResult.allow()
	return engine.validate(state, _pick_action(value))


func _pick_hover(screen: Vector2) -> void:
	var v: Variant = _pick_value(screen)
	var plan := {}
	var s := _step()
	var picked: Array = []
	for st_i in range(_steps.size()):
		var st: Dictionary = _steps[st_i]
		if String(st.get("pick", "")) == "cell":
			var val: Variant = _params.get(String(st["param"])) if st_i < _step_i else null
			if st_i == _step_i:
				picked.append_array(_picks)
			elif val is Array and not (val as Array).is_empty():
				picked.append_array(val if val[0] is Array else [val])
	if not picked.is_empty():
		var flat: Array = []
		for p: Variant in picked:
			if p is Array and (p as Array).size() == 2 and p[0] is Array:
				flat.append_array(p)
			else:
				flat.append(p)
		plan["picked"] = flat
	var r := _pick_check(v) if v != null else RuleResult.allow()
	_pick_reason = "" if r.ok else "[%s]" % r.reason
	if v is Array:
		plan["hover_cell"] = v
		plan["hover_ok"] = r.ok
		if s.has("weapon"):
			var w := Weapons.find(state.unit(unit_id), String(s["weapon"]))
			var ap := Areas.plan(state, state.unit(unit_id), w, Vector2i(int(v[0]), int(v[1])))
			if ap.get("ok", false):
				plan["area"] = ap["cells"]
		elif int(s.get("area", 0)) > 0:
			var cells: Array = []
			for c: Vector2i in view.map.grid.cells_within(Vector2i(int(v[0]), int(v[1])), int(s["area"])):
				if view.map.has_cell(c):
					cells.append([c.x, c.y])
			plan["area"] = cells
	elif v is String:
		view.labels.hover_unit = v
	view.overlays.show_plan(plan)
	_set_hint()


func _pick_click(screen: Vector2) -> void:
	var v: Variant = _pick_value(screen)
	if v == null:
		return
	var r := _pick_check(v)
	if not r.ok:
		_pick_reason = "[%s]" % r.reason
		_set_hint()
		return
	if v is String and _picks.has(v):
		return  # each target once
	_picks.append(v)
	if _picks.size() >= int(_step().get("count", 1)):
		_pick_finish_step()
	else:
		_pick_hover(screen)


## Ends the current step (also early, for "up to N" and optional steps).
func _pick_finish_step() -> void:
	var s := _step()
	if s.is_empty():
		return
	if _picks.is_empty() and not s.get("optional", false):
		return
	if not _picks.is_empty():
		_params[String(s["param"])] = ActionInputs.value_of(s, _picks)
	_picks = []
	_step_i += 1
	if _step_i >= _steps.size():
		_ask_pick()
	else:
		_set_hint()


func _ask_pick() -> void:
	var action := {"type": selected.get("type", ""), "actor": unit_id, "params": _params}
	var r := engine.validate(state, action)
	if not r.ok:
		_ask("[color=#ff8a7a]%s: %s[/color]" % [selected.get("name", ""), r.reason], {})
		return
	var warn := ""
	for w: Variant in selected.get("warnings", []):
		warn += "
[color=#ffc857]⚠ %s[/color]" % (w as Dictionary).get("text", "")
	if selected.has("table_note"):
		warn += "
[color=#e0b050]Table: %s[/color]" % selected["table_note"]
	_ask("%s?%s" % [selected.get("name", ""), warn], action)


func _ask(text: String, action: Dictionary) -> void:
	pending = action
	_fill_options(selected.get("options", []) if not action.is_empty() and not selected.is_empty() else [])
	_prompt_text.text = text
	_prompt.visible = true
	_prompt.reset_size()
	var vp := _prompt.get_viewport_rect().size
	_prompt.position = Vector2((vp.x - _prompt.size.x) / 2.0, vp.y * 0.6)
	# Without an action there is nothing to confirm: just a message.
	(_prompt.get_child(0).get_child(1).get_child(0) as Button).visible = not action.is_empty()


## One drop-down per option; picking sets that param on the pending action (defaults first).
func _fill_options(opts: Array) -> void:
	for c in _opt_row.get_children():
		_opt_row.remove_child(c)
		c.queue_free()
	_opt_row.visible = not opts.is_empty()
	for o: Dictionary in opts:
		var params: Dictionary = pending.get("params", {})
		params[String(o["key"])] = o.get("default")
		pending["params"] = params
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var vals: Array = o.get("values", [])
		for v: Array in vals:
			ob.add_item(String(v[1]))
		ob.tooltip_text = String(o.get("label", ""))
		for i in range(vals.size()):
			if vals[i][0] == o.get("default"):
				ob.select(i)
		ob.item_selected.connect(func(i: int) -> void: (pending["params"] as Dictionary)[String(o["key"])] = vals[i][0])
		_opt_row.add_child(ob)


func cancel() -> void:
	pending = {}
	_prompt.visible = false
	mode = "idle"
	selected = {}
	_hover_unit = ""
	_last_cell = Vector2i(99999, 99999)
	bar.card.visible = false
	view.overlays.clear()
	_set_hint()


## Submits the pending action to the rules engine and plays what happens.
func confirm() -> void:
	if pending.is_empty() or busy:
		return
	var action := pending
	cancel()
	busy = true
	var res: RuleResult
	if submitter.is_valid():
		res = await submitter.call(action)
	else:
		var out := engine.submit(state, action)
		res = out["result"]
		if res.ok:
			await player.play(out["events"])
	if not res.ok:
		busy = false
		_ask("[color=#ff8877]Not allowed:[/color] %s  [color=#8899aa](%s)[/color]" % [res.reason, res.rule_ref], {})
		return
	busy = false
	acted.emit()
	refresh()


func end_turn() -> void:
	if busy or not active:
		return
	cancel()
	busy = true
	var out := engine.submit(state, {"type": "end_turn", "actor": unit_id})
	active = false
	bar.visible = false
	_hint.text = ""
	await player.play(out["events"])
	busy = false
	finished.emit()
