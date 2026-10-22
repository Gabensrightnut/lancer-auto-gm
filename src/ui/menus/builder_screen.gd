extends Control
## Pilot and mech builder. Left: the pilot (License Level, points, skills, talents, licenses,
## core bonuses, mech skills). Middle: the mech (frame, preview area, stats, mounts, systems).
## Right: the picker for whatever slot is being changed; choices that would make the build
## illegal are shown greyed out with the reason. All rules live in BuilderModel.

## The visuals work puts the 3D mech preview in this node (a Control, filled by its owner).
var preview_area: PanelContainer
var model: BuilderModel
var pilot_box: VBoxContainer
var mech_box: VBoxContainer
var picker_box: VBoxContainer
var picker_title: Label
var status_box: HBoxContainer
var show_blocked := true
## What the picker is choosing: {"kind": "frame"/"weapon"/"mod"/"system", "mount", "slot"}
var picking: Dictionary = {"kind": "frame"}
var tab_index := 0
var _dialog: FileDialog


func _ready() -> void:
	var c := MenuSession.ensure_campaign()
	var pid := MenuSession.builder_pilot
	if not c.pilots.has(pid):
		pid = c.pilots.keys()[0]
		MenuSession.builder_pilot = pid
	model = BuilderModel.new(MenuSession.content(), c.pilots[pid])
	model.changed.connect(_refresh)
	var col := MenuTheme.screen(self, "Pilot & Mech Builder", "Every choice is checked against the rules as you make it.", _done)
	var bar: HBoxContainer = col.get_child(0)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(grow)
	for b in [["Import from COMP/CON", "compendium", _import], ["Export to COMP/CON", "save", _export], ["Done", "activate", _done]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.icon = MenuTheme.icon_texture(b[1], 22, MenuTheme.TEXT)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(b[2])
		bar.add_child(btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var pilot_panel := MenuTheme.panel("Pilot", MenuTheme.ACCENT, "pilot")
	pilot_panel.custom_minimum_size = Vector2(470, 0)
	row.add_child(pilot_panel)
	pilot_box = MenuTheme.body(pilot_panel)
	var mech_panel := MenuTheme.panel("Mech", MenuTheme.ACCENT, "frame")
	mech_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mech_panel)
	var mech_scroll := ScrollContainer.new()
	mech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mech_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	MenuTheme.body(mech_panel).add_child(mech_scroll)
	mech_box = VBoxContainer.new()
	mech_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mech_box.add_theme_constant_override("separation", 12)
	mech_scroll.add_child(mech_box)
	var picker_panel := MenuTheme.panel("", MenuTheme.ACCENT)
	picker_panel.custom_minimum_size = Vector2(500, 0)
	row.add_child(picker_panel)
	var pb := MenuTheme.body(picker_panel)
	var ph := HBoxContainer.new()
	picker_title = MenuTheme.heading("", 20)
	picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(picker_title)
	var blocked := CheckBox.new()
	blocked.text = "Show locked"
	blocked.button_pressed = true
	blocked.toggled.connect(func(on: bool) -> void:
		show_blocked = on
		_refresh_picker())
	ph.add_child(blocked)
	pb.add_child(ph)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pb.add_child(scroll)
	picker_box = VBoxContainer.new()
	picker_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_box.add_theme_constant_override("separation", 6)
	scroll.add_child(picker_box)
	status_box = HBoxContainer.new()
	status_box.add_theme_constant_override("separation", 14)
	col.add_child(status_box)
	_refresh()


func _refresh() -> void:
	_refresh_pilot()
	_refresh_mech()
	_refresh_picker()
	_refresh_status()


# --- Pilot -------------------------------------------------------------------------------

func _refresh_pilot() -> void:
	_clear(pilot_box, 1)
	var p := model.pilot
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 8)
	var callsign := LineEdit.new()
	callsign.text = str(p.get("callsign", ""))
	callsign.placeholder_text = "Callsign"
	callsign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	callsign.add_theme_font_size_override("font_size", 22)
	callsign.text_changed.connect(func(t: String) -> void: p["callsign"] = t)
	names.add_child(callsign)
	var full := LineEdit.new()
	full.text = str(p.get("name", ""))
	full.placeholder_text = "Name"
	full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full.text_changed.connect(func(t: String) -> void: p["name"] = t)
	names.add_child(full)
	pilot_box.add_child(names)
	var ll := HBoxContainer.new()
	ll.add_theme_constant_override("separation", 10)
	# License Level isn't picked here: it goes up by one after every mission (Core p.18).
	ll.add_child(MenuTheme.label("LICENSE LEVEL", 15, MenuTheme.MUTED))
	ll.add_child(MenuTheme.heading(str(model.ll()), 28))
	var ll_note := MenuTheme.label("GRIT +%d  ·  goes up after every mission" % UnitFactory.grit(model.ll()), 15, MenuTheme.MUTED)
	ll_note.tooltip_text = "Pilots gain a License Level after every mission, success or failure (Core p.18)."
	ll_note.mouse_filter = Control.MOUSE_FILTER_PASS
	ll.add_child(ll_note)
	pilot_box.add_child(ll)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	var b := model.budgets()
	for k in [["skills", "Skill points"], ["talents", "Talent ranks"], ["hase", "Mech skills"], ["licenses", "License ranks"], ["core_bonuses", "Core bonuses"]]:
		var used: int = b[k[0]]["used"]
		var mx: int = b[k[0]]["max"]
		var color := MenuTheme.BAD if used > mx else (MenuTheme.GOOD if used == mx else MenuTheme.WARN)
		chips.add_child(MenuTheme.chip("%s %d/%d" % [k[1], used, mx], color))
	pilot_box.add_child(chips)
	if model.can_reallocate():
		pilot_box.add_child(_realloc_box())
	var hase := GridContainer.new()
	hase.columns = 4
	hase.add_theme_constant_override("h_separation", 10)
	for k: String in BuilderModel.HASE:
		var v := int(p.get(k, 0))
		hase.add_child(MenuTheme.label(k.to_upper(), 15, MenuTheme.MUTED))
		hase.add_child(_step_button("−", v > 0, "", func() -> void: model.set_hase(k, v - 1)))
		hase.add_child(MenuTheme.heading(str(v), 20))
		var why := model._preview(func() -> String: return model.set_hase(k, v + 1))
		hase.add_child(_step_button("+", why == "", why, func() -> void: model.set_hase(k, v + 1)))
	pilot_box.add_child(hase)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pilot_box.add_child(tabs)
	tabs.add_child(_rank_list("Skills", model.skill_options(), func(id: String, r: int) -> void: model.set_skill(id, r), "+%d", 2))
	tabs.add_child(_rank_list("Talents", model.talent_options(), func(id: String, r: int) -> void: model.set_talent(id, r), "Rank %d", 1))
	tabs.add_child(_rank_list("Licenses", model.license_options(), func(id: String, r: int) -> void: model.set_license(id, r), "Rank %d", 1))
	tabs.add_child(_core_bonus_list())
	tabs.current_tab = tab_index
	tabs.tab_changed.connect(func(i: int) -> void: tab_index = i)


## Level-up reallocation (Core p.18): once per new License Level.
func _realloc_box() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.WARN.darkened(0.75), MenuTheme.WARN, 1, 3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(MenuTheme.label("Level-up reallocation (once): move all ranks of one talent or license to another, or swap a core bonus.", 14, MenuTheme.WARN.lightened(0.4), true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var kind := OptionButton.new()
	var from := OptionButton.new()
	var to := OptionButton.new()
	from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	from.clip_text = true
	to.clip_text = true
	for k in [["talent", "Talent"], ["license", "License"], ["core_bonus", "Core bonus"]]:
		kind.add_item(k[1])
		kind.set_item_metadata(kind.item_count - 1, k[0])
	var fill := func() -> void:
		from.clear()
		to.clear()
		var k: String = kind.get_selected_metadata()
		var have: Array = []
		var all: Array = []
		match k:
			"talent":
				have = model.pilot["talents"].keys()
				all = model.db.all("talents")
			"license":
				have = model.pilot["licenses"].keys()
				all = model.db.all("frames").filter(func(e: Dictionary) -> bool: return e.get("source", "") != "GMS")
			"core_bonus":
				have = model.pilot["core_bonuses"].duplicate()
				all = model.db.all("core_bonuses")
		for id: String in have:
			var e: Dictionary = model.db.get_entry({"talent": "talents", "license": "frames", "core_bonus": "core_bonuses"}[k], id)
			from.add_item(str(e.get("name", id)))
			from.set_item_metadata(from.item_count - 1, id)
		for e: Dictionary in all:
			if not have.has(e.get("id", "")):
				to.add_item(str(e.get("name", e.get("id", ""))))
				to.set_item_metadata(to.item_count - 1, e.get("id", ""))
	kind.item_selected.connect(func(_i: int) -> void: fill.call())
	fill.call()
	row.add_child(kind)
	row.add_child(from)
	row.add_child(MenuTheme.label("→", 18))
	row.add_child(to)
	v.add_child(row)
	var result := MenuTheme.label("", 14, MenuTheme.BAD.lightened(0.3), true)
	var apply := Button.new()
	apply.text = "Reallocate"
	apply.pressed.connect(func() -> void:
		if from.item_count == 0 or to.item_count == 0:
			result.text = "Nothing to move."
			return
		var why := model.reallocate(kind.get_selected_metadata(), from.get_selected_metadata(), to.get_selected_metadata())
		result.text = why)
	v.add_child(apply)
	v.add_child(result)
	return p


func _rank_list(title: String, options: Array, set_rank: Callable, rank_text: String, mult: int) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["rank"] != b["rank"]:
			return a["rank"] > b["rank"]
		return a["name"] < b["name"])
	for o: Dictionary in options:
		var h := HBoxContainer.new()
		var name := MenuTheme.label(o["name"], 16, MenuTheme.TEXT if o["rank"] > 0 else MenuTheme.MUTED)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.tooltip_text = str(o.get("detail", ""))
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(name)
		if o.get("source", "") != "":
			h.add_child(MenuTheme.icon(MenuTheme.maker_icon(o["source"]), 18, MenuTheme.maker_color(o["source"])))
		h.add_child(MenuTheme.label(rank_text % (o["rank"] * mult) if o["rank"] > 0 else "—", 15, MenuTheme.TEXT))
		h.add_child(_step_button("−", o["rank"] > 0, "", func() -> void: set_rank.call(o["id"], o["rank"] - 1)))
		h.add_child(_step_button("+", o["ok"], o["reason"], func() -> void: set_rank.call(o["id"], o["rank"] + 1)))
		v.add_child(h)
	return scroll


func _core_bonus_list() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Core bonuses"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for o: Dictionary in model.core_bonus_options():
		var check := CheckBox.new()
		check.text = o["name"]
		check.button_pressed = o["selected"]
		check.disabled = not o["ok"] and not o["selected"]
		check.tooltip_text = o["detail"] + ("\n\nLocked: " + o["reason"] if not o["ok"] else "")
		check.toggled.connect(func(_on: bool) -> void: model.toggle_core_bonus(o["id"]))
		v.add_child(check)
	return scroll


# --- Mech --------------------------------------------------------------------------------

func _refresh_mech() -> void:
	_clear(mech_box)
	var m := model.mech()
	if m.is_empty():
		mech_box.add_child(MenuTheme.label("This pilot has no mech.", 18, MenuTheme.MUTED))
		return
	var frame := model.db.frame(str(m["frame"]))
	var source := str(frame.get("source", "GMS"))
	var accent := MenuTheme.maker_color(source)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var name_edit := LineEdit.new()
	name_edit.text = str(m.get("name", ""))
	name_edit.placeholder_text = "Mech name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 22)
	name_edit.text_changed.connect(func(t: String) -> void: model.mech()["name"] = t)
	top.add_child(name_edit)
	var frame_btn := Button.new()
	frame_btn.text = "%s %s   ▾" % [source, frame.get("name", "?")]
	frame_btn.icon = MenuTheme.icon_texture(MenuTheme.maker_icon(source), 26, accent)
	frame_btn.custom_minimum_size = Vector2(220, 0)
	frame_btn.pressed.connect(func() -> void: _pick({"kind": "frame"}))
	top.add_child(frame_btn)
	mech_box.add_child(top)

	preview_area = PanelContainer.new()
	preview_area.name = "MechPreview"
	preview_area.custom_minimum_size = Vector2(0, 300)
	var ps := MenuTheme.box(Color("08090c"), accent.darkened(0.3), 1, 0)
	preview_area.add_theme_stylebox_override("panel", ps)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(_centered(MenuTheme.icon(MenuTheme.maker_icon(source), 120, accent.darkened(0.2))))
	var tag := MenuTheme.label("3D MECH PREVIEW", 15, MenuTheme.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(tag)
	preview_area.add_child(pv)
	mech_box.add_child(preview_area)

	var u := UnitFactory.build_mech(model.db, "preview", str(m["frame"]), m.get("loadout", {}), model.pilot)
	var sp := model.sp()
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 6)
	stats.add_theme_constant_override("v_separation", 6)
	for s in [["HP", u.max_hp, "repair"], ["Armor", u.armor, "save"], ["Evasion", u.evasion, "evasion"], ["E-Def", u.edef, "e_def"],
			["Heat cap", u.heat_cap, "heat"], ["Speed", u.speed, "range"], ["Sensors", u.sensors, "sensor"], ["Save", u.save_target, "save"],
			["Structure", u.max_structure, "structure"], ["Stress", u.max_stress, "reactor"]]:
		stats.add_child(_stat(s[0], str(s[1]), s[2]))
	stats.add_child(_stat("SP", "%d / %d" % [sp["used"], sp["max"]], "system_point", MenuTheme.BAD if sp["used"] > sp["max"] else MenuTheme.TEXT))
	mech_box.add_child(stats)

	for mt: Dictionary in model.mounts():
		mech_box.add_child(_mount_panel(mt, accent))
	var sys_head := HBoxContainer.new()
	sys_head.add_child(MenuTheme.heading("Systems", 18))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sys_head.add_child(spacer)
	var add := Button.new()
	add.text = "+ Add system"
	add.pressed.connect(func() -> void: _pick({"kind": "system"}))
	sys_head.add_child(add)
	mech_box.add_child(sys_head)
	var systems: Array = m.get("loadout", {}).get("systems", [])
	if systems.is_empty():
		mech_box.add_child(MenuTheme.label("No systems installed.", 15, MenuTheme.MUTED))
	for i in range(systems.size()):
		var s := model.db.system(str(systems[i]))
		var h := HBoxContainer.new()
		h.add_child(MenuTheme.icon("system", 20, MenuTheme.MUTED))
		var l := MenuTheme.label("%s  ·  %s SP" % [s.get("name", systems[i]), s.get("sp", 0)], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var rm := Button.new()
		rm.text = "Remove"
		rm.pressed.connect(func() -> void: model.remove_system(i))
		h.add_child(rm)
		mech_box.add_child(h)


func _mount_panel(mt: Dictionary, accent: Color) -> Control:
	var p := PanelContainer.new()
	var st := MenuTheme.box(MenuTheme.PANEL_2, MenuTheme.LINE, 1, 0)
	st.border_width_left = 4
	st.border_color = accent
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var head := MenuTheme.label("%s MOUNT" % str(mt["type"]).to_upper(), 15, MenuTheme.MUTED)
	head.custom_minimum_size = Vector2(118, 0)
	h.add_child(head)
	var slots: int = mt["slots"]
	for s in range(slots):
		var w: Dictionary = mt["weapons"][s] if s < mt["weapons"].size() else {}
		var b := Button.new()
		b.text = w.get("name", "Empty slot")
		b.clip_text = true
		b.custom_minimum_size = Vector2(90, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if w.is_empty():
			b.add_theme_color_override("font_color", MenuTheme.MUTED)
		var selected: bool = picking.get("kind") == "weapon" and picking.get("mount") == mt["index"] and picking.get("slot") == s
		if selected:
			b.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.PANEL_2, MenuTheme.ACCENT, 2, 3))
		b.pressed.connect(func() -> void: _pick({"kind": "weapon", "mount": mt["index"], "slot": s}))
		h.add_child(b)
		if not w.is_empty():
			var clear := Button.new()
			clear.text = "✕"
			clear.tooltip_text = "Empty this slot"
			clear.pressed.connect(func() -> void: model.set_weapon(mt["index"], s, ""))
			h.add_child(clear)
	var mod := Button.new()
	mod.text = "Mod: %s" % (mt["mod_name"] if mt["mod_name"] != "" else "none")
	mod.clip_text = true
	mod.custom_minimum_size = Vector2(110, 0)
	mod.disabled = mt["weapons"].is_empty()
	mod.tooltip_text = "A weapon mod goes on this mount's weapon." if not mod.disabled else "Put a weapon here first."
	mod.pressed.connect(func() -> void: _pick({"kind": "mod", "mount": mt["index"]}))
	h.add_child(mod)
	return p


# --- Picker ------------------------------------------------------------------------------

func _pick(what: Dictionary) -> void:
	picking = what
	_refresh()


func _refresh_picker() -> void:
	_clear(picker_box)
	var options: Array = []
	match picking.get("kind", "frame"):
		"frame":
			picker_title.text = "CHOOSE A FRAME"
			options = model.frame_options()
		"weapon":
			var mt: Dictionary = model.mounts()[picking["mount"]] if picking["mount"] < model.mounts().size() else {}
			picker_title.text = "%s MOUNT · SLOT %d" % [str(mt.get("type", "")).to_upper(), int(picking["slot"]) + 1]
			options = model.weapon_options(picking["mount"], picking["slot"])
		"mod":
			picker_title.text = "WEAPON MOD"
			options = model.mod_options(picking["mount"])
		"system":
			picker_title.text = "ADD A SYSTEM"
			options = model.system_options()
	var shown := 0
	for o: Dictionary in options:
		if not o["ok"] and not o["selected"] and not show_blocked:
			continue
		picker_box.add_child(_option_row(o))
		shown += 1
	if shown == 0:
		picker_box.add_child(MenuTheme.label("Nothing can go here right now.", 16, MenuTheme.MUTED))


func _option_row(o: Dictionary) -> Control:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 58)
	b.clip_text = true
	var maker := str(o.get("source", ""))
	b.icon = MenuTheme.icon_texture(MenuTheme.maker_icon(maker) if maker != "" else "generic_item", 28,
		MenuTheme.maker_color(maker) if o["ok"] or o["selected"] else MenuTheme.MUTED.darkened(0.3))
	var lic := "" if int(o.get("license_level", 0)) == 0 else "  ·  %s rank %d" % [maker, o["license_level"]]
	b.text = "%s%s\n%s" % [o["name"], lic, o["detail"] if o["ok"] or o["selected"] else "Locked: " + str(o["reason"])]
	b.tooltip_text = str(o["detail"]) + ("" if o["ok"] else "\n\nLocked: " + str(o["reason"]))
	b.add_theme_font_size_override("font_size", 16)
	if o["selected"]:
		b.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.ACCENT.darkened(0.55), MenuTheme.ACCENT, 1, 3))
	elif not o["ok"]:
		b.add_theme_color_override("font_color", MenuTheme.MUTED)
		b.add_theme_color_override("font_hover_color", MenuTheme.BAD.lightened(0.3))
	b.pressed.connect(_choose.bind(o))
	return b


func _choose(o: Dictionary) -> void:
	if not o["ok"]:
		return  # Locked: the row already says why.
	match picking.get("kind", "frame"):
		"frame":
			model.set_frame(o["id"])
		"weapon":
			model.set_weapon(picking["mount"], picking["slot"], o["id"])
		"mod":
			model.set_mod(picking["mount"], o["id"])
		"system":
			model.add_system(o["id"])


# --- Status, import/export, leaving ---------------------------------------------------------

func _refresh_status() -> void:
	_clear(status_box)
	var problems := model.problems()
	if problems.is_empty():
		status_box.add_child(MenuTheme.chip("Legal build", MenuTheme.GOOD))
		status_box.add_child(MenuTheme.label("Everything checks out for License Level %d." % model.ll(), 16, MenuTheme.MUTED))
	else:
		status_box.add_child(MenuTheme.chip("Not legal", MenuTheme.BAD))
		var l := MenuTheme.label("  ·  ".join(problems.slice(0, 3)), 16, MenuTheme.BAD.lightened(0.25), true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_box.add_child(l)


func _import() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, func(path: String) -> void:
		var r := Compcon.import_pilot(FileAccess.get_file_as_string(path), model.db)
		if not r["ok"]:
			_popup("Couldn't import", r["errors"], MenuTheme.BAD)
			return
		var c := MenuSession.campaign
		c.add_pilot(r["pilot"], model.db)
		MenuSession.store.save_campaign(c)
		MenuSession.builder_pilot = r["pilot"]["id"]
		model = BuilderModel.new(model.db, r["pilot"])
		model.changed.connect(_refresh)
		_refresh()
		if not r["warnings"].is_empty():
			_popup("Imported %s, with notes" % r["pilot"]["callsign"], r["warnings"], MenuTheme.WARN))


func _export() -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_popup("Couldn't save", ["That folder can't be written to."], MenuTheme.BAD)
			return
		f.store_string(JSON.stringify(Compcon.export_pilot(model.pilot, model.db), "\t"))
		_popup("Exported", ["Saved %s. Import it in COMP/CON from its pilot roster." % path.get_file()], MenuTheme.GOOD))


func _file_dialog(mode: FileDialog.FileMode, done: Callable) -> void:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.json ; COMP/CON pilot"])
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		_dialog.current_file = "%s.json" % str(model.pilot.get("callsign", "pilot")).to_lower().replace(" ", "_")
	_dialog.file_selected.connect(done)
	add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _popup(title: String, lines: Array, color: Color) -> void:
	var pop := PopupPanel.new()
	var p := MenuTheme.panel(title, color)
	p.custom_minimum_size = Vector2(720, 0)
	for line in lines.slice(0, 12):
		MenuTheme.body(p).add_child(MenuTheme.label("•  " + str(line), 16, MenuTheme.TEXT, true))
	var ok := Button.new()
	ok.text = "OK"
	ok.pressed.connect(pop.queue_free)
	MenuTheme.body(p).add_child(ok)
	pop.add_child(p)
	add_child(pop)
	pop.popup_centered()


func _done() -> void:
	var c := MenuSession.campaign
	if c != null and c.pilots.has(model.pilot["id"]):
		c.pilots[model.pilot["id"]] = model.pilot
		MenuSession.store.save_campaign(c)
	if MenuSession.lobby != null and MenuSession.lobby.is_host:
		MenuSession.lobby.assign_pilot(MenuSession.lobby.seats()[0], MenuSession.lobby.assignment[MenuSession.lobby.seats()[0]])
	MenuSession.go(self, MenuSession.back_to)


# --- Little pieces -----------------------------------------------------------------------

func _step_button(text: String, enabled: bool, reason: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(38, 34)
	b.disabled = not enabled
	b.tooltip_text = reason if not enabled else ""
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(action)
	return b


func _stat(name: String, value: String, icon_name: String, color: Color = MenuTheme.TEXT) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.BG, MenuTheme.LINE, 1, 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(MenuTheme.icon(icon_name, 20, MenuTheme.MUTED))
	h.add_child(MenuTheme.label(name.to_upper(), 13, MenuTheme.MUTED))
	h.add_child(MenuTheme.heading(value, 18, color))
	p.add_child(h)
	return p


static func _centered(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


## Removes children (keeping the first `keep`, e.g. a panel header).
static func _clear(box: Container, keep: int = 0) -> void:
	var kids := box.get_children()
	for i in range(keep, kids.size()):
		box.remove_child(kids[i])
		kids[i].queue_free()
