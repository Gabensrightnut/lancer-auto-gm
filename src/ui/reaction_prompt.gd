class_name ReactionPrompt
extends PanelContainer
## Asks a player whether to take a reaction the rules engine offered (a `reaction_offered`
## event / state.pending): Brace when hit, Overwatch when an enemy moves through your THREAT.
## Explains the choice in plain words with the numbers involved, and returns the params for
## the engine's {"type": "react"} action. The engine's suggested answer is highlighted.
## Choices: a target (Avenger Silos: buttons, or click a unit on the board), a space
## (Tactical Simulation: click the board), or an action (Reactive Code). Frame-trait reactions
## (Warp Shield, Defensive Pulse, Mag Parry...) are a plain yes/no with what they do.

signal answered(params: Dictionary)

## For the official rule text (lancer-data actions.json).
var db: ContentDB
## For picking on the board: highlights and the screen-to-board lookups (PlayerTurn has
## unit_at_screen / cell_at_screen).
var view: BattleView
var picker: Object

## Our plain-language summaries of trait reactions (rules: src/core/rules/trait_reactions.gd).
const TRAITS := {
	"warp_shield": ["WARP SHIELD", "%s can bend space around %s: the attack gets +1 Difficulty."],
	"defensive_pulse": ["DEFENSIVE PULSE", "%s can shield %s: Resistance to all damage from this attack."],
	"mag_parry": ["MAG PARRY", "%s can try to deflect the kinetic hit on %s: roll 1d6, on 5+ the attack misses."],
	"tactical_simulation": ["TACTICAL SIMULATION", "%s can run the numbers for %s: roll 1d6. On 4+ they get Resistance to the damage and may teleport up to 3 spaces; otherwise they may teleport up to 6."],
	"reactive_code": ["REACTIVE CODE", "%s was hit by a tech attack from %s and can answer with a quick tech action against them."],
	"avenger_silos": ["AVENGER SILOS", "Critical hit! %s's silos can fire 3 explosive damage at another character within 15 they can see%s."],
}

var _picking := ""  # "unit" or "cell" while the board answers
var _pick_ids: Array = []
var _hovered := ""
var _brace_offered := false

var _text: RichTextLabel
var _buttons: HFlowContainer


func _init() -> void:
	add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.96)
	sb.border_color = Color(0.95, 0.45, 0.95, 0.9)
	sb.set_border_width_all(2)
	sb.border_width_top = 4
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(520, 0)
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_font_size_override("bold_font_size", 20)
	v.add_child(_text)
	_buttons = HFlowContainer.new()
	_buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("h_separation", 14)
	_buttons.add_theme_constant_override("v_separation", 8)
	v.add_child(_buttons)


## Shows the question and waits for the answer. `pending` is GameState.pending.
func ask(state: GameState, pending: Dictionary) -> Dictionary:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var who := state.unit(String(pending.get("unit", "")))
	var ctx: Dictionary = pending.get("context", {})
	var suggested: Dictionary = ctx.get("suggested", {}) if ctx.get("suggested") is Dictionary else {}
	if suggested.is_empty() and not state.pending.is_empty():
		suggested = Reactions.suggested_answer(state)
	var px := 20
	_text.clear()
	_brace_offered = String(pending.get("reaction", "")) == "brace"
	match String(pending.get("reaction", "")):
		"brace":
			var att := state.unit(String(ctx.get("attacker", "")))
			var dmg := ""
			for part: Dictionary in ctx.get("damage", []):
				dmg += "%d {icon:%s} " % [int(part.get("amount", 0)), Icons.damage(String(part.get("type", "Kinetic")))]
			Icons.write(_text, "{icon:reaction} [b]REACTION: BRACE?[/b]\n", px)
			Icons.write(_text, "%s is hit by %s for %s.\n" % [who.name if who else "?", att.name if att else "an attack", dmg.strip_edges()], px)
			Icons.write(_text, "[color=#c8d2dc]%s[/color]\n" % _rule("act_brace", "Brace your mech for impact, reducing damage at the cost of your next turn's actions."), px)
			Icons.write(_text, "[color=#8aa]HP %d/%d, Armor %d · Rule: actions: Brace[/color]" % [who.hp if who else 0, who.max_hp if who else 0, who.armor if who else 0], px)
			_add("Brace", {"take": true}, bool(suggested.get("take", false)))
			if who and Effects.has(who, "reactive_weave"):
				# Reactive Weave: Brace and move (click the space to move to).
				Icons.write(_text, "
[color=#8aa]Reactive Weave: to Brace and move, click a space on the board.[/color]", px)
				_picking = "cell_move"
			_add("Take the hit", {"take": false}, not bool(suggested.get("take", false)))
		"overwatch":
			var mover := state.unit(String(ctx.get("mover", "")))
			Icons.write(_text, "{icon:reaction} [b]REACTION: OVERWATCH?[/b]\n", px)
			Icons.write(_text, "%s is moving within %s's reach.\n" % [mover.name if mover else "An enemy", who.name if who else "?"], px)
			Icons.write(_text, "[color=#c8d2dc]%s[/color]\n" % _rule("act_overwatch", "Attack a close-by target attempting to move."), px)
			Icons.write(_text, "[color=#8aa]Rule: actions: Overwatch[/color]", px)
			for key: String in ctx.get("weapons", []):
				var w := Weapons.find(who, key) if who else {}
				_add("Fire %s" % w.get("name", key), {"take": true, "weapon": key}, String(suggested.get("weapon", "")) == key)
			_add("Let them go", {"take": false}, false)
		"avenger_silos":
			_trait_text(pending, who, null)
			Icons.write(_text, "
[color=#8aa]Click one of them on the board, or pick below.[/color]", px)
			_pick_ids = ctx.get("targets", [])
			_picking = "unit"
			for id: String in _pick_ids:
				var t := state.unit(id)
				if t == null:
					continue
				var tag := "enemy" if who and t.side != who.side else "ALLY"
				var b := _add("%s (%s, %d away)" % [t.name, tag, Sight.unit_distance(state, who, t) if who else 0], {"take": true, "target": id}, String(suggested.get("target", "")) == id)
				b.mouse_entered.connect(func() -> void: _hover(id))
				b.mouse_exited.connect(func() -> void: _hover(""))
			_add("Hold fire", {"take": false}, false)
		"tactical_simulation":
			_trait_text(pending, who, state.unit(String(ctx.get("target", ""))))
			Icons.write(_text, "
[color=#8aa]To teleport, click a free space within 3 (up to 6 if the roll is under 4).[/color]", px)
			_picking = "cell"
			_add("Use it, stay put", {"take": true}, bool(suggested.get("take", false)))
			_add("Don't", {"take": false}, false)
		"reactive_code":
			_trait_text(pending, who, state.unit(String(ctx.get("attacker", ""))))
			for opt: String in ctx.get("options", []):
				_add(opt.replace("_", " ").capitalize(), {"take": true, "action": opt}, String(suggested.get("action", "")) == opt)
			_add("Don't", {"take": false}, false)
		"warp_shield", "defensive_pulse", "mag_parry":
			_trait_text(pending, who, state.unit(String(ctx.get("target", ""))))
			_add("Yes", {"take": true}, bool(suggested.get("take", true)))
			_add("No", {"take": false}, not bool(suggested.get("take", true)))
		_:
			Icons.write(_text, "[b]REACTION: %s?[/b]" % String(pending.get("reaction", "")).to_upper(), px)
			_add("Yes", {"take": true}, true)
			_add("No", {"take": false}, false)
	visible = true
	reset_size()
	if is_inside_tree():
		var vp := get_viewport_rect().size
		position = Vector2((vp.x - size.x) / 2.0, vp.y * 0.3)
	var params: Dictionary = await answered
	visible = false
	_picking = ""
	_pick_ids = []
	_hover("")
	return params


## The book's text for an action, from lancer-data (HTML stripped).
func _rule(id: String, fallback: String) -> String:
	if db == null:
		return fallback
	var t := String(db.get_entry("actions", id).get("detail", ""))
	if t == "":
		return fallback
	return RegEx.create_from_string("<[^>]+>").sub(t.replace("<br>", "
"), "", true).strip_edges()


func _trait_text(pending: Dictionary, who: Unit, other: Unit) -> void:
	var kind := String(pending.get("reaction", ""))
	var info: Array = TRAITS.get(kind, [kind.to_upper(), "%s can react%s."])
	var name := who.name if who else "?"
	var other_name := other.name if other else ("" if kind == "avenger_silos" else "an ally")
	Icons.write(_text, "{icon:reaction} [b]REACTION: %s?[/b]
" % info[0], 20)
	Icons.write(_text, String(info[1]) % [name, other_name] + "
", 20)
	Icons.write(_text, "[color=#8aa]Counts as your reaction this round. Rule: %s[/color]" % pending.get("rule_ref", "frame trait"), 20)


## Clicks on the board answer target and space choices while the prompt is up.
func _input(e: InputEvent) -> void:
	if visible and _brace_offered and e.is_action_pressed("brace"):
		get_viewport().set_input_as_handled()
		answered.emit({"take": true})
		return
	if not visible or _picking == "" or picker == null:
		return
	if e is InputEventMouseMotion and _picking == "unit":
		var hid := String(picker.call("unit_at_screen", (e as InputEventMouseMotion).position))
		_hover(hid if _pick_ids.has(hid) else "")
	if not (e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	var pos := (e as InputEventMouseButton).position
	if get_global_rect().has_point(pos):
		return  # the buttons handle their own clicks
	if _picking == "unit":
		var id := String(picker.call("unit_at_screen", pos))
		if _pick_ids.has(id):
			get_viewport().set_input_as_handled()
			answered.emit({"take": true, "target": id})
	elif _picking == "cell" or _picking == "cell_move":
		var c: Variant = picker.call("cell_at_screen", pos)
		if c is Vector2i:
			get_viewport().set_input_as_handled()
			answered.emit({"take": true, ("move_to" if _picking == "cell_move" else "to"): [(c as Vector2i).x, (c as Vector2i).y]})


## Lights up a candidate target on the board.
func _hover(id: String) -> void:
	if view == null:
		return
	if _hovered != "" and view.units.has(_hovered):
		(view.units[_hovered] as MechView).model.set_fx("flash", 0.0)
	_hovered = id
	view.labels.hover_unit = id
	if id != "" and view.units.has(id):
		(view.units[id] as MechView).model.set_fx("flash", 0.35)


func _add(label: String, params: Dictionary, recommended: bool) -> Button:
	var b := Button.new()
	b.text = label + ("  (suggested)" if recommended else "")
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(160, 40)
	b.pressed.connect(func() -> void: answered.emit(params))
	_buttons.add_child(b)
	return b
