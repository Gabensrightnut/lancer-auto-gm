class_name ReactionPrompt
extends PanelContainer
## Asks a player whether to take a reaction the rules engine offered (a `reaction_offered`
## event / state.pending): Brace when hit, Overwatch when an enemy moves through your THREAT.
## Explains the choice in plain words with the numbers involved, and returns the params for
## the engine's {"type": "react"} action. The engine's suggested answer is highlighted.

signal answered(params: Dictionary)

## For the official rule text (lancer-data actions.json).
var db: ContentDB

var _text: RichTextLabel
var _buttons: HBoxContainer


func _init() -> void:
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
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 14)
	v.add_child(_buttons)


## Shows the question and waits for the answer. `pending` is GameState.pending.
func ask(state: GameState, pending: Dictionary) -> Dictionary:
	for c in _buttons.get_children():
		c.queue_free()
	var who := state.unit(String(pending.get("unit", "")))
	var ctx: Dictionary = pending.get("context", {})
	var suggested := Reactions.suggested_answer(state)
	var px := 20
	_text.clear()
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
		_:
			Icons.write(_text, "[b]REACTION: %s?[/b]" % String(pending.get("reaction", "")).to_upper(), px)
			_add("Yes", {"take": true}, true)
			_add("No", {"take": false}, false)
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y * 0.3)
	var params: Dictionary = await answered
	visible = false
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


func _add(label: String, params: Dictionary, recommended: bool) -> void:
	var b := Button.new()
	b.text = label + ("  (suggested)" if recommended else "")
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(160, 40)
	b.pressed.connect(func() -> void: answered.emit(params))
	_buttons.add_child(b)
