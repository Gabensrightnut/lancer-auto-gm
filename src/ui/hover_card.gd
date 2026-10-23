class_name HoverCard
extends PanelContainer
## The description card shown while hovering an action: name and cost, the effect with
## numbers followed by their official icon, plain-language warnings worked out from the
## unit's current state, the expected outcome against the hovered target, and the rule
## reference. Draws only what it's given (format in src/render/FORMATS.md).

const WARN := Color(1.0, 0.78, 0.3)
const DANGER := Color(1.0, 0.4, 0.35)

var _text: RichTextLabel


func _init() -> void:
	add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.045, 0.06, 0.96)
	sb.border_color = Color(0.4, 0.62, 0.82, 0.85)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(440, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 18)
	add_child(_text)


func show_action(a: Dictionary, scale_factor: float = 1.0) -> void:
	_text.clear()
	_text.custom_minimum_size.x = 440 * scale_factor
	var px := int(18 * scale_factor)
	var cost := String(a.get("cost", "quick"))
	var ci := Icons.cost(cost)
	var head := "[b]%s[/b]   {icon:%s} [color=#%s]%s[/color]" % [a.get("name", ""), ci, Icons.color(ci).to_html(false), CostIcon.NAMES.get(cost, cost)]
	for e: Dictionary in a.get("extras", []):
		head += "   %s {icon:%s}" % [e.get("value", ""), e.get("icon", "heat")]
	Icons.write(_text, head + "\n", px)
	if a.has("stats"):
		Icons.write(_text, "[color=#cfd8e3]%s[/color]\n" % a["stats"], px)
	# Long rule text stays readable: the short description, else the first ~300 characters.
	var body := String(a.get("text", a.get("desc", "")))
	if body.length() > 320:
		var short := String(a.get("desc", ""))
		if short != "" and short.length() < body.length():
			body = short
		else:
			var cut := body.left(300).rfind(". ")
			body = body.left(cut + 1 if cut > 120 else 300) + " …"
	Icons.write(_text, "[color=#b8c4d2]%s[/color]\n" % body, px)
	if a.get("auto_hint", false):
		Icons.write(_text, "[color=#ffd166]Right-click: auto-use this whenever it's allowed.[/color]\n", px)
	if ActionButton.locked(a):
		Icons.write(_text, "[color=#%s]✕ Can't use: %s[/color]\n" % [DANGER.to_html(false), a.get("reason", "")], px)
	for w: Variant in a.get("warnings", []):
		var wd: Dictionary = w if w is Dictionary else {"text": str(w)}
		var col := DANGER if String(wd.get("level", "warn")) == "danger" else WARN
		Icons.write(_text, "[color=#%s]⚠ %s[/color]\n" % [col.to_html(false), wd["text"]], px)
	if a.get("mod") is Dictionary:
		var md: Dictionary = a["mod"]
		Icons.write(_text, "[color=#9fd1ff][b]Mod: %s[/b]%s[/color]
" % [md.get("name", ""), ("  (%d uses left)" % int(md["uses"])) if md.has("uses") else ""], px)
		if String(md.get("text", "")) != "":
			Icons.write(_text, "[color=#8fb4d8]%s[/color]
" % md["text"], px)
	if a.has("table_note"):
		Icons.write(_text, "[color=#e0b050][b]%s:[/b] %s[/color]
" % ["Table" if String(a.get("table", "")) == "manual" else "Partly the table", a["table_note"]], px)
	var o: Dictionary = a.get("outcome", {})
	if not o.is_empty():
		var line := "[b]vs %s:[/b]  " % o.get("target", "target")
		if o.has("hit_chance"):
			line += "[color=#ffffff]%d%%[/color] to hit" % roundi(float(o["hit_chance"]) * 100.0)
		if o.has("cover") and String(o["cover"]) != "none":
			line += "  ·  %s cover" % String(o["cover"]).capitalize()
		if o.has("damage"):
			line += "  ·  likely %s %s" % [o["damage"], Icons.dmg_token(String(o.get("damage_type", "Kinetic")))]
			if o.has("armor"):
				line += " (after %d Armor)" % int(o["armor"])
		Icons.write(_text, "[color=#9fe0ff]%s[/color]\n" % line, px)
	if a.has("rule_ref"):
		_text.append_text("[color=#7f93a8][i]%s[/i][/color]" % a["rule_ref"])
	visible = true
	reset_size()
