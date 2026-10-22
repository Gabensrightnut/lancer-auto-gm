extends Control
## Customizer demo: the mech paint preview (and the pilot creator) on their own screen, for
## checking by screenshot:
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/customizer.tscn "out_%s.jpg" 20 paint_factory paint_preset paint_random paint_everest

var content: ContentDB
var preview: MechPreview
var panel: PanelContainer
var _sheet: Control


func _ready() -> void:
	content = ContentDB.new()
	content.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.075)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	panel = PanelContainer.new()
	panel.position = Vector2(560, 40)
	panel.size = Vector2(800, 1000)
	add_child(panel)
	preview = MechPreview.new()
	panel.add_child(preview)
	_show("mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}]})


func _show(frame_id: String, loadout: Dictionary, paint: Dictionary = {}) -> void:
	preview.set_mech(content, frame_id, loadout, paint)


func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["paint_factory"]


func screenshot_stage(tag: String) -> void:
	panel.visible = tag.begins_with("paint")
	if _sheet:
		_sheet.queue_free()
		_sheet = null
	match tag:
		"creator_portrait", "creator_token", "creator_beard":
			var pc := PilotCreator.new()
			add_child(pc)
			_sheet = pc
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			pc.open(PortraitSpec.randomize(rng))
			pc.toggle_lock("hair")
			pc.toggle_lock("face")
			if tag == "creator_beard":
				pc.select_part("beard")
				pc.set_expression("smiling")
			if tag == "creator_token":
				pc.set_tab("token")
		"dialogue":
			# How story's dialogue would look with PortraitArt: speaker lit, listener dimmed,
			# the NPC mirrored to face the pilot.
			var box := Control.new()
			box.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(box)
			_sheet = box
			var rng := RandomNumberGenerator.new()
			rng.seed = 33
			var pilot := PortraitArt.new()
			pilot.set_look(PortraitArt.look_for_pilot({"id": "hawk", "portrait": PortraitSpec.randomize(rng)}), "determined")
			pilot.size = Vector2(300, 360)
			pilot.position = Vector2(40, 1080 - 360 - 60)
			box.add_child(pilot)
			var npc := PortraitArt.new()
			npc.set_look(PortraitArt.look_for_npc({"id": "quartermaster_vell"}), "smug")
			npc.flip = true
			npc.lit = false
			npc.size = Vector2(300, 360)
			npc.position = Vector2(1920 - 340, 1080 - 360 - 60)
			box.add_child(npc)
			var bubble := Label.new()
			bubble.text = "HAWK:  \"We'll take the contract. But the price goes up if they've got artillery.\""
			bubble.add_theme_font_size_override("font_size", 24)
			bubble.position = Vector2(380, 1080 - 200)
			box.add_child(bubble)
		"portraits":
			# A grid of random pilots.
			var grid := GridContainer.new()
			grid.columns = 6
			grid.position = Vector2(40, 30)
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			add_child(grid)
			_sheet = grid
			var rng := RandomNumberGenerator.new()
			rng.seed = int(tag.hash()) & 0xffff
			for i in range(12):
				var pa := PortraitArt.new()
				pa.custom_minimum_size = Vector2(290, 330)
				pa.set_look(PortraitSpec.randomize(rng), PortraitArt.EXPRESSIONS[i % PortraitArt.EXPRESSIONS.size()])
				grid.add_child(pa)
		"expressions":
			var grid := GridContainer.new()
			grid.columns = 5
			grid.position = Vector2(40, 30)
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			add_child(grid)
			_sheet = grid
			var rng := RandomNumberGenerator.new()
			rng.seed = 21
			var look := PortraitSpec.randomize(rng)
			for e: String in PortraitArt.EXPRESSIONS:
				var pa := PortraitArt.new()
				pa.custom_minimum_size = Vector2(350, 400)
				pa.set_look(look, e)
				grid.add_child(pa)
		"paint_factory":
			_show("mf_lancaster", {"mounts": [{"weapons": ["mw_assault_rifle"]}]})
		"paint_preset":
			_show("mf_lancaster", {"mounts": [{"weapons": ["mw_assault_rifle"]}]},
				{"primary": "#e6b422", "secondary": "#2c2f35", "glow": "#ff9a26", "markings": "#131417",
				"decals": {"chest": "hazard", "shoulder_l": "number:07", "shoulder_r": "chevron"}})
		"paint_random":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			_show("mf_raleigh", {"mounts": [{"weapons": ["mw_pistol"]}]})
			preview.randomize_paint(rng)
		"paint_everest":
			_show("mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}]},
				{"primary": "#1f4466", "secondary": "#c9c7c0", "glow": "#59d8ff", "markings": "#f2f0ea",
				"decals": {"chest": "roundel", "shoulder_r": "number:12", "leg_l": "stripes"}})
	await get_tree().process_frame
