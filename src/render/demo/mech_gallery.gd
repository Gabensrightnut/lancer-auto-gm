extends Node3D
## Lines up every frame in lancer-data with a demo loadout, labelled, for checking the
## generated models. Run: tools/screenshot.gd -- res://scenes/mech_gallery.tscn out.png
## Optional: `-- ... weapons` shows every weapon model instead.

var view: BattleView


func _ready() -> void:
	var content := ContentDB.new()
	content.load_all()
	view = BattleView.new()
	add_child(view)
	var show_weapons := "weapons" in OS.get_cmdline_user_args()
	var map := BattleMap.flat(GridLayout.Shape.SQUARE, 24, 14)
	view.set_map(map)
	view.terrain.set_grid_visible(false)
	if show_weapons:
		_weapons(content)
	else:
		_frames(content)


func _frames(content: ContentDB) -> void:
	var frames: Array = content.all("frames")
	var per_row := 10
	var x := 0.0
	var z := 2.0
	for i in range(frames.size()):
		var f: Dictionary = frames[i]
		var mech := MechBuilder.build(f, DemoLoadouts.for_frame(f, content), content)
		if i % per_row == 0 and i > 0:
			x = 0.0
			z += 3.6
		var w := maxf(1.0, float(f["stats"]["size"])) * 1.1 + 0.8
		x += w * 0.5
		mech.set_meta("x", x)
		mech.position = Vector3(x, 0, z)
		mech.rotation_degrees.y = 200
		view.add_child(mech)
		var label := Label3D.new()
		label.text = "%s\n%s  S%s" % [f["name"], f["source"], str(f["stats"]["size"])]
		label.font_size = 40
		label.pixel_size = 0.004
		label.position = Vector3(x, 0.02, z + 1.2)
		x += w * 0.5
		label.rotation_degrees.x = -70
		label.modulate = MechStyles.palette(f["source"])["glow"].lightened(0.3)
		view.add_child(label)
	view.tactical.look_at_point(Vector3(13.0, 0.6, 5.6), 17.0)
	view.tactical.pitch = -38
	view.tactical.yaw = 0
	view.tactical.snap()


func _weapons(content: ContentDB) -> void:
	var list: Array = content.all("weapons")
	var per_row := 12
	for i in range(list.size()):
		var w: Dictionary = list[i]
		var model := WeaponBuilder.build(w)
		var x := (i % per_row) * 1.7 + 1.0
		var z := (i / per_row) * 1.25 + 1.0
		model.position = Vector3(x, 0.3, z)
		model.rotation_degrees.y = 90
		model.scale = Vector3.ONE * 1.6
		view.add_child(model)
		var label := Label3D.new()
		label.text = "%s\n%s %s %s" % [w["name"], w.get("source", "-"), w.get("mount", ""), w.get("type", "")]
		label.font_size = 28
		label.pixel_size = 0.0035
		label.position = Vector3(x, 0.02, z + 0.35)
		label.rotation_degrees.x = -90
		view.add_child(label)
	view.tactical.look_at_point(Vector3(10.2, 0, 5.0), 15.5)
	view.tactical.pitch = -80
	view.tactical.yaw = 0
	view.tactical.snap()


## Screenshot hook: "row0".."row2" frames one row up close.
func screenshot_setup(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("row"):
			var r := int(a.substr(3))
			view.tactical.look_at_point(Vector3(9.0 if r < 2 else 7.0, 0.7, 2.0 + r * 3.6), 9.5)
			view.tactical.pitch = -22
			view.tactical.snap()
