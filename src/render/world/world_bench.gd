extends SceneTree
## Frame-rate benchmark for battlefields: a generated 40x40 mission with its whole roster in
## the battle view, vsync off, at 1080p. Prints average fps and 1% low per kit and view.
##   godot --path . -s res://src/render/world/world_bench.gd -- [quality] [kit ...]
## quality: high (default), medium, low. Kits: landscape[/culture] (default: a mix).

const WARMUP := 1.5
const MEASURE := 4.0

var _view: BattleView
var _frames: PackedFloat32Array = []
var _eye: Camera3D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var quality := "high"
	if not args.is_empty() and args[0] in WorldQuality.PRESETS:
		quality = args[0]
		args = args.slice(1)
	var kits: Array = args if not args.is_empty() else ["grassy_hills/medieval", "city/cyberpunk", "alien_wilds", "desert_mesas/old_west", "city/burning"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var db := ContentDB.new()
	db.load_all()
	_view = BattleView.new()
	_view.content = db
	root.add_child(_view)
	WorldQuality.set_preset(quality, root)
	print("quality %s, %s, %s" % [quality, root.size, RenderingServer.get_video_adapter_name()])
	for kit: String in kits:
		var weather := kit.get_slice("+", 1) if "+" in kit else "clear"
		var parts := kit.get_slice("+", 0).split("/")
		var sz := int(OS.get_environment("LANCER_BENCH_SIZE")) if OS.get_environment("LANCER_BENCH_SIZE") != "" else 40
		var t_build := Time.get_ticks_msec()
		var g := MissionGenerator.generate(40, {"db": db, "size": sz, "height": sz, "landscape": parts[0], "culture": parts[1] if parts.size() > 1 else "", "weather": weather})
		var state: GameState = g["state"]
		var t_gen := Time.get_ticks_msec() - t_build
		t_build = Time.get_ticks_msec()
		_view.set_map(state.map, g["mission"].flavor["kit"])
		print("%-24s %dx%d  generate %d ms, build %d ms" % [kit, sz, sz, t_gen, Time.get_ticks_msec() - t_build])
		_view.clear_units()
		var v := ViewFilter.new().view_for(state, "gm")
		var n := 0
		for id: String in v.get("units", {}):
			if n >= 8:
				break
			_view.add_unit(v["units"][id])
			n += 1
		for cam: String in ["wide", "close", "eye"]:
			_aim(state.map, cam)
			var r := await _measure()
			print("%-24s %-5s %d units  avg %5.1f fps  1%% low %5.1f fps  (%d frames)" % [kit, cam, n, r[0], r[1], r[2]])
	quit()


func _aim(map: BattleMap, cam: String) -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in map.cells():
		var p := map.grid.to_world(c)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var mid := (lo + hi) * 0.5
	var t := _view.tactical
	if _eye:
		_eye.queue_free()
		_eye = null
		t.camera.current = true
	if cam == "eye":
		# Cockpit height: a mech's eye about 1.1 units above the ground, looking across.
		var c := map.grid.from_world(mid)
		_eye = Camera3D.new()
		_eye.fov = 75.0
		_eye.near = 0.02
		_eye.far = 400.0
		_view.add_child(_eye)
		_eye.position = map.grid.to_world(c) + Vector3.UP * (map.ground_height(c) + 1.1)
		_eye.look_at(_eye.position + Vector3(0.5, -0.1, -1.0), Vector3.UP)
		_eye.current = true
		return
	if cam == "close":
		t.look_at_point(mid + Vector3(0, 1, 0), 12.0)
		t.pitch = -32
	else:
		t.look_at_point(mid + Vector3(0, 1, 0), (hi.x - lo.x) * 0.95)
		t.pitch = -45
	t.yaw = -20
	t.snap()


func _measure() -> Array:
	var t := 0.0
	while t < WARMUP:
		await process_frame
		t += Engine.get_main_loop().root.get_process_delta_time()
	_frames = []
	t = 0.0
	var last := Time.get_ticks_usec()
	while t < MEASURE:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		_frames.append(dt)
		t += dt
		# Slowly turn so the view keeps changing.
		if _eye:
			_eye.rotate_y(deg_to_rad(20.0) * dt)
		else:
			_view.tactical.yaw += 20.0 * dt
			_view.tactical.snap()
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var worst := sorted.slice(int(sorted.size() * 0.99))
	var worst_avg := 0.0
	for f in worst:
		worst_avg += f
	worst_avg /= maxf(1.0, worst.size())
	return [_frames.size() / total, 1.0 / maxf(worst_avg, 1e-6), _frames.size()]
