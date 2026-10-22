extends Node3D
## People check: HumanFigure close up (a lineup of looks and animations) and a hub crowd of
## ~30 with a frame-rate readout.
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/people.tscn "out_%s.jpg" 20 close hub

var cam: Camera3D
var _crowd: Array = []


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.58, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.4, 0.36)
	ground.material_override = gm
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 35
	add_child(cam)


func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["close"]


func _clear() -> void:
	for f in _crowd:
		(f as Node).queue_free()
	_crowd.clear()


func _person(seed: int, at: Vector3, anim: String, opts: Dictionary = {}) -> HumanFigure:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var f := HumanFigure.new().build(PortraitSpec.randomize(rng), opts)
	f.position = at
	add_child(f)
	f.play(anim)
	_crowd.append(f)
	return f


func screenshot_stage(tag: String) -> void:
	_clear()
	match tag:
		"close":
			var anims := ["idle", "walk", "talk", "aim", "run", "sneak"]
			for i in range(6):
				var f := _person(100 + i * 7, Vector3((i - 2.5) * 1.1, 0, 0), anims[i], {"gear": {"pack": i % 2 == 0, "rifle": i in [3, 4]}})
				f.rotation_degrees.y = 160.0 + i * 8.0
			_look(Vector3(0, 1.0, 0), Vector3(0, 1.55, 7.8))
		"faces":
			# The 10 expressions, heads close up.
			var ex: Array = HumanFigure.EXPRESSIONS.keys()
			for i in range(ex.size()):
				var rng := RandomNumberGenerator.new()
				rng.seed = 700 + i
				var lk := PortraitSpec.randomize(rng)
				for part: String in ["hats", "glasses", "beard", "mustache", "scarves"]:
					lk["parts"][part]["option"] = "none"
				var f := HumanFigure.new().build(lk)
				f.position = Vector3((i - 4.5) * 0.5, 0, 0)
				add_child(f)
				_crowd.append(f)
				f.rotation_degrees.y = 180
				f.set_expression(ex[i])
				f.set_process(false)  # hold the face still (no blinks) for the shot
				f._face_now = (HumanFigure.EXPRESSIONS[ex[i]] as Dictionary).duplicate()
				for k: String in HumanFigure.FACE_KEYS:
					var idx := f._face_mesh.find_blend_shape_by_name(k)
					if idx >= 0:
						f._face_mesh.set_blend_shape_value(idx, float(f._face_now.get(k, 0.0)))
			_look(Vector3(0, 1.66, 0), Vector3(0, 1.68, 2.6))
		"dialogue":
			# Two people talking: the speaker turns to the listener, mouth moving.
			var a := _person(41, Vector3(-0.8, 0, 0), "idle")
			var b := _person(42, Vector3(0.8, 0, 0.3), "idle")
			a.rotation_degrees.y = 210
			b.rotation_degrees.y = 150
			a.look_at_target(b)
			b.look_at_target(a)
			b.set_expression("worried")
			a.speak("We hold the ridge until the convoy is through. No arguments.", "determined", 10.0)
			for i in range(20):
				await get_tree().process_frame
			_look(Vector3(0, 1.45, 0.1), Vector3(0.2, 1.65, 3.6))
		"portrait_match":
			# Portrait next to its figure, for the "looks like their portrait" check.
			var f := _person(5, Vector3(0.6, 0, 0), "idle", {"gear": {"pack": true}})
			f.rotation_degrees.y = 200
			_look(Vector3(0.3, 1.0, 0), Vector3(0.3, 1.4, 3.8))
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			var layer := CanvasLayer.new()
			add_child(layer)
			_crowd.append(layer)
			var pa := PortraitArt.new()
			pa.set_look(PortraitSpec.randomize(rng))
			pa.position = Vector2(140, 200)
			pa.size = Vector2(520, 600)
			layer.add_child(pa)
		"hub":
			var anims := ["idle", "walk", "talk", "idle", "sit", "run"]
			for i in range(30):
				var a := Vector3((i % 6 - 2.5) * 2.4, 0, (i / 6 - 2) * 2.4) + Vector3(sin(i * 1.7), 0, cos(i * 2.3)) * 0.5
				var f := _person(300 + i, a, anims[i % anims.size()], {"gear": {"pack": i % 3 == 0}})
				f.rotation_degrees.y = i * 47.0
			_look(Vector3(0, 0.8, 0), Vector3(0, 11, 17))
			await _measure("hub, 30 people")
			return
	await get_tree().process_frame


func _look(at: Vector3, from: Vector3) -> void:
	cam.global_transform = Transform3D(Basis.looking_at(at - from), from)


func _measure(label: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in range(30):
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in range(240):
		cam.global_transform = cam.global_transform.rotated(Vector3.UP, 0.003)
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1e6
	print("PERF %s: %.1f fps, draw calls %d, primitives %d" % [label, 240.0 / dt,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
