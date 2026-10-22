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
var _hint: Label
var _last_cell := Vector2i(99999, 99999)
var _hover_unit := ""


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
		_:
			_hint.text = "Click the board to move  ·  pick an action below  ·  End Turn when done" if active else ""
	# Under the turn-order bar's round banner, clear of hover cards; sized to its text so
	# nameplates only fade right under it.
	_hint.size = Vector2.ZERO
	_hint.reset_size()
	_hint.position = Vector2((vp.x - _hint.size.x) * 0.5, vp.y * 0.163 + 6)


# --- input -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if not pending.is_empty():
					confirm()
			KEY_ESCAPE:
				cancel()
	elif event is InputEventMouseMotion:
		hover_screen((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			click_screen(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mode != "idle":
			cancel()


func _ray(screen: Vector2) -> Array:
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
	var best := ""
	var best_d := 0.6
	for id: String in view.units:
		var mv: MechView = view.units[id]
		var p := mv.body_center()
		var dist: float = (p - (r[0] as Vector3)).cross(r[1] as Vector3).length() / maxf(0.5, mv.model.height)
		if dist < best_d and not mv.destroyed:
			best_d = dist
			best = id
	return best


func hover_screen(screen: Vector2) -> void:
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
	if mode == "target":
		var id := unit_at_screen(screen)
		if id != "":
			choose_target(id)
		return
	var c: Variant = cell_at_screen(screen)
	if c != null:
		plan_move(c)


# --- planning --------------------------------------------------------------------------

## Draws the rules engine's move preview to `cell` (no state change).
func preview_move(cell: Vector2i) -> Dictionary:
	var u := state.unit(unit_id)
	var p := RulesQueries.preview_move(state, unit_id, cell, -1, "boost" if mode == "boost" else "move")
	view.overlays.show_plan(move_overlay(p, u))
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
		{"type": type, "actor": unit_id, "params": {"to": [cell.x, cell.y]}})


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
		"self":
			var warn := ""
			for w: Variant in a.get("warnings", []):
				warn += "\n[color=#ffc857]⚠ %s[/color]" % (w as Dictionary).get("text", "")
			_ask("%s?%s" % [a.get("name", ""), warn], {"type": a.get("type", ""), "actor": unit_id, "params": a.get("params", {})})
		_:
			_ask("[color=#aab]%s: not playable in this demo yet.[/color]" % a.get("name", ""), {})
	_set_hint()


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


func _ask(text: String, action: Dictionary) -> void:
	pending = action
	_prompt_text.text = text
	_prompt.visible = true
	_prompt.reset_size()
	var vp := _prompt.get_viewport_rect().size
	_prompt.position = Vector2((vp.x - _prompt.size.x) / 2.0, vp.y * 0.6)
	# Without an action there is nothing to confirm: just a message.
	(_prompt.get_child(0).get_child(1).get_child(0) as Button).visible = not action.is_empty()


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
