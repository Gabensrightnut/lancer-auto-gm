extends SceneTree
## Frame-rate benchmark for battlefields: a generated 40x40 mission with its whole roster in
## the battle view, vsync off, at 1080p. Prints average fps and 1% low per kit and view.
##   godot --path . -s res://src/render/world/world_bench.gd -- [quality] [kit ...]
## quality: high (default), medium, low. Kits: landscape[/culture] (default: a mix).

const WARMUP := 1.5
const MEASURE := 4.0

var _view: BattleView
var _frames: PackedFloat32Array = []


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
		var parts := kit.split("/")
		var g := MissionGenerator.generate(40, {"db": db, "size": 40, "landscape": parts[0], "culture": parts[1] if parts.size() > 1 else ""})
		var state: GameState = g["state"]
		_view.set_map(state.map, g["mission"].flavor["kit"])
		_view.clear_units()
		var v := ViewFilter.new().view_for(state, "gm")
		var n := 0
		for id: String in v.get("units", {}):
			if n >= 8:
				break
			_view.add_unit(v["units"][id])
			n += 1
		for cam: String in ["wide", "close"]:
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
		# Slowly orbit so the view keeps changing.
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
