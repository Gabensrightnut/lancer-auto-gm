extends Control
## Customizer demo: the mech paint preview (and the pilot creator) on their own screen, for
## checking by screenshot:
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/customizer.tscn "out_%s.jpg" 20 paint_factory paint_preset paint_random paint_everest

var content: ContentDB
var preview: MechPreview


func _ready() -> void:
	content = ContentDB.new()
	content.load_all()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.075)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
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
	match tag:
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
